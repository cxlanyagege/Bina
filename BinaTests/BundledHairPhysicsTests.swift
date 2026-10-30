import Foundation
import RealityKit
import XCTest
@testable import Bina

@MainActor
final class BundledHairPhysicsTests: XCTestCase {
    func testActualHairDoesNotCrossTheSelectedCollarRegion() async throws {
        let f = try await HairFixture()
        let geometry = try HairCollarGeometry(model: f.model)
        // Hard motion bounds can leave approximate proxies overlapping; require
        // clearance of the rendered surfaces rather than relaxing those bounds.
        for offset: SIMD3<Float> in [[0,0,-2],[-1.5,0,-2],[1.5,0,-2],[0,1.2,-2],[0,-1.2,-2],[-1.5,0.8,-2],[1.5,-0.8,-2]] {
            f.motion.showReference(); f.motion.showNatural()
            f.advance(180, target: f.head + offset)
            XCTAssertEqual(try geometry.crossingCount(), 0, "Hair crosses the selected collar region at target \(offset).")
        }
    }

    func testOnlySelectedAccessoryRotationsChange() async throws {
        let f = try await HairFixture()
        let control = f.character.clone(recursive: true)
        let controlModel = try XCTUnwrap(HairFixture.rig(control))
        controlModel.jointTransforms = f.reference
        let baseline = try CharacterIdleMotion(character: control, pose: f.pose)
        let first = f.model.jointTransforms
        let placement = f.character.transform.matrix
        for _ in 0..<180 {
            let target = f.head + SIMD3<Float>(1.5,0.5,-2)
            f.motion.advance(by: 1.0/60, isVisible: true, attentionTarget: target)
            baseline.advance(by: 1.0/60, isVisible: true, attentionTarget: target)
        }
        let selected = Set(f.profile.chains.flatMap(\.joints))
        var changed = 0
        for (i, name) in f.model.jointNames.enumerated() {
            let actual = f.model.jointTransforms[i], expected = controlModel.jointTransforms[i]
            if selected.contains(String(name.split(separator: "/").last!)) {
                XCTAssertLessThan(simd_distance(actual.translation, expected.translation), 0.000001)
                XCTAssertLessThan(simd_distance(actual.scale, expected.scale), 0.000001)
                if matrixError(actual.matrix, expected.matrix) > 0.001 { changed += 1 }
            } else { XCTAssertLessThan(matrixError(actual.matrix, expected.matrix), 0.000001) }
        }
        XCTAssertGreaterThan(changed, 0)
        XCTAssertLessThan(matrixError(f.character.transform.matrix, placement), 0.000001)
        XCTAssertGreaterThan(zip(first, f.model.jointTransforms).map { matrixError($0.matrix, $1.matrix) }.max() ?? 0, 0.01)
    }

    func testPauseToggleAndReferenceFreezeOrRestoreTheCompletePose() async throws {
        let f = try await HairFixture()
        f.advance(120, target: f.head + [1.5,0,-2])
        f.motion.pause()
        let paused = f.model.jointTransforms
        let reset = f.motion.hairPhysicsDiagnostics?.resetCount
        f.motion.isHairPhysicsEnabled = false
        let originalOpacity = f.model.components[OpacityComponent.self]?.opacity
        f.motion.showsPhysicsDebug = true
        XCTAssertEqual(try XCTUnwrap(f.model.components[OpacityComponent.self]).opacity, (originalOpacity ?? 1) * 0.3, accuracy: 0.000001)
        f.advance(120, target: f.head + [-1.5,0,-2])
        assertPose(f.model.jointTransforms, paused)
        XCTAssertEqual(f.motion.hairPhysicsDiagnostics?.resetCount, reset)
        f.motion.showReference()
        XCTAssertEqual(f.model.components[OpacityComponent.self]?.opacity, originalOpacity)
        assertPose(f.model.jointTransforms, f.reference)
        f.advance(60, target: f.head + [1.5,0,-2])
        assertPose(f.model.jointTransforms, f.reference)
        f.motion.isHairPhysicsEnabled = true
        f.motion.showNatural()
        assertPose(f.model.jointTransforms, f.reference)
        f.advance(180, target: f.head + [-1.5,0,-2])
        XCTAssertTrue(f.motion.isHairPhysicsAvailable)
        XCTAssertLessThan(try XCTUnwrap(f.motion.hairPhysicsDiagnostics).maximumPenetration, 0.001)
    }

    func testInterruptionPlacementScaleAndFrameGapResetHistory() async throws {
        let f = try await HairFixture()
        f.advance(120, target: f.head + [1.5,0,-2])
        let paused = f.model.jointTransforms
        var count = try XCTUnwrap(f.motion.hairPhysicsDiagnostics).resetCount
        f.motion.advance(by: 20, isVisible: false, attentionTarget: f.head)
        assertPose(f.model.jointTransforms, paused)
        f.advance(1, target: nil)
        XCTAssertGreaterThan(try XCTUnwrap(f.motion.hairPhysicsDiagnostics).resetCount, count)
        count = try XCTUnwrap(f.motion.hairPhysicsDiagnostics).resetCount
        let parent = Entity(); parent.addChild(f.character)
        parent.position = [2,0,1]; parent.scale = [0.5,0.5,0.5]
        f.advance(1, target: nil)
        XCTAssertGreaterThan(try XCTUnwrap(f.motion.hairPhysicsDiagnostics).resetCount, count)
        count = try XCTUnwrap(f.motion.hairPhysicsDiagnostics).resetCount
        f.motion.advance(by: 10, isVisible: true)
        XCTAssertGreaterThan(try XCTUnwrap(f.motion.hairPhysicsDiagnostics).resetCount, count)
        XCTAssertTrue(f.model.jointTransforms.allSatisfy { t in (0..<4).allSatisfy { t.rotation.vector[$0].isFinite } })
    }

    func testInvalidProfileCannotReplaceAWorkingBindingAndFailureRetainsPrimaryMotion() async throws {
        let f = try await HairFixture()
        let invalid = CharacterPhysicsProfile(schemaVersion: 1, modelSHA256: String(repeating: "a", count: 64),
            chains: f.profile.chains, colliders: f.profile.colliders)
        XCTAssertThrowsError(try f.motion.configureHairPhysics(invalid, pose: f.pose))
        XCTAssertTrue(f.motion.isHairPhysicsAvailable)
        f.motion.recordPhysicsTiming()
        XCTAssertNotNil(f.motion.physicsTimingDescription)
        f.motion.reportHairPhysicsUnavailable(CharacterPhysicsError.unstableSimulation)
        XCTAssertFalse(f.motion.isHairPhysicsAvailable)
        XCTAssertNotNil(f.motion.hairPhysicsMessage)
        let phase = f.motion.cycleTime
        f.advance(60, target: f.head + [1,0,-2])
        XCTAssertGreaterThan(f.motion.cycleTime, phase)
    }

    func testRearLocksCannotFoldOrTwistOverDuringContinuousHeadMotion() async throws {
        for fps in [30,60,90,120] {
            let f = try await HairFixture()
            let control = try f.control(simulatesHair: false)
            let skeleton = try XCTUnwrap(f.model.model?.mesh.contents.skeletons.first)
            let chains = f.profile.chains.filter { $0.maximumChainAngle != nil }
            XCTAssertEqual(chains.count, 2)
            let indices = Dictionary(uniqueKeysWithValues: f.model.jointNames.enumerated().map {
                (String($0.element.split(separator: "/").last!), $0.offset)
            })
            var previous: [simd_quatf] = []
            var maximumDeviation: Float = 0, maximumSpeed: Float = 0
            for frame in 0..<(fps * 8) {
                let phase = Float(frame) / Float(fps) * 2 * Float.pi / 4
                let target = f.head + SIMD3<Float>(1.6 * sin(phase), 0.9 * cos(phase * 1.5), -2)
                f.motion.advance(by: 1 / Double(fps), isVisible: true, attentionTarget: target)
                control.motion.advance(by: 1 / Double(fps), isVisible: true, attentionTarget: target)
                let actual = globalRotations(f.model, skeleton: skeleton)
                let primary = globalRotations(control.model, skeleton: skeleton)
                var current: [simd_quatf] = []
                for chain in chains { for name in chain.joints {
                    let i = try XCTUnwrap(indices[name])
                    let difference = rotationDistance(actual[i], primary[i])
                    maximumDeviation = max(maximumDeviation, difference)
                    current.append(actual[i])
                } }
                if !previous.isEmpty, frame > fps {
                    for (before, after) in zip(previous, current) {
                        maximumSpeed = max(maximumSpeed, rotationDistance(before, after) * Float(fps))
                    }
                }
                previous = current
            }
            XCTAssertLessThanOrEqual(maximumDeviation, 0.651, "Rear lock folds or twists at \(fps) FPS.")
            XCTAssertLessThan(maximumSpeed, 4, "Rear lock jumps during continuous motion at \(fps) FPS.")
            XCTAssertEqual(f.motion.hairPhysicsDiagnostics?.resetCount, 1)
        }
    }

    func testHeadingSliderDoesNotReplayWarmUpOrChangeTheLocalHairMotion() async throws {
        let f = try await HairFixture()
        let control = try f.control(simulatesHair: true)
        let target = SIMD4(f.head + SIMD3<Float>(0,0,-2), 1)
        let characterTarget = simd_inverse(f.character.transformMatrix(relativeTo: nil)) * target
        f.advance(120, target: SIMD3(target.x,target.y,target.z))
        for _ in 0..<120 { control.motion.advance(by: 1.0/60, isVisible: true, attentionTarget: SIMD3(target.x,target.y,target.z)) }
        let resetCount = try XCTUnwrap(f.motion.hairPhysicsDiagnostics).resetCount
        var maximumError: Float = 0
        for frame in 0..<360 {
            // The appearance slider emits five-degree steps, including its wrap boundary.
            f.character.orientation = simd_quatf(angle: Float(frame * 5) * .pi / 180, axis: [0,1,0])
            let rotatedTarget = f.character.transformMatrix(relativeTo: nil) * characterTarget
            f.motion.advance(by: 1.0/60, isVisible: true, attentionTarget: SIMD3(rotatedTarget.x,rotatedTarget.y,rotatedTarget.z))
            control.motion.advance(by: 1.0/60, isVisible: true, attentionTarget: SIMD3(target.x,target.y,target.z))
            maximumError = max(maximumError, zip(f.model.jointTransforms, control.model.jointTransforms).map {
                matrixError($0.matrix, $1.matrix)
            }.max() ?? 0)
        }
        XCTAssertEqual(f.motion.hairPhysicsDiagnostics?.resetCount, resetCount)
        XCTAssertLessThan(maximumError, 0.0001)
    }

    private func globalRotations(_ model: ModelEntity, skeleton: MeshResource.Skeleton) -> [simd_quatf] {
        var globals: [simd_quatf] = []
        for (i, joint) in skeleton.joints.enumerated() {
            let rotation = model.jointTransforms[i].rotation
            globals.append(simd_normalize(joint.parentIndex.map { globals[$0] * rotation } ?? rotation))
        }
        return globals
    }

    private func rotationDistance(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(1, abs(simd_dot(a.vector, b.vector))))
    }

    private func assertPose(_ actual: [Transform], _ expected: [Transform]) {
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertLessThan(zip(actual, expected).map { matrixError($0.matrix, $1.matrix) }.max() ?? 0, 0.000001)
    }

    private func matrixError(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        (0..<4).flatMap { c in (0..<4).map { r in abs(a[c][r] - b[c][r]) } }.max() ?? 0
    }
}

@MainActor
private final class HairFixture {
    let character: Entity
    let model: ModelEntity
    let reference: [Transform]
    let pose: CharacterIdlePose
    let profile: CharacterPhysicsProfile
    let motion: CharacterIdleMotion
    let head: SIMD3<Float>

    init() async throws {
        guard let modelURL = CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main) else {
            throw XCTSkip("The local-only character asset is not bundled in this checkout.")
        }
        let poseURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaIdlePose", extension: "json", in: .main))
        let profileURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaPhysics", extension: "json", in: .main))
        character = try await CharacterAsset.load()
        model = try XCTUnwrap(Self.rig(character))
        reference = model.jointTransforms
        pose = try await CharacterIdlePose.load(modelURL: modelURL, poseURL: poseURL)
        profile = try await CharacterPhysicsProfile.load(modelURL: modelURL, profileURL: profileURL)
        motion = try await CharacterAsset.loadIdleMotion(for: character)
        guard motion.isHairPhysicsAvailable else { throw CharacterPhysicsError.invalidBinding(motion.hairPhysicsMessage ?? "Physics failed to load.") }
        let skeleton = try XCTUnwrap(model.model?.mesh.contents.skeletons.first)
        let index = try XCTUnwrap(model.jointNames.firstIndex { $0.split(separator: "/").last == "Joint_0041" })
        var i = index, matrix = reference[index].matrix
        while let parent = skeleton.joints[i].parentIndex { matrix = reference[parent].matrix * matrix; i = parent }
        let p = (model.transformMatrix(relativeTo: nil) * matrix).columns.3
        head = SIMD3(p.x,p.y,p.z)
    }

    func advance(_ frames: Int, target: SIMD3<Float>?) {
        for _ in 0..<frames { motion.advance(by: 1.0/60, isVisible: true, attentionTarget: target) }
    }

    func control(simulatesHair: Bool) throws -> (character: Entity, model: ModelEntity, motion: CharacterIdleMotion) {
        let character = character.clone(recursive: true)
        let model = try XCTUnwrap(Self.rig(character))
        model.jointTransforms = reference
        let motion = try CharacterIdleMotion(character: character, pose: pose)
        if simulatesHair { try motion.configureHairPhysics(profile, pose: pose) }
        return (character, model, motion)
    }

    static func rig(_ entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        for child in entity.children { if let result = rig(child) { return result } }
        return nil
    }
}

/// CPU skinning of the imported mesh, independent of the spring collision proxies.
@MainActor
private struct HairCollarGeometry {
    struct Part {
        let hair: Bool
        let positions: [SIMD3<Float>]
        let influences: [MeshJointInfluence]
        let stride: Int
        let triangles: [UInt32]
    }
    let model: ModelEntity
    let skeleton: MeshResource.Skeleton
    let parts: [Part]

    init(model: ModelEntity) throws {
        self.model = model
        let component = try XCTUnwrap(model.model)
        skeleton = try XCTUnwrap(component.mesh.contents.skeletons.first)
        var parts: [Part] = []
        for mesh in component.mesh.contents.models { for part in mesh.parts {
            let name = component.materials[part.materialIndex].name ?? ""
            guard ["CharacterMaterial_22","CharacterMaterial_23","CharacterMaterial_00","CharacterMaterial_05"].contains(name) else { continue }
            let points = part.positions.elements
            let weights = try XCTUnwrap(part.jointInfluences?.influences.elements)
            let indices = try XCTUnwrap(part.triangleIndices?.elements)
            guard !points.isEmpty, weights.count % points.count == 0, indices.count % 3 == 0 else {
                throw CharacterPhysicsError.invalidBinding("Incomplete test skinning geometry.")
            }
            parts.append(Part(hair: ["CharacterMaterial_22","CharacterMaterial_23"].contains(name), positions: points, influences: weights,
                              stride: weights.count / points.count, triangles: indices))
        } }
        self.parts = parts
    }

    func crossingCount() throws -> Int {
        var globals: [simd_float4x4] = []
        for (i,joint) in skeleton.joints.enumerated() {
            globals.append(joint.parentIndex.map { globals[$0] * model.jointTransforms[i].matrix } ?? model.jointTransforms[i].matrix)
        }
        let skin = zip(globals, skeleton.joints).map { $0 * $1.inverseBindPoseMatrix }
        let world = model.transformMatrix(relativeTo: nil)
        var hair: [TestTriangleGeometry.Triangle] = [], cloth: [TestTriangleGeometry.Triangle] = []
        let lower = SIMD3<Float>(-0.18,1.18,-0.34), upper = SIMD3<Float>(0.18,1.32,0.08)
        for part in parts {
            let points = part.positions.enumerated().map { i,p -> SIMD3<Float> in
                var point = SIMD4<Float>(repeating: 0)
                for j in 0..<part.stride {
                    let w = part.influences[i * part.stride + j]
                    point += (skin[w.jointIndex] * SIMD4(p,1)) * w.weight
                }
                let result = world * point
                return SIMD3(result.x,result.y,result.z)
            }
            for i in stride(from: 0, to: part.triangles.count, by: 3) {
                let t = TestTriangleGeometry.Triangle(a: points[Int(part.triangles[i])], b: points[Int(part.triangles[i+1])], c: points[Int(part.triangles[i+2])])
                guard !any(t.maximum .< lower), !any(t.minimum .> upper) else { continue }
                if part.hair { hair.append(t) } else { cloth.append(t) }
            }
        }
        guard !hair.isEmpty, !cloth.isEmpty else { throw CharacterPhysicsError.invalidBinding("Empty collar test region.") }
        var count = 0
        for a in hair { for b in cloth {
            guard !any(a.maximum .< b.minimum), !any(b.maximum .< a.minimum) else { continue }
            if TestTriangleGeometry.crosses(a,b) { count += 1 }
        } }
        return count
    }
}

import Foundation
import RealityKit
import XCTest
@testable import Bina

@MainActor
final class BundledCharacterAttentionTests: XCTestCase {
    func testActualHeadTurnsInTheCorrectFrameWhileStanceAndPlacementStayFixed() async throws {
        for (yaw, scale): (Float, Float) in [(0, 1), (1.1, 0.45), (-2.4, 1.15)] {
            let fixture = try await Fixture()
            fixture.parent.position = [3, -0.4, 5]
            fixture.parent.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            fixture.parent.scale = SIMD3(repeating: scale)
            let placement = fixture.parent.transform.matrix
            let feet = try fixture.footPositions()
            fixture.advance(frames: 240, target: try fixture.target(offset: [1.5, 0.8, -2]))

            let forward = try fixture.attentionForward()
            XCTAssertGreaterThan(forward.x, 0.3)
            XCTAssertGreaterThan(forward.y, 0.1)
            XCTAssertLessThan(abs(atan2(forward.x, -forward.z)), CharacterHeadAttention.maximumYaw + 0.001)
            XCTAssertLessThan(asin(forward.y), CharacterHeadAttention.maximumUpwardPitch + 0.001)
            assertMatrix(fixture.parent.transform.matrix, equals: placement)
            for (before, after) in zip(feet, try fixture.footPositions()) {
                XCTAssertLessThan(simd_distance(before, after), 0.00001)
            }
            assertStanceMatchesIdle(fixture)
        }
    }

    func testPauseToggleAndReferencePreserveTheWholePose() async throws {
        let fixture = try await Fixture()
        let target = try fixture.target(offset: [1.2, 0.5, -2])
        fixture.advance(frames: 120, target: target)
        fixture.motion.pause()
        fixture.controlMotion.pause()
        let paused = fixture.model.jointTransforms
        let phase = fixture.motion.cycleTime
        fixture.motion.isAttentionEnabled = false
        fixture.advance(frames: 120, target: try fixture.target(offset: [-1.5, -0.5, -2]))
        assertPose(fixture.model.jointTransforms, equals: paused)
        XCTAssertEqual(fixture.motion.cycleTime, phase)

        fixture.motion.resume()
        fixture.controlMotion.resume()
        fixture.advance(frames: 360, target: target)
        XCTAssertLessThan(simd_distance(try fixture.attentionForward(), [0, 0, -1]), 0.0001)
        assertPose(fixture.model.jointTransforms, equals: fixture.controlModel.jointTransforms)

        fixture.motion.isAttentionEnabled = true
        fixture.motion.showReference()
        fixture.controlMotion.showReference()
        fixture.advance(frames: 60, target: target)
        assertPose(fixture.model.jointTransforms, equals: fixture.reference)
        fixture.motion.showNatural()
        fixture.controlMotion.showNatural()
        assertPose(fixture.model.jointTransforms, equals: fixture.reference)
        fixture.advance(frames: 1, target: target)
        XCTAssertLessThan(simd_distance(try fixture.attentionForward(), [0, 0, -1]), 0.001)
        fixture.advance(frames: 180, target: target)
        XCTAssertGreaterThan(try fixture.attentionForward().x, 0.3)
    }

    func testHiddenAndMissingTargetsDoNotReplayOldPositionsOrSnap() async throws {
        let fixture = try await Fixture()
        fixture.advance(frames: 120, target: try fixture.target(offset: [1.5, 0, -2]))
        let before = fixture.model.jointTransforms
        let forward = try fixture.attentionForward()
        let phase = fixture.motion.cycleTime
        fixture.advance(frames: 120, target: try fixture.target(offset: [-1.5, 0, -2]), visible: false)
        assertPose(fixture.model.jointTransforms, equals: before)
        XCTAssertEqual(fixture.motion.cycleTime, phase)

        fixture.advance(frames: 1, target: nil)
        let returning = try fixture.attentionForward()
        XCTAssertGreaterThan(returning.x, 0)
        XCTAssertLessThan(returning.x, forward.x)
        XCTAssertLessThan(simd_distance(returning, forward), 0.01)
        fixture.advance(frames: 360, target: nil)
        XCTAssertLessThan(simd_distance(try fixture.attentionForward(), [0, 0, -1]), 0.0001)

        fixture.advance(frames: 1, target: try fixture.target(offset: [-1.5, 0, -2]))
        XCTAssertLessThan(simd_distance(try fixture.attentionForward(), [0, 0, -1]), 0.01)
        fixture.advance(frames: 180, target: try fixture.target(offset: [-1.5, 0, -2]))
        XCTAssertLessThan(try fixture.attentionForward().x, -0.3)
    }

    func testRearCloseAndInvalidTargetsLeaveOnlyTheExistingIdle() async throws {
        let fixture = try await Fixture()
        for offset: SIMD3<Float> in [[0, 0, 2], [0.1, 0, -0.1], [0, 3, 0], [.nan, 0, -2]] {
            fixture.advance(frames: 90, target: try fixture.target(offset: offset))
            assertPose(fixture.model.jointTransforms, equals: fixture.controlModel.jointTransforms)
        }
    }

    func testRejectsAnInvalidHeadNeckHierarchy() async throws {
        let fixture = try await Fixture()
        XCTAssertThrowsError(try CharacterAttentionBinding(
            model: fixture.model, character: fixture.character, reference: fixture.reference,
            neck: fixture.head, head: fixture.neck
        ))
    }

    private func assertStanceMatchesIdle(_ fixture: Fixture) {
        for index in fixture.model.jointTransforms.indices {
            let actual = fixture.model.jointTransforms[index]
            let expected = fixture.controlModel.jointTransforms[index]
            if index == fixture.neck || index == fixture.head {
                XCTAssertLessThan(simd_distance(actual.translation, expected.translation), 0.000001)
                XCTAssertLessThan(simd_distance(actual.scale, expected.scale), 0.000001)
            } else { assertMatrix(actual.matrix, equals: expected.matrix) }
        }
    }

    private func assertPose(_ actual: [Transform], equals expected: [Transform]) {
        XCTAssertEqual(actual.count, expected.count)
        for (a, b) in zip(actual, expected) { assertMatrix(a.matrix, equals: b.matrix) }
    }

    private func assertMatrix(_ actual: simd_float4x4, equals expected: simd_float4x4) {
        for column in 0..<4 {
            for row in 0..<4 { XCTAssertEqual(actual[column][row], expected[column][row], accuracy: 0.000001) }
        }
    }
}

@MainActor
private final class Fixture {
    let parent = Entity()
    let character: Entity
    let control: Entity
    let model: ModelEntity
    let controlModel: ModelEntity
    let motion: CharacterIdleMotion
    let controlMotion: CharacterIdleMotion
    let reference: [Transform]
    let neck: Int
    let head: Int
    let feet: [Int]

    init() async throws {
        guard let modelURL = CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main) else {
            throw XCTSkip("The local-only character asset is not bundled in this checkout.")
        }
        let poseURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaIdlePose", extension: "json", in: .main))
        character = try await CharacterAsset.load()
        control = character.clone(recursive: true)
        func rig(_ entity: Entity) -> ModelEntity? {
            if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
            for child in entity.children { if let result = rig(child) { return result } }
            return nil
        }
        model = try XCTUnwrap(rig(character))
        controlModel = try XCTUnwrap(rig(control))
        reference = model.jointTransforms
        let pose = try await CharacterIdlePose.load(modelURL: modelURL, poseURL: poseURL)
        let jointNames = model.jointNames
        func index(_ name: String) throws -> Int {
            try XCTUnwrap(jointNames.firstIndex { $0.split(separator: "/").last == Substring(name) })
        }
        neck = try index(try XCTUnwrap(pose.motionJoints["neck"]))
        head = try index(try XCTUnwrap(pose.motionJoints["head"]))
        feet = try pose.fixedJoints.map(index)
        motion = try CharacterIdleMotion(character: character, pose: pose)
        controlMotion = try CharacterIdleMotion(character: control, pose: pose)
        controlMotion.isAttentionEnabled = false
        parent.addChild(character)
        parent.addChild(control)
    }

    func advance(frames: Int, target: SIMD3<Float>?, visible: Bool = true) {
        for _ in 0..<frames {
            motion.advance(by: 1.0 / 60, isVisible: visible, attentionTarget: target)
            controlMotion.advance(by: 1.0 / 60, isVisible: visible)
        }
    }

    func target(offset: SIMD3<Float>) throws -> SIMD3<Float> {
        let point = try jointMatrix(head, model: controlModel).columns.3
        return SIMD3(point.x, point.y, point.z) + character.orientation(relativeTo: nil).act(offset)
    }

    func attentionForward() throws -> SIMD3<Float> {
        let actual = Transform(matrix: simd_inverse(character.transformMatrix(relativeTo: nil)) * (try jointMatrix(head, model: model))).rotation
        let baseline = Transform(matrix: simd_inverse(control.transformMatrix(relativeTo: nil)) * (try jointMatrix(head, model: controlModel))).rotation
        return (actual * baseline.inverse).act([0, 0, -1])
    }

    func footPositions() throws -> [SIMD3<Float>] {
        try feet.map {
            let point = try jointMatrix($0, model: model).columns.3
            return SIMD3(point.x, point.y, point.z)
        }
    }

    private func jointMatrix(_ index: Int, model: ModelEntity) throws -> simd_float4x4 {
        let skeleton = try XCTUnwrap(model.model?.mesh.contents.skeletons.first)
        var current = index
        var matrix = model.jointTransforms[current].matrix
        while let parent = skeleton.joints[current].parentIndex {
            matrix = model.jointTransforms[parent].matrix * matrix
            current = parent
        }
        return model.transformMatrix(relativeTo: nil) * matrix
    }
}

import Foundation
import RealityKit
import XCTest
@testable import Bina

@MainActor
final class BundledCharacterIdleTests: XCTestCase {
    func testUniqueSkeletonDrivesTheNaturalPose() async throws {
        let (character, model, pose) = try await loadSource()
        let reference = model.jointTransforms
        let placement = character.transform

        _ = try CharacterIdleMotion(character: character, pose: pose)

        XCTAssertEqual(model.jointNames.count, 790)
        XCTAssertEqual(Set(model.jointNames).count, 790)
        XCTAssertEqual(model.model?.mesh.contents.skeletons.count, 1)
        XCTAssertEqual(pose.jointDeltas.count, 4)
        for name in pose.jointDeltas.keys {
            let index = try jointIndex(name, in: model)
            XCTAssertGreaterThan(simd_length(model.jointTransforms[index].rotation.vector - reference[index].rotation.vector), 0.01)
        }
        assertPose([character.transform], equals: [placement])
    }

    func testIdleKeepsFeetAndPlacementFixedAcrossTheLoop() async throws {
        let (character, model, pose) = try await loadSource()
        let feet = try pose.fixedJoints.map { try jointPosition($0, in: model) }
        let placement = character.transform
        let motion = try CharacterIdleMotion(character: character, pose: pose)
        let firstPose = model.jointTransforms

        for frame in 1...660 {
            motion.advance(by: 1.0 / 60, isVisible: true)
            if frame % 55 == 0 {
                for (name, reference) in zip(pose.fixedJoints, feet) {
                    XCTAssertLessThan(simd_length(try jointPosition(name, in: model) - reference), 0.00001)
                }
            }
        }

        assertPose(model.jointTransforms, equals: firstPose, accuracy: 0.00001)
        assertPose([character.transform], equals: [placement])
    }

    func testPauseVisibilityAndReferenceControlsPreserveTheExpectedPose() async throws {
        let (character, model, pose) = try await loadSource()
        let reference = model.jointTransforms
        let motion = try CharacterIdleMotion(character: character, pose: pose)
        for _ in 0..<120 { motion.advance(by: 1.0 / 60, isVisible: true) }
        let current = model.jointTransforms
        let time = motion.cycleTime

        motion.pause()
        motion.advance(by: 10, isVisible: true)
        XCTAssertEqual(motion.mode, .paused)
        XCTAssertEqual(motion.cycleTime, time)
        assertPose(model.jointTransforms, equals: current)
        motion.resume()
        motion.advance(by: 10, isVisible: false)
        XCTAssertEqual(motion.cycleTime, time)
        assertPose(model.jointTransforms, equals: current)

        motion.showReference()
        XCTAssertEqual(motion.mode, .reference)
        assertPose(model.jointTransforms, equals: reference)
        motion.resume()
        XCTAssertEqual(motion.mode, .reference)
        motion.showNatural()
        assertPose(model.jointTransforms, equals: reference)
        for _ in 0..<60 { motion.advance(by: 1.0 / 60, isVisible: true) }
        XCTAssertEqual(motion.mode, .playing)
        XCTAssertGreaterThan(simd_length(model.jointTransforms[try jointIndex("Joint_0177", in: model)].rotation.vector
            - reference[try jointIndex("Joint_0177", in: model)].rotation.vector), 0.01)
    }

    func testSceneLifecycleRejectsObsoleteFrameCallbacks() async throws {
        try requireLocalAsset()
        let prototype = SpatialPrototype(store: IdleTestPlacementStore())
        await prototype.loadCharacter()
        let motion = try XCTUnwrap(prototype.characterIdle, prototype.characterIdleMessage ?? "Idle preparation failed.")
        prototype.spaceDidAppear()
        prototype.contentEntity.isEnabled = true
        let firstToken = prototype.beginMotionUpdates()
        prototype.advanceCharacterMotion(by: 0.05, token: firstToken)
        let firstTime = motion.cycleTime
        XCTAssertGreaterThan(firstTime, 0)

        let currentToken = prototype.beginMotionUpdates()
        prototype.endMotionUpdates(token: firstToken)
        prototype.advanceCharacterMotion(by: 0.05, token: firstToken)
        XCTAssertEqual(motion.cycleTime, firstTime)
        prototype.advanceCharacterMotion(by: 0.05, token: currentToken)
        let currentTime = motion.cycleTime
        XCTAssertGreaterThan(currentTime, firstTime)

        prototype.setSceneActive(false)
        prototype.advanceCharacterMotion(by: 1, token: currentToken)
        XCTAssertEqual(motion.cycleTime, currentTime)
        prototype.spaceDidDisappear()
        prototype.spaceDidAppear()
        prototype.contentEntity.isEnabled = true
        prototype.advanceCharacterMotion(by: 1, token: currentToken)
        XCTAssertEqual(motion.cycleTime, currentTime)
        let reopenedToken = prototype.beginMotionUpdates()
        prototype.advanceCharacterMotion(by: 0.05, token: reopenedToken)
        XCTAssertEqual(motion.cycleTime, currentTime)
        prototype.setSceneActive(true)
        // The production view restores scene activity before valid tracking
        // enables content. This fixture supplies visibility without live ARKit.
        prototype.contentEntity.isEnabled = true
        prototype.advanceCharacterMotion(by: 0.05, token: reopenedToken)
        XCTAssertGreaterThan(motion.cycleTime, currentTime)
        prototype.endMotionUpdates(token: reopenedToken)
        prototype.spaceDidDisappear()
    }

    private func requireLocalAsset() throws {
        guard CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main) != nil else {
            throw XCTSkip("The local-only character asset is not bundled in this checkout.")
        }
    }

    private func loadSource() async throws -> (Entity, ModelEntity, CharacterIdlePose) {
        try requireLocalAsset()
        let modelURL = try XCTUnwrap(CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main))
        let poseURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaIdlePose", extension: "json", in: .main))
        let character = try await CharacterAsset.load()
        let model = try XCTUnwrap(skinnedModel(in: character))
        let pose = try await CharacterIdlePose.load(modelURL: modelURL, poseURL: poseURL)
        return (character, model, pose)
    }

    private func skinnedModel(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        return entity.children.lazy.compactMap { self.skinnedModel(in: $0) }.first
    }

    private func jointIndex(_ name: String, in model: ModelEntity) throws -> Int {
        try XCTUnwrap(model.jointNames.firstIndex { $0.split(separator: "/").last == Substring(name) })
    }

    private func jointPosition(_ name: String, in model: ModelEntity) throws -> SIMD3<Float> {
        let skeleton = try XCTUnwrap(model.model?.mesh.contents.skeletons.first)
        let transforms = model.jointTransforms
        var index = try jointIndex(name, in: model)
        var matrix = transforms[index].matrix
        var visited: Set<Int> = [index]
        while let parent = skeleton.joints[index].parentIndex {
            XCTAssertTrue(visited.insert(parent).inserted)
            matrix = transforms[parent].matrix * matrix
            index = parent
        }
        let position = (model.transformMatrix(relativeTo: nil) * matrix).columns.3
        return SIMD3(position.x, position.y, position.z)
    }

    private func assertPose(_ actual: [Transform], equals expected: [Transform], accuracy: Float = 0.000001) {
        XCTAssertEqual(actual.count, expected.count)
        for (left, right) in zip(actual, expected) {
            for column in 0..<4 {
                for row in 0..<4 {
                    XCTAssertEqual(left.matrix[column][row], right.matrix[column][row], accuracy: accuracy)
                }
            }
        }
    }
}

@MainActor
private final class IdleTestPlacementStore: PlacementPersisting {
    func load() throws -> SavedPlacement? { nil }
    func save(_ placement: SavedPlacement) throws {}
    func clear() throws {}
}

import Foundation
import RealityKit
import XCTest
@testable import Bina

@MainActor
final class BundledCharacterFaceTests: XCTestCase {
    func testDialogueExpressionsReuseBoundedShapesAndPreserveBothEyeFormsAndSkeleton() async throws {
        let f = try await FaceFixture()
        f.face.automaticBlink = false
        let joints = f.model.jointTransforms
        for eye: CharacterFacePlayback.EyeState in [.coveredClosed, .uncoveredOpen] {
            f.face.eyeState = eye
            var smiles: [DialogueAffect: Float] = [:]
            var brows: [DialogueAffect: Float] = [:]
            for affect in DialogueAffect.allCases {
                f.face.setConversationCue(.idle, mouth: 0, expression: .init(affect: affect))
                for _ in 0..<60 { try f.face.advance(by: 1.0 / 60, influence: 1) }
                smiles[affect] = f.value("smile")
                brows[affect] = f.value("browRaise")
                XCTAssertEqual(f.value("blink"), eye == .coveredClosed ? 1 : 0)
                XCTAssertEqual(try f.coverOpacity(), eye == .coveredClosed ? 1 : 0)
                XCTAssertLessThanOrEqual(f.value("smile"), 0.22)
                XCTAssertLessThanOrEqual(f.value("browRaise"), 0.18)
                XCTAssertEqual(f.value("mouthOpen"), 0)
                assertPose(f.model.jointTransforms, joints)
            }
            XCTAssertGreaterThan(smiles[.cheerful]!, smiles[.warm]!)
            XCTAssertGreaterThan(smiles[.warm]!, 0)
            XCTAssertEqual(smiles[.concerned]!, 0)
            XCTAssertGreaterThan(brows[.concerned]!, 0)
            XCTAssertLessThan(brows[.concerned]!, 0.06)
            XCTAssertGreaterThan(brows[.curious]!, brows[.concerned]!)
        }
    }

    func testDialogueExpressionRespectsPauseReferenceAndManualOverride() async throws {
        let f = try await FaceFixture()
        f.face.setConversationCue(.speaking, mouth: 0.25, expression: .init(affect: .cheerful))
        f.advance(60)
        XCTAssertGreaterThan(f.value("smile"), 0)
        f.motion.pause()
        let weights = f.weights()
        f.face.setConversationCue(.speaking, mouth: 0.25, expression: .init(affect: .concerned))
        f.advance(60)
        XCTAssertEqual(f.weights(), weights)
        f.motion.showReference()
        XCTAssertEqual(f.weights(), f.originalWeights)
        f.motion.showNatural()
        f.face.followsDialogue = false
        f.face.expression = .gentleSmile
        f.face.setConversationCue(.speaking, mouth: 0.2, expression: .init(affect: .concerned))
        f.advance(60)
        XCTAssertGreaterThan(f.value("smile"), 0)
        XCTAssertEqual(f.value("mouthOpen"), 0.2)
        XCTAssertEqual(f.value("blink"), 1)
        XCTAssertEqual(try f.coverOpacity(), 1)
        f.face.followsDialogue = true
        f.face.setConversationCue(.idle, mouth: 0)
        f.advance(60)
        XCTAssertEqual(f.value("smile"), 0)
        f.face.followsDialogue = false
        f.advance(60)
        XCTAssertGreaterThan(f.value("smile"), 0)
    }

    func testConversationCuesPreserveEyeFormsAndClearOnlyTheirOwnMouthOverlay() async throws {
        let f = try await FaceFixture()
        for state: CharacterFacePlayback.EyeState in [.coveredClosed, .uncoveredOpen] {
            f.face.eyeState = state
            f.face.automaticBlink = false
            f.advance(60)
            let blink = f.value("blink"), cover = try f.coverOpacity(), joints = f.model.jointTransforms
            f.face.setConversationCue(.listening, mouth: 0)
            try f.face.present(influence: 1)
            XCTAssertEqual(f.value("blink"), blink)
            XCTAssertEqual(try f.coverOpacity(), cover)
            XCTAssertGreaterThan(f.value("browRaise"), 0)
            f.face.setConversationCue(.speaking, mouth: 1)
            try f.face.present(influence: 1)
            XCTAssertEqual(f.value("mouthOpen"), 0.35, accuracy: 0.00001)
            XCTAssertEqual(f.value("blink"), blink)
            f.face.setConversationCue(.idle, mouth: 0)
            try f.face.present(influence: 1)
            XCTAssertEqual(f.value("mouthOpen"), 0)
            for (a, b) in zip(joints, f.model.jointTransforms) {
                XCTAssertEqual(a.matrix, b.matrix)
            }
        }
        f.face.setConversationCue(.speaking, mouth: 0.35)
        f.motion.showReference()
        XCTAssertEqual(f.weights(), f.originalWeights)
    }

    func testDeliveredFacialTargetsAreUniqueAndTheDefaultIsCoveredClosed() async throws {
        let f = try await FaceFixture()
        let names = f.weights().keys
        XCTAssertEqual(names.count, 60)
        XCTAssertEqual(Set(names).count, 60)
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("Face_") })
        for mesh in try XCTUnwrap(f.model.model).mesh.contents.models { for part in mesh.parts {
            XCTAssertEqual(Set(part.blendShapeNames), Set(names))
        } }
        XCTAssertEqual(f.face.eyeState, .coveredClosed)
        XCTAssertEqual(f.value("blink"), 1)
        XCTAssertEqual(try f.coverOpacity(), 1)
        XCTAssertEqual(f.model.jointNames.count, 790)
    }

    func testUncoveredBlinkAndCoveredReturnPreserveEyeMaterials() async throws {
        let f = try await FaceFixture()
        f.face.eyeState = .uncoveredOpen
        f.face.automaticBlink = false
        f.advance(60)
        XCTAssertEqual(f.value("blink"), 0)
        XCTAssertEqual(try f.coverOpacity(), 0)
        f.face.previewBlink()
        f.advance(5)
        XCTAssertEqual(f.value("blink"), 1)
        XCTAssertEqual(try f.coverOpacity(), 0)
        f.advance(30)
        XCTAssertEqual(f.value("blink"), 0)
        f.face.eyeState = .coveredClosed
        f.advance(60)
        XCTAssertEqual(f.value("blink"), 1)
        XCTAssertEqual(try f.coverOpacity(), 1)
        for name in ["CharacterMaterial_09", "CharacterMaterial_10", "CharacterMaterial_11"] {
            let material = try XCTUnwrap(f.model.model?.materials.first { $0.name == name } as? PhysicallyBasedMaterial)
            guard case .opaque = material.blending else { XCTFail("Eye opacity changed: \(name)"); continue }
        }
        let cover = try XCTUnwrap(f.model.model?.materials.first { $0.name == "CharacterMaterial_12" } as? PhysicallyBasedMaterial)
        guard case .transparent(let opacity) = cover.blending else { return XCTFail("Eye cover lost texture transparency.") }
        XCTAssertNotNil(opacity.texture)
    }

    func testPauseHiddenReferenceAndReturnRespectTheWholeFacialState() async throws {
        let f = try await FaceFixture()
        f.face.eyeState = .uncoveredOpen
        f.face.automaticBlink = false
        f.face.followsDialogue = false
        f.face.expression = .gentleSmile
        f.face.mouthPose = .round
        f.advance(120)
        f.motion.pause()
        let weights = f.weights(), sample = f.face.sample
        f.face.eyeState = .coveredClosed
        f.face.mouthPose = .relaxed
        f.advance(60)
        f.motion.advance(by: 20, isVisible: false)
        XCTAssertEqual(f.weights(), weights)
        XCTAssertEqual(f.face.sample, sample)
        XCTAssertEqual(try f.coverOpacity(), 0)
        f.motion.showReference()
        XCTAssertEqual(f.weights(), f.originalWeights)
        XCTAssertEqual(try f.coverOpacity(), 1)
        assertPose(f.model.jointTransforms, f.reference)
        f.advance(60)
        XCTAssertEqual(f.weights(), f.originalWeights)
        f.motion.showNatural()
        XCTAssertEqual(f.value("blink"), 1)
        XCTAssertEqual(try f.coverOpacity(), 1)
        f.face.eyeState = .uncoveredOpen
        f.advance(120)
        XCTAssertEqual(f.value("blink"), 0)
        XCTAssertEqual(try f.coverOpacity(), 0)
        XCTAssertEqual(f.value("mouthRound"), 0)
    }

    func testFaceDoesNotChangeSkeletonPlacementOrOtherMaterialOwners() async throws {
        let f = try await FaceFixture()
        let control = f.character.clone(recursive: true)
        let model = try XCTUnwrap(FaceFixture.rig(control))
        model.jointTransforms = f.reference
        let baseline = try CharacterIdleMotion(character: control, pose: f.pose)
        try baseline.configureHairPhysics(f.physics, pose: f.pose)
        let placement = f.character.transform.matrix
        f.face.eyeState = .uncoveredOpen
        f.face.followsDialogue = false
        f.face.expression = .gentleSmile
        f.face.mouthPose = .open
        var maximumPoseError: Float = 0
        for _ in 0..<120 {
            let target = SIMD3<Float>(1.5,1.6,-2)
            f.motion.advance(by: 1.0/60, isVisible: true, attentionTarget: target)
            baseline.advance(by: 1.0/60, isVisible: true, attentionTarget: target)
            maximumPoseError = max(maximumPoseError, zip(f.model.jointTransforms, model.jointTransforms).map {
                matrixError($0.matrix, $1.matrix)
            }.max() ?? 0)
        }
        XCTAssertLessThan(maximumPoseError, 0.000001)
        assertPose(f.model.jointTransforms, model.jointTransforms)
        XCTAssertLessThan(matrixError(f.character.transform.matrix, placement), 0.000001)
        let originals = try XCTUnwrap(f.originalMaterials as? [PhysicallyBasedMaterial])
        let current = try XCTUnwrap(f.model.model?.materials as? [PhysicallyBasedMaterial])
        for (before, after) in zip(originals, current) where before.name != "CharacterMaterial_12" {
            XCTAssertEqual(before.name, after.name)
            XCTAssertEqual(before.blending, after.blending)
            XCTAssertEqual(before.faceCulling, after.faceCulling)
            XCTAssertEqual(before.opacityThreshold, after.opacityThreshold)
        }
        f.motion.showsPhysicsDebug = true
        f.advance(1)
        XCTAssertEqual(f.model.components[OpacityComponent.self]?.opacity, 0.3)
        f.motion.showReference()
        XCTAssertNil(f.model.components[OpacityComponent.self])
        XCTAssertEqual(f.weights(), f.originalWeights)
    }

    func testInvalidReplacementAndFailurePreservePrimaryMotion() async throws {
        let f = try await FaceFixture()
        f.face.eyeState = .uncoveredOpen
        f.advance(60)
        let weights = f.weights()
        let mismatch = CharacterFaceProfile(schemaVersion: 1, modelSHA256: String(repeating: "a", count: 64),
            channels: f.profile.channels, coveringMaterial: f.profile.coveringMaterial)
        XCTAssertThrowsError(try f.motion.configureFace(mismatch))
        var channels = f.profile.channels; channels["blink"] = "Face_9999"
        let missing = CharacterFaceProfile(schemaVersion: 1, modelSHA256: f.profile.modelSHA256,
            channels: channels, coveringMaterial: f.profile.coveringMaterial)
        XCTAssertThrowsError(try f.motion.configureFace(missing))
        XCTAssertTrue(f.motion.face === f.face)
        XCTAssertEqual(f.weights(), weights)
        f.motion.reportFaceUnavailable(CharacterFaceError.invalidBinding("Test failure"))
        XCTAssertNil(f.motion.face)
        XCTAssertNotNil(f.motion.faceMessage)
        XCTAssertEqual(f.weights(), f.originalWeights)
        let phase = f.motion.cycleTime
        f.advance(60)
        XCTAssertGreaterThan(f.motion.cycleTime, phase)
        XCTAssertTrue(f.motion.isHairPhysicsAvailable)
    }

    func testMalformedSamplesCannotMutateTheImportedState() async throws {
        let f = try await FaceFixture()
        let binding = try CharacterFaceBinding(model: f.model, profile: f.profile,
            referenceWeights: f.originalComponent, referenceMaterials: f.originalMaterials)
        let before = f.weights()
        var values = CharacterFacePlayback().sample.channels
        values["blink"] = .nan
        XCTAssertThrowsError(try binding.apply(.init(coveringOpacity: 0, channels: values), influence: 1))
        XCTAssertThrowsError(try binding.apply(.init(coveringOpacity: 0, channels: [:]), influence: 1))
        XCTAssertThrowsError(try binding.apply(CharacterFacePlayback().sample, influence: -1))
        XCTAssertEqual(f.weights(), before)
        XCTAssertEqual(try f.coverOpacity(), 1)
    }

    func testValidReplacementRestoresTheOriginalReferenceRatherThanTheLastPreview() async throws {
        let f = try await FaceFixture()
        f.face.eyeState = .uncoveredOpen
        f.face.followsDialogue = false
        f.face.expression = .gentleSmile
        f.advance(60)
        XCTAssertGreaterThan(f.value("smile"), 0)
        try f.motion.configureFace(f.profile)
        XCTAssertEqual(f.value("blink"), 1)
        f.motion.showReference()
        XCTAssertEqual(f.weights(), f.originalWeights)
        XCTAssertEqual(try f.coverOpacity(), 1)
    }

    private func assertPose(_ actual: [Transform], _ expected: [Transform]) {
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertLessThan(zip(actual, expected).map { matrixError($0.matrix,$1.matrix) }.max() ?? 0, 0.000001)
    }

    private func matrixError(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        (0..<4).flatMap { c in (0..<4).map { r in abs(a[c][r]-b[c][r]) } }.max() ?? 0
    }
}

@MainActor
private final class FaceFixture {
    let character: Entity
    let model: ModelEntity
    let reference: [Transform]
    let originalComponent: BlendShapeWeightsComponent?
    let originalMaterials: [any Material]
    let originalWeights: [String: Float]
    let pose: CharacterIdlePose
    let physics: CharacterPhysicsProfile
    let profile: CharacterFaceProfile
    let motion: CharacterIdleMotion
    let face: CharacterFaceMotion

    init() async throws {
        guard let input = CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main) else {
            throw XCTSkip("The local-only character asset is not bundled in this checkout.")
        }
        character = try await CharacterAsset.load()
        model = try XCTUnwrap(Self.rig(character))
        reference = model.jointTransforms
        originalComponent = model.components[BlendShapeWeightsComponent.self]
        originalMaterials = try XCTUnwrap(model.model).materials
        originalWeights = Self.weights(model)
        let poseURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaIdlePose", extension: "json", in: .main))
        let physicsURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaPhysics", extension: "json", in: .main))
        let faceURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaFace", extension: "json", in: .main))
        pose = try await CharacterIdlePose.load(modelURL: input, poseURL: poseURL)
        physics = try await CharacterPhysicsProfile.load(modelURL: input, profileURL: physicsURL)
        profile = try await CharacterFaceProfile.load(modelURL: input, profileURL: faceURL)
        motion = try await CharacterAsset.loadIdleMotion(for: character)
        face = try XCTUnwrap(motion.face, motion.faceMessage ?? "Face preparation failed.")
    }

    func advance(_ frames: Int) {
        for _ in 0..<frames { motion.advance(by: 1.0/60, isVisible: true) }
    }

    func weights() -> [String: Float] { Self.weights(model) }
    func value(_ semantic: String) -> Float { weights()[profile.channels[semantic]!]! }

    func coverOpacity() throws -> Float {
        let cover = try XCTUnwrap(model.model?.materials.first { $0.name == profile.coveringMaterial } as? PhysicallyBasedMaterial)
        guard case .transparent(let opacity) = cover.blending else { throw CharacterFaceError.invalidBinding("Missing cover transparency.") }
        return opacity.scale
    }

    static func weights(_ model: ModelEntity) -> [String: Float] {
        var result: [String: Float] = [:]
        if let component = model.components[BlendShapeWeightsComponent.self] {
            for data in component.weightSet {
                for (name, value) in zip(data.weightNames, data.weights) { result[name] = value }
            }
        }
        return result
    }

    static func rig(_ entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        return entity.children.compactMap(rig).first
    }
}

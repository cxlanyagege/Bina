import Foundation
import RealityKit
import XCTest
import simd

@testable import Bina

@MainActor
final class BundledFootwearTests: XCTestCase {
    func testBarefootRemovesHeelGeometryAndRetainsOtherPartsAndFacialMappings() async throws {
        let (character, motion) = try await loaded()
        let geometry = try FootGeometry(character)
        let original = try XCTUnwrap(geometry.model.model)
        motion.face?.eyeState = .uncoveredOpen
        motion.face?.automaticBlink = false
        for _ in 0..<120 { motion.advance(by: 1.0 / 120, isVisible: true) }
        let before = try XCTUnwrap(geometry.model.model)
        let faceWeights = try XCTUnwrap(geometry.model.components[BlendShapeWeightsComponent.self])
        motion.setFootwearMode(.barefoot)
        let bare = try XCTUnwrap(geometry.model.model)
        XCTAssertFalse(bare.mesh === original.mesh)
        let retained = parts(bare)
        let expected = parts(original).filter { original.materials[$0.materialIndex].name != "CharacterMaterial_19" }
        XCTAssertEqual(Set(retained.map(\.id)), Set(expected.map(\.id)))
        let expectedByID = Dictionary(uniqueKeysWithValues: expected.map { ($0.id, $0) })
        for actual in retained {
            let baseline = try XCTUnwrap(expectedByID[actual.id])
            XCTAssertTrue(actual.positions.elements == baseline.positions.elements, "Positions changed: \(actual.id)")
            XCTAssertTrue(
                actual.triangleIndices?.elements == baseline.triangleIndices?.elements,
                "Triangles changed: \(actual.id)")
            XCTAssertTrue(actual.normals?.elements == baseline.normals?.elements, "Normals changed: \(actual.id)")
            XCTAssertEqual(Set(actual.blendShapeNames), Set(baseline.blendShapeNames))
            for name in actual.blendShapeNames {
                XCTAssertTrue(
                    actual.blendShapeOffsets(named: name)?.elements
                        == baseline.blendShapeOffsets(named: name)?.elements,
                    "Facial target changed: \(name)")
            }
            XCTAssertEqual(actual.materialIndex, baseline.materialIndex)
        }
        XCTAssertFalse(retained.contains { bare.materials[$0.materialIndex].name == "CharacterMaterial_19" })
        XCTAssertEqual(bare.materials.map(\.name), before.materials.map(\.name))
        for (actual, baseline) in zip(bare.materials, before.materials) {
            let actual = try XCTUnwrap(actual as? PhysicallyBasedMaterial)
            let baseline = try XCTUnwrap(baseline as? PhysicallyBasedMaterial)
            XCTAssertEqual(actual.faceCulling, baseline.faceCulling)
            XCTAssertEqual(actual.baseColor.tint.cgColor, baseline.baseColor.tint.cgColor)
            XCTAssertEqual(String(describing: actual.blending), String(describing: baseline.blending))
        }
        let mapping = BlendShapeWeightsComponent(weightsMapping: BlendShapeWeightsMapping(meshResource: bare.mesh))
        let originalMapping = BlendShapeWeightsComponent(
            weightsMapping: BlendShapeWeightsMapping(meshResource: original.mesh))
        // Imported default weight sets may use an empty ID; compare mesh mappings with
        // each other separately from the currently presented facial component.
        XCTAssertEqual(mapping.weightSet.map(\.id), originalMapping.weightSet.map(\.id))
        XCTAssertEqual(
            mapping.weightSet.map { Set($0.weightNames) }, originalMapping.weightSet.map { Set($0.weightNames) })
        let afterWeights = try XCTUnwrap(geometry.model.components[BlendShapeWeightsComponent.self])
        XCTAssertEqual(namedWeights(afterWeights), namedWeights(faceWeights))
        motion.setFootwearMode(.waterHeels)
        XCTAssertTrue(geometry.model.model?.mesh === original.mesh)
    }

    func testBarefootSupportsBothHeelAndForefootAndOnlyChangesFourFixedRotations() async throws {
        let (character, motion) = try await loaded()
        let model = try FootGeometry(character).model
        let before = model.jointTransforms
        let phase = motion.cycleTime
        motion.setFootwearMode(.barefoot)
        let after = model.jointTransforms
        let calibrated: Set<Int> = [17, 18, 33, 34]
        for index in before.indices {
            let change = difference(before[index].matrix, after[index].matrix)
            if calibrated.contains(index) {
                XCTAssertGreaterThan(change, 0.1)
            } else {
                XCTAssertLessThan(change, 0.00001)
            }
        }
        XCTAssertEqual(motion.cycleTime, phase)
        let contact = try XCTUnwrap(motion.footwearGroundContact)
        let feet = try FootGeometry(character).worldPoints().filter { $0.y < 0.13 }
        for side: Float in [-1, 1] {
            let heel = try XCTUnwrap(feet.filter { $0.x * side > 0 && $0.z > -0.16 && $0.z < -0.10 }.map(\.y).min())
            let forefoot = try XCTUnwrap(feet.filter { $0.x * side > 0 && $0.z < -0.23 }.map(\.y).min())
            XCTAssertEqual(heel, contact.center.y, accuracy: 0.002)
            XCTAssertEqual(forefoot, contact.center.y, accuracy: 0.002)
        }
        for _ in 0..<120 { motion.advance(by: 1.0 / 90, isVisible: true, attentionTarget: [0.4, 1.4, -1]) }
        for index in calibrated {
            XCTAssertLessThan(difference(model.jointTransforms[index].matrix, after[index].matrix), 0.00001)
        }
    }

    func testPauseReferenceAndHiddenPlaybackKeepClearFootwearSemantics() async throws {
        let (character, motion) = try await loaded()
        let model = try FootGeometry(character).model
        let original = model.model?.mesh
        motion.setFootwearMode(.barefoot)
        let barePose = model.jointTransforms
        let bareMesh = model.model?.mesh
        motion.pause()
        motion.setFootwearMode(.waterHeels)
        motion.advance(by: 1, isVisible: true)
        XCTAssertEqual(motion.footwearMode, .barefoot)
        XCTAssertTrue(model.model?.mesh === bareMesh)
        for (a, b) in zip(model.jointTransforms, barePose) { XCTAssertEqual(difference(a.matrix, b.matrix), 0) }
        motion.showReference()
        XCTAssertTrue(model.model?.mesh === original)
        XCTAssertEqual(motion.footwearMode, .barefoot)
        XCTAssertEqual(motion.footwearGroundContact, motion.footwear?.contact(for: .waterHeels))
        motion.showNatural()
        XCTAssertTrue(model.model?.mesh === bareMesh)
        XCTAssertEqual(motion.footwearGroundContact, motion.footwear?.contact(for: .barefoot))
        motion.advance(by: 0.5, isVisible: false)
        XCTAssertTrue(model.model?.mesh === bareMesh)
    }

    func testPrototypeSwitchCancelsPreviewAndPreservesAnchorAssociationAndGroundContact() async throws {
        try requireAsset()
        let saved = SavedPlacement(anchorID: UUID(), alignment: .soleContact)
        let store = FootwearStore(saved)
        let prototype = SpatialPrototype(store: store)
        await prototype.loadCharacter()
        let motion = try XCTUnwrap(prototype.characterIdle)
        _ = try XCTUnwrap(motion.footwear, motion.footwearMessage ?? "")
        let token = UUID()
        let floor = FloorTestGeometry.rectangle()
        prototype.floorPlacement.beginRun(token)
        prototype.floorPlacement.setAvailability(.running, token: token)
        prototype.floorPlacement.setTrackingAvailable(true, token: token)
        prototype.floorPlacement.receive(floor, token: token, now: 1)
        prototype.floorPlacement.reconcile([floor], token: token, now: 2)
        XCTAssertTrue(
            prototype.floorPlacement.prepare(
                device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
        prototype.setFootwearMode(.barefoot)
        XCTAssertNil(prototype.floorPlacement.preview)
        XCTAssertEqual(prototype.savedPlacement, saved)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(
            try XCTUnwrap(FootGeometry(prototype.contentEntity).worldPoints().map(\.y).min()), 0, accuracy: 0.0001)
        prototype.toggleReferencePose()
        XCTAssertEqual(
            try XCTUnwrap(FootGeometry(prototype.contentEntity).worldPoints().map(\.y).min()), 0, accuracy: 0.0001)
        prototype.toggleReferencePose()
        XCTAssertEqual(motion.footwearMode, .barefoot)
        XCTAssertEqual(
            try XCTUnwrap(FootGeometry(prototype.contentEntity).worldPoints().map(\.y).min()), 0, accuracy: 0.0001)
        prototype.spaceDidDisappear()
        XCTAssertEqual(motion.footwearMode, .barefoot)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testPreparationRestoresTheImportedPoseAndRejectsInvalidSamplesWithoutChangingPresentation() async throws {
        try requireAsset()
        let character = try await CharacterAsset.load()
        let model = try FootGeometry(character).model
        let reference = model.jointTransforms
        let mesh = model.model?.mesh
        let binding = try CharacterFootwear(character: character, model: model, reference: reference)
        for (a, b) in zip(model.jointTransforms, reference) { XCTAssertEqual(difference(a.matrix, b.matrix), 0) }
        var invalid = Array(reference.dropLast())
        XCTAssertThrowsError(try binding.apply(.barefoot, to: &invalid))
        XCTAssertTrue(model.model?.mesh === mesh)
        let parent = Entity()
        parent.addChild(character)
        XCTAssertThrowsError(try CharacterFootwear(character: character, model: model, reference: reference))
    }

    func testFootwearFailureRestoresWaterHeelsAndRetainsPrimaryHairAndFacialPlayback() async throws {
        let (character, motion) = try await loaded()
        let model = try FootGeometry(character).model
        let mesh = model.model?.mesh
        motion.setFootwearMode(.barefoot)
        motion.reportFootwearUnavailable(CharacterFootwearError.invalidBinding("Synthetic failure."))
        XCTAssertFalse(motion.canChangeFootwear)
        XCTAssertNotNil(motion.footwearMessage)
        XCTAssertEqual(motion.footwearMode, .waterHeels)
        XCTAssertTrue(model.model?.mesh === mesh)
        let phase = motion.cycleTime
        motion.advance(by: 1.0 / 60, isVisible: true)
        XCTAssertGreaterThan(motion.cycleTime, phase)
        XCTAssertNotNil(motion.face)
        XCTAssertTrue(motion.isHairPhysicsAvailable)
    }

    private func loaded() async throws -> (Entity, CharacterIdleMotion) {
        try requireAsset()
        let character = try await CharacterAsset.load()
        let motion = try await CharacterAsset.loadIdleMotion(for: character)
        _ = try XCTUnwrap(motion.footwear, motion.footwearMessage ?? "")
        return (character, motion)
    }

    private func requireAsset() throws {
        guard CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main) != nil else {
            throw XCTSkip("The local-only character asset is not bundled in this checkout.")
        }
    }

    private func parts(_ model: ModelComponent) -> [MeshResource.Part] {
        model.mesh.contents.models.flatMap { Array($0.parts) }
    }
    private func namedWeights(_ component: BlendShapeWeightsComponent) -> [String: [String: Float]] {
        Dictionary(
            uniqueKeysWithValues: component.weightSet.map {
                ($0.id, Dictionary(uniqueKeysWithValues: zip($0.weightNames, $0.weights)))
            })
    }
    private func difference(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        (0..<4).flatMap { column in (0..<4).map { abs(a[column][$0] - b[column][$0]) } }.max() ?? 0
    }
}

@MainActor
private final class FootwearStore: PlacementPersisting {
    let placement: SavedPlacement
    private(set) var saveCount = 0
    init(_ placement: SavedPlacement) { self.placement = placement }
    func load() throws -> SavedPlacement? { placement }
    func save(_ placement: SavedPlacement) throws { saveCount += 1 }
    func clear() throws {}
}

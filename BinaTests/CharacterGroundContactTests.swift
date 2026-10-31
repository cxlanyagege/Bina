import Foundation
import RealityKit
import XCTest
import simd

@testable import Bina

@MainActor
final class CharacterGroundContactTests: XCTestCase {
    func testActualFeetTouchTheGroundAndFitTheFootprintAcrossScaleAndHeadingChanges() async throws {
        let character = try await loadCharacter()
        let motion = try await CharacterAsset.loadIdleMotion(for: character)
        let presentation = Entity()
        let floor = Entity()
        presentation.addChild(character)
        floor.addChild(presentation)
        floor.position = [2, 0.3, -1]
        for mode in CharacterFootwearMode.allCases {
            motion.setFootwearMode(mode)
            let contact = try XCTUnwrap(motion.footwearGroundContact)
            let geometry = try FootGeometry(character)
            for height: Float in [0.4, 1.6, 1.9] {
                for heading: Float in [0, .pi / 2, -.pi] {
                    let scale = height / 1.6
                    presentation.scale = SIMD3(repeating: scale)
                    presentation.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
                    presentation.position = contact.correction(scale: scale, heading: heading)
                    let points = geometry.worldPoints()
                    let lowest = try XCTUnwrap(points.map(\.y).min())
                    XCTAssertEqual(lowest, 0.3, accuracy: 0.0001)
                    XCTAssertTrue(points.allSatisfy { $0.y >= 0.3 - 0.0001 })
                    let feet = points.filter { $0.y <= 0.3 + 0.08 * scale }
                    XCTAssertFalse(feet.isEmpty)
                    for point in feet {
                        XCTAssertLessThanOrEqual(
                            simd_length(SIMD2(point.x - 2, point.z + 1)), contact.radius * scale + 0.0001)
                    }
                    let center = presentation.transform.matrix * SIMD4(contact.center, 1)
                    XCTAssertLessThan(simd_length(SIMD3(center.x, center.y, center.z)), 0.00001)
                }
            }
        }
        XCTAssertThrowsError(try CharacterGroundContact.measure(in: character))
    }

    func testPersistedSoleAlignmentUsesTheFootPivotWhileLegacyPlacementKeepsItsOrigin() async throws {
        try requireAsset()
        for alignment: SavedPlacement.Alignment? in [nil, .soleContact] {
            let store = GroundTestStore(SavedPlacement(anchorID: UUID(), alignment: alignment))
            let prototype = SpatialPrototype(store: store)
            await prototype.loadCharacter()
            let presentation = try XCTUnwrap(prototype.contentEntity.children.first)
            if alignment == nil {
                XCTAssertEqual(presentation.position, .zero)
                prototype.headingDegrees = 90
                prototype.characterHeight = 0.8
                XCTAssertEqual(presentation.position, .zero)
                prototype.setFootwearMode(.barefoot)
                XCTAssertEqual(try XCTUnwrap(FootGeometry(presentation).worldPoints().map(\.y).min()), 0, accuracy: 0.0001)
                prototype.setFootwearMode(.waterHeels)
                XCTAssertEqual(presentation.position, .zero)
            } else {
                for mode in CharacterFootwearMode.allCases {
                    prototype.setFootwearMode(mode)
                    let geometry = try FootGeometry(presentation)
                    for height: Double in [0.4, 1.6, 1.9] {
                        prototype.characterHeight = height
                        prototype.headingDegrees = 90
                        XCTAssertEqual(try XCTUnwrap(geometry.worldPoints().map(\.y).min()), 0, accuracy: 0.0001)
                    }
                }
            }
            XCTAssertEqual(store.saveCount, 0)
        }
    }

    func testMissingShoeGeometryDoesNotProduceAnInventedContactPoint() {
        XCTAssertThrowsError(try CharacterGroundContact.measure(in: Entity()))
    }

    private func requireAsset() throws {
        guard CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main) != nil else {
            throw XCTSkip("The local-only character asset is not bundled in this checkout.")
        }
    }

    private func loadCharacter() async throws -> Entity {
        try requireAsset()
        return try await CharacterAsset.load()
    }
}

/// Independent CPU skinning checks exposed feet and shoes, including toes beyond the shoe ornaments.
@MainActor
struct FootGeometry {
    struct Part {
        let positions: [SIMD3<Float>]
        let weights: [MeshJointInfluence]
        let stride: Int
    }
    let model: ModelEntity
    let skeleton: MeshResource.Skeleton
    let parts: [Part]

    init(_ character: Entity) throws {
        func rig(_ entity: Entity) -> ModelEntity? {
            if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
            return entity.children.compactMap(rig).first
        }
        model = try XCTUnwrap(rig(character))
        let component = try XCTUnwrap(model.model)
        skeleton = try XCTUnwrap(component.mesh.contents.skeletons.first)
        var parts: [Part] = []
        for mesh in component.mesh.contents.models {
            for part in mesh.parts {
                if ["CharacterMaterial_19", "CharacterMaterial_00", "CharacterMaterial_14"].contains(
                    component.materials[part.materialIndex].name)
                {
                    let positions = part.positions.elements
                    let weights = try XCTUnwrap(part.jointInfluences?.influences.elements)
                    parts.append(Part(positions: positions, weights: weights, stride: weights.count / positions.count))
                }
            }
        }
        XCTAssertFalse(parts.isEmpty)
        self.parts = parts
    }

    func worldPoints() -> [SIMD3<Float>] {
        let transforms = model.jointTransforms
        var globals: [simd_float4x4] = []
        for (i, joint) in skeleton.joints.enumerated() {
            globals.append(joint.parentIndex.map { globals[$0] * transforms[i].matrix } ?? transforms[i].matrix)
        }
        let matrices = zip(globals, skeleton.joints).map { $0 * $1.inverseBindPoseMatrix }
        let world = model.transformMatrix(relativeTo: nil)
        return parts.flatMap { part in
            part.positions.enumerated().map { i, p in
                var point = SIMD4<Float>(repeating: 0)
                for j in 0..<part.stride {
                    let influence = part.weights[i * part.stride + j]
                    point += (matrices[influence.jointIndex] * SIMD4(p, 1)) * influence.weight
                }
                let result = world * point
                return SIMD3(result.x, result.y, result.z)
            }
        }
    }
}

@MainActor
private final class GroundTestStore: PlacementPersisting {
    let placement: SavedPlacement
    var saveCount = 0
    init(_ placement: SavedPlacement) { self.placement = placement }
    func load() throws -> SavedPlacement? { placement }
    func save(_ placement: SavedPlacement) throws { saveCount += 1 }
    func clear() throws {}
}

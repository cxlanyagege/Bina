import Foundation
import RealityKit
import XCTest
@testable import Bina

@MainActor
final class BundledCharacterAssetTests: XCTestCase {
    func testBundledCharacterLoadsAndHasNormalizedGeometry() async throws {
        let character = try await loadLocalCharacter()
        let bounds = character.visualBounds(recursive: true, relativeTo: nil)
        XCTAssertFalse(bounds.isEmpty)
        XCTAssertEqual(bounds.extents.y, CharacterAsset.referenceHeight, accuracy: 0.001)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.center.x, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.center.z, 0, accuracy: 0.001)
        XCTAssertGreaterThan(modelCount(in: character), 0)
    }

    func testEyeAndFaceMaterialsRemainOpaqueAfterImport() async throws {
        let character = try await loadLocalCharacter()
        // These source surfaces use RGB atlases. Transparency sorting can expose
        // internal eye geometry if the exporter adds an unnecessary alpha graph.
        let expectedNames = Set([9, 10, 11, 13, 20, 21].map {
            String(format: "CharacterMaterial_%02d", $0)
        })
        let eyeMaterials = materials(in: character).filter {
            expectedNames.contains($0.name ?? "")
        }
        XCTAssertEqual(Set(eyeMaterials.compactMap(\.name)), expectedNames)
        for material in eyeMaterials {
            let surface = try XCTUnwrap(material as? PhysicallyBasedMaterial)
            guard case .opaque = surface.blending else {
                XCTFail("\(material.name ?? "Eye material") must import as opaque.")
                continue
            }
        }
    }

    func testTranslucentDetailsPreserveSourceOpacityAfterImport() async throws {
        let character = try await loadLocalCharacter()
        let importedMaterials = materials(in: character)
        for name in ["CharacterMaterial_12", "CharacterMaterial_23"] {
            let material = try XCTUnwrap(importedMaterials.first { $0.name == name })
            let surface = try XCTUnwrap(material as? PhysicallyBasedMaterial)
            XCTAssertNil(surface.opacityThreshold)
            guard case .transparent(let opacity) = surface.blending else {
                XCTFail("\(name) must retain continuous texture transparency.")
                continue
            }
            XCTAssertNotNil(opacity.texture)
        }
        let shoes = try XCTUnwrap(importedMaterials.first { $0.name == "CharacterMaterial_19" })
        let surface = try XCTUnwrap(shoes as? PhysicallyBasedMaterial)
        guard case .transparent(let opacity) = surface.blending else {
            return XCTFail("The source shoe opacity must remain translucent.")
        }
        XCTAssertNil(opacity.texture)
        // RealityKit imports scalar USD opacity into the base-color tint alpha.
        let effectiveOpacity = opacity.scale * Float(surface.baseColor.tint.cgColor.alpha)
        XCTAssertEqual(effectiveOpacity, 0.75, accuracy: 0.001)
    }

    func testCharacterSurfacesRetainSourceSidedness() async throws {
        let character = try await loadLocalCharacter()
        let importedMaterials = materials(in: character)
        XCTAssertFalse(importedMaterials.isEmpty)
        for material in importedMaterials {
            let surface = try XCTUnwrap(material as? PhysicallyBasedMaterial)
            let expected: PhysicallyBasedMaterial.FaceCulling = surface.name == "CharacterMaterial_19"
                ? .back : .none
            XCTAssertEqual(surface.faceCulling, expected, "\(material.name ?? "Character surface")")
        }
    }

    private func loadLocalCharacter() async throws -> Entity {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "Columbina", withExtension: "usdz", subdirectory: "Characters")
            ?? bundle.url(forResource: "Columbina", withExtension: "usdz", subdirectory: "Resources/Characters")
            ?? bundle.url(forResource: "Columbina", withExtension: "usdz")
        guard url != nil else {
            // The character asset is local-only and is not required in a clean checkout.
            throw XCTSkip("The local Columbina.usdz asset is not bundled in this build.")
        }

        return try await CharacterAsset.load(in: bundle)
    }

    private func materials(in entity: Entity) -> [any Material] {
        let ownMaterials = entity.components[ModelComponent.self]?.materials ?? []
        return ownMaterials + entity.children.flatMap { materials(in: $0) }
    }

    private func modelCount(in entity: Entity) -> Int {
        let ownCount = entity.components[ModelComponent.self] == nil ? 0 : 1
        return entity.children.reduce(ownCount) { $0 + modelCount(in: $1) }
    }
}

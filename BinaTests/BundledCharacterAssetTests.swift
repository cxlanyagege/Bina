import Foundation
import RealityKit
import XCTest
@testable import Bina

@MainActor
final class BundledCharacterAssetTests: XCTestCase {
    func testBundledCharacterLoadsAndHasNormalizedGeometry() async throws {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "Columbina", withExtension: "usdz", subdirectory: "Characters")
            ?? bundle.url(forResource: "Columbina", withExtension: "usdz", subdirectory: "Resources/Characters")
            ?? bundle.url(forResource: "Columbina", withExtension: "usdz")
        guard url != nil else {
            // The character asset is local-only and is not required in a clean checkout.
            throw XCTSkip("The local Columbina.usdz asset is not bundled in this build.")
        }

        let character = try await CharacterAsset.load(in: bundle)
        let bounds = character.visualBounds(recursive: true, relativeTo: nil)
        XCTAssertFalse(bounds.isEmpty)
        XCTAssertEqual(bounds.extents.y, CharacterAsset.referenceHeight, accuracy: 0.001)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.center.x, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.center.z, 0, accuracy: 0.001)
        XCTAssertGreaterThan(modelCount(in: character), 0)
    }

    private func modelCount(in entity: Entity) -> Int {
        let ownCount = entity.components[ModelComponent.self] == nil ? 0 : 1
        return entity.children.reduce(ownCount) { $0 + modelCount(in: $1) }
    }
}

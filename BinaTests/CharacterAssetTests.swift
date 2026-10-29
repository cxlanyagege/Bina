import simd
import Testing
@testable import Bina

@MainActor
struct CharacterAssetTests {
    @Test func normalizesHeightAndPlacesFeetAtOrigin() throws {
        let result = try #require(CharacterBoundsNormalization.make(
            minimum: [2, -1, 4], maximum: [4, 3, 8]
        ))
        #expect(abs(result.scale - 0.4) < 0.0001)
        #expect(result.translation == SIMD3<Float>(-3, 1, -6))
        let feetCenter = SIMD3<Float>(3, -1, 6)
        let normalizedFeet = (feetCenter + result.translation) * result.scale
        #expect(simd_length(normalizedFeet) < 0.0001)
        #expect(abs((3 + result.translation.y) * result.scale - 1.6) < 0.0001)
    }

    @Test func centeredMeterAssetKeepsItsReferenceScale() throws {
        let result = try #require(CharacterBoundsNormalization.make(
            minimum: [-0.5, 0, -0.25], maximum: [0.5, 1.6, 0.25]
        ))
        #expect(abs(result.scale - 1) < 0.0001)
        #expect(result.translation == .zero)
    }

    @Test func supportsExplicitReferenceHeight() throws {
        let result = try #require(CharacterBoundsNormalization.make(
            minimum: [-1, -2, -1], maximum: [1, 2, 1], referenceHeight: 2
        ))
        #expect(result.scale == 0.5)
        #expect(result.translation == SIMD3<Float>(0, 2, 0))
    }

    @Test func rejectsEmptyOrInvertedBounds() {
        #expect(CharacterBoundsNormalization.make(minimum: .zero, maximum: .zero) == nil)
        #expect(CharacterBoundsNormalization.make(minimum: [0, 2, 0], maximum: [1, 1, 1]) == nil)
        #expect(CharacterBoundsNormalization.make(minimum: [2, 0, 0], maximum: [1, 2, 1]) == nil)
    }

    @Test func rejectsNonfiniteBoundsAndReferenceHeight() {
        #expect(CharacterBoundsNormalization.make(minimum: [.nan, 0, 0], maximum: [1, 2, 1]) == nil)
        #expect(CharacterBoundsNormalization.make(minimum: [0, 0, 0], maximum: [1, .infinity, 1]) == nil)
        for height: Float in [0, -1, .nan, .infinity] {
            #expect(CharacterBoundsNormalization.make(minimum: .zero, maximum: [1, 2, 1], referenceHeight: height) == nil)
        }
    }

    @Test func rejectsOverflowingExtents() {
        #expect(CharacterBoundsNormalization.make(
            minimum: [-Float.greatestFiniteMagnitude, 0, 0],
            maximum: [Float.greatestFiniteMagnitude, 2, 1]
        ) == nil)
    }
}

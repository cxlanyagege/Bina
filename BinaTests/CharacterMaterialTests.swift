import RealityKit
import Testing
@testable import Bina

@MainActor
struct CharacterMaterialTests {
    @Test func nestedThinSurfaceRendersBothSidesAndPreservesTransparency() throws {
        var material = PhysicallyBasedMaterial()
        material.faceCulling = .back
        material.blending = .transparent(opacity: .init(scale: 0.4))
        material.roughness = .init(floatLiteral: 0.8)
        let surface = ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [material])
        surface.position = [1, 2, 3]
        let container = Entity()
        container.addChild(surface)
        let root = Entity()
        root.addChild(container)

        CharacterAsset.configureMaterials(in: root)

        let model = try #require(surface.components[ModelComponent.self])
        let result = try #require(model.materials.first as? PhysicallyBasedMaterial)
        #expect(result.faceCulling == .none)
        #expect(result.blending == material.blending)
        #expect(result.opacityThreshold == material.opacityThreshold)
        #expect(result.roughness.scale == material.roughness.scale)
        #expect(surface.position == [1, 2, 3])
    }

    @Test func otherMaterialTypesArePreservedAlongsidePhysicalSurfaces() throws {
        var unlit = UnlitMaterial(color: .white)
        unlit.faceCulling = .front
        let surface = ModelEntity(
            mesh: .generatePlane(width: 1, depth: 1),
            materials: [unlit, PhysicallyBasedMaterial()]
        )

        CharacterAsset.configureMaterials(in: surface)

        let model = try #require(surface.components[ModelComponent.self])
        #expect(model.materials.count == 2)
        let unlitResult = try #require(model.materials[0] as? UnlitMaterial)
        #expect(unlitResult.faceCulling == .front)
        #expect(unlitResult.color.tint == unlit.color.tint)
        let physicalResult = try #require(model.materials[1] as? PhysicallyBasedMaterial)
        #expect(physicalResult.faceCulling == .none)
    }
}

import RealityKit
import UIKit

enum PlaceholderCharacter {
    static let height: Float = 1.6

    /// Uses simple geometry so spatial testing does not depend on an unvalidated character asset.
    static func make() -> Entity {
        let character = Entity()
        character.name = "SpatialPrototypePlaceholder"
        let bodyMaterial = SimpleMaterial(color: UIColor.systemTeal, roughness: 0.8, isMetallic: false)
        let accentMaterial = SimpleMaterial(color: UIColor.white, roughness: 0.8, isMetallic: false)

        func part(_ mesh: MeshResource, at position: SIMD3<Float>, accent: Bool = false) {
            let entity = ModelEntity(mesh: mesh, materials: [accent ? accentMaterial : bodyMaterial])
            entity.position = position
            character.addChild(entity)
        }

        part(.generateSphere(radius: 0.13), at: [0, 1.47, 0])
        part(.generateBox(size: [0.36, 0.5, 0.22], cornerRadius: 0.06), at: [0, 1.07, 0])
        for side: Float in [-1, 1] {
            part(.generateBox(size: [0.12, 0.7, 0.14], cornerRadius: 0.04), at: [side * 0.1, 0.4, 0])
            part(.generateBox(size: [0.13, 0.08, 0.27], cornerRadius: 0.025), at: [side * 0.1, 0.04, -0.045])
            part(.generateBox(size: [0.1, 0.48, 0.12], cornerRadius: 0.04), at: [side * 0.25, 1.05, 0])
        }
        part(.generateBox(size: [0.15, 0.035, 0.015], cornerRadius: 0.008), at: [0, 1.49, -0.125], accent: true)
        part(.generateBox(size: [0.18, 0.04, 0.025], cornerRadius: 0.01), at: [0, 1.18, -0.12], accent: true)
        return character
    }
}

import RealityKit
import UIKit
import simd

/// A foot-range preview in world space, independent of the currently saved anchor.
@MainActor
final class FloorPlacementMarker {
    let root = Entity()
    private var disk: ModelEntity?
    private var feet: Entity?

    init() {
        root.name = "FloorPlacementPreview"
        root.isEnabled = false
    }

    func update(_ preview: FloorPlacementPreview?) {
        guard let preview else {
            root.isEnabled = false
            return
        }
        if disk == nil {
            var material = UnlitMaterial(color: UIColor.systemGreen)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.25))
            let disk = ModelEntity(mesh: .generateCylinder(height: 0.003, radius: 1), materials: [material])
            let feet = Entity()
            for side: Float in [-1, 1] {
                let foot = ModelEntity(
                    mesh: .generateBox(size: [0.07, 0.004, 0.18], cornerRadius: 0.015),
                    materials: [UnlitMaterial(color: .white)])
                foot.position = [side * 0.055, 0.006, 0]
                feet.addChild(foot)
            }
            root.addChild(disk)
            root.addChild(feet)
            self.disk = disk
            self.feet = feet
        }
        root.transform = Transform(matrix: preview.transform)
        root.position.y += 0.006
        disk?.scale = [preview.settings.clearance, 1, preview.settings.clearance]
        let glyphScale = preview.settings.characterScale * min(1, preview.settings.contactRadius / 0.14)
        feet?.scale = SIMD3(repeating: glyphScale)
        feet?.orientation = simd_quatf(angle: preview.settings.headingRadians, axis: [0, 1, 0])
        root.isEnabled = true
    }
}

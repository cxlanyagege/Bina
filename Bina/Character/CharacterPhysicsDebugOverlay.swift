import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Reusable diagnostic geometry; disabled by default and independent of pose ownership.
@MainActor
final class CharacterPhysicsDebugOverlay {
    private let root = Entity()
    private let model: ModelEntity
    private var savedOpacity: OpacityComponent?
    private var overridesOpacity = false
    private let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
    private let sphere = MeshResource.generateSphere(radius: 1)
    private var lines: [ModelEntity] = []
    private var points: [ModelEntity] = []
    private var volumes: [(ModelEntity, ModelEntity, ModelEntity)] = []

    var isVisible: Bool {
        get { root.isEnabled }
        set {
            root.isEnabled = newValue
            if newValue, !overridesOpacity {
                savedOpacity = model.components[OpacityComponent.self]
                model.components.set(OpacityComponent(opacity: (savedOpacity?.opacity ?? 1) * 0.3))
                overridesOpacity = true
            } else if !newValue, overridesOpacity {
                if let savedOpacity { model.components.set(savedOpacity) }
                else { model.components.remove(OpacityComponent.self) }
                overridesOpacity = false
            }
        }
    }

    init(character: Entity, model: ModelEntity) {
        self.model = model
        root.name = "HairPhysicsDebug"
        root.isEnabled = false
        character.addChild(root)
    }

    func remove() {
        isVisible = false
        root.removeFromParent()
    }

    func update(segments: [CharacterHairPhysics.Segment], colliders: [SpringCapsule], isVisible: Bool) {
        self.isVisible = isVisible
        guard isVisible else { return }
        while lines.count < segments.count {
            let line = ModelEntity(mesh: cylinder, materials: [UnlitMaterial(color: .green)])
            let point = ModelEntity(mesh: sphere, materials: [UnlitMaterial(color: .cyan)])
            root.addChild(line); root.addChild(point)
            lines.append(line); points.append(point)
        }
        while volumes.count < colliders.count {
            var material = UnlitMaterial(color: .orange)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.2))
            let line = ModelEntity(mesh: cylinder, materials: [material])
            let start = ModelEntity(mesh: sphere, materials: [material])
            let end = ModelEntity(mesh: sphere, materials: [material])
            for entity in [line, start, end] { root.addChild(entity) }
            volumes.append((line, start, end))
        }
        for (i, segment) in segments.enumerated() {
            setLine(lines[i], start: segment.start, end: segment.end, radius: 0.001)
            points[i].position = segment.end
            points[i].scale = SIMD3(repeating: 0.003)
        }
        for (i, capsule) in colliders.enumerated() {
            let (line, start, end) = volumes[i]
            setLine(line, start: capsule.start, end: capsule.end, radius: capsule.radius)
            start.position = capsule.start; end.position = capsule.end
            start.scale = SIMD3(repeating: capsule.radius); end.scale = start.scale
        }
    }

    private func setLine(_ entity: ModelEntity, start: SIMD3<Float>, end: SIMD3<Float>, radius: Float) {
        let direction = end - start
        let length = simd_length(direction)
        entity.isEnabled = length > 0.000001
        guard entity.isEnabled else { return }
        entity.position = (start + end) / 2
        entity.orientation = simd_quatf(from: [0, 1, 0], to: direction / length)
        entity.scale = [radius, length, radius]
    }
}

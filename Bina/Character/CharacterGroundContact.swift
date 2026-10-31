import Foundation
import RealityKit
import simd

nonisolated enum CharacterGroundContactError: LocalizedError {
    case invalidGeometry
    var errorDescription: String? { "无法校准模型鞋底，仍可使用手动高度放置。" }
}

/// Sole contact is expressed in the normalized model's presentation-parent frame.
nonisolated struct CharacterGroundContact: Equatable {
    let center: SIMD3<Float>
    let radius: Float
    static let placeholder = CharacterGroundContact(center: [0, 0, -0.045], radius: 0.24)

    func correction(scale: Float, heading: Float) -> SIMD3<Float> {
        -simd_quatf(angle: heading, axis: [0, 1, 0]).act(center * scale)
    }

    /// Measure before attachment and before motion changes the imported pose.
    @MainActor static func measure(
        in character: Entity, footwear: CharacterFootwearMode = .waterHeels
    ) throws -> CharacterGroundContact {
        guard character.parent == nil else { throw CharacterGroundContactError.invalidGeometry }
        var models: [ModelEntity] = []
        func collect(_ entity: Entity) {
            if let model = entity as? ModelEntity, !model.jointNames.isEmpty { models.append(model) }
            for child in entity.children { collect(child) }
        }
        collect(character)
        guard models.count == 1, let model = models.first, let component = model.model,
            let skeleton = component.mesh.contents.skeletons.first,
            skeleton.joints.count == model.jointTransforms.count
        else { throw CharacterGroundContactError.invalidGeometry }
        let transforms = model.jointTransforms
        var globals: [simd_float4x4] = []
        for (i, joint) in skeleton.joints.enumerated() {
            if let parent = joint.parentIndex {
                guard parent >= 0, parent < i else { throw CharacterGroundContactError.invalidGeometry }
                globals.append(globals[parent] * transforms[i].matrix)
            } else {
                globals.append(transforms[i].matrix)
            }
        }
        let skin = zip(globals, skeleton.joints).map { $0 * $1.inverseBindPoseMatrix }
        let frame = model.transformMatrix(relativeTo: nil)
        var shoePoints: [SIMD3<Float>] = []
        var skinPoints: [SIMD3<Float>] = []
        for mesh in component.mesh.contents.models {
            for part in mesh.parts {
                guard component.materials.indices.contains(part.materialIndex) else { continue }
                let name = component.materials[part.materialIndex].name
                guard name == "CharacterMaterial_19" || name == "CharacterMaterial_00" else { continue }
                let positions = part.positions.elements
                guard !positions.isEmpty, let influences = part.jointInfluences?.influences.elements,
                    influences.count % positions.count == 0
                else { throw CharacterGroundContactError.invalidGeometry }
                let count = influences.count / positions.count
                guard (1...16).contains(count) else { throw CharacterGroundContactError.invalidGeometry }
                for (i, position) in positions.enumerated() {
                    var point = SIMD4<Float>(repeating: 0)
                    var weight: Float = 0
                    for j in 0..<count {
                        let influence = influences[i * count + j]
                        guard skin.indices.contains(influence.jointIndex), influence.weight.isFinite,
                            influence.weight >= 0
                        else { throw CharacterGroundContactError.invalidGeometry }
                        point += (skin[influence.jointIndex] * SIMD4(position, 1)) * influence.weight
                        weight += influence.weight
                    }
                    let p = frame * point
                    guard abs(weight - 1) < 0.001, (0..<3).allSatisfy({ p[$0].isFinite }) else {
                        throw CharacterGroundContactError.invalidGeometry
                    }
                    let position = SIMD3(p.x, p.y, p.z)
                    if name == "CharacterMaterial_19" {
                        shoePoints.append(position)
                    } else {
                        skinPoints.append(position)
                    }
                }
            }
        }
        guard let shoeBase = shoePoints.map(\.y).min() else { throw CharacterGroundContactError.invalidGeometry }
        // The source's shoe material covers heel ornaments, while exposed toes use skin.
        // Include the lowest eight centimeters of skin to cover both complete feet.
        let footSkin = skinPoints.filter { $0.y <= shoeBase + 0.08 }
        guard !footSkin.isEmpty else { throw CharacterGroundContactError.invalidGeometry }
        let points = footwear == .waterHeels ? shoePoints + footSkin : footSkin
        let lower = points.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min)
        let upper = points.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
        let radius = simd_length(SIMD2(upper.x - lower.x, upper.z - lower.z)) / 2
        guard (-0.1...0.25).contains(lower.y), (0.025...0.5).contains(radius) else {
            throw CharacterGroundContactError.invalidGeometry
        }
        return CharacterGroundContact(
            center: [(lower.x + upper.x) / 2, lower.y, (lower.z + upper.z) / 2], radius: radius)
    }
}

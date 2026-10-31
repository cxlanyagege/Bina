import Foundation
import RealityKit
import simd

nonisolated enum CharacterFootwearMode: String, CaseIterable {
    case waterHeels
    case barefoot
}

nonisolated enum CharacterFootwearError: LocalizedError {
    case invalidBinding(String)

    var errorDescription: String? { "足部形态暂不可用，已保留原始水球高跟与站姿。请检查角色资源后重新运行。" }
}

/// Prepares source-specific footwear meshes, fixed foot poses, and matching contact points.
/// Runtime joint changes are composed into the existing pose owner's array, never written here.
@MainActor
final class CharacterFootwear {
    private let model: ModelEntity
    private let originalMesh: MeshResource
    private let barefootMesh: MeshResource
    private let referenceCount: Int
    private let barefootRotations: [Int: simd_quatf]
    private let waterHeelContact: CharacterGroundContact
    private let barefootContact: CharacterGroundContact

    init(character: Entity, model: ModelEntity, reference: [Transform]) throws {
        guard character.parent == nil, let component = model.model,
            let skeleton = component.mesh.contents.skeletons.first,
            skeleton.joints.count == reference.count, skeleton.joints.map(\.name) == model.jointNames
        else {
            throw CharacterFootwearError.invalidBinding("Footwear requires the unattached imported rig.")
        }
        let heelIndices = Set(
            component.materials.indices.filter {
                component.materials[$0].name == "CharacterMaterial_19"
            })
        guard heelIndices.count == 1 else {
            throw CharacterFootwearError.invalidBinding("The water-heel material is missing or ambiguous.")
        }
        let names = model.jointNames.map { String($0.split(separator: "/").last ?? "") }
        func index(_ name: String) throws -> Int {
            let matches = names.indices.filter { names[$0] == name }
            guard matches.count == 1 else { throw CharacterFootwearError.invalidBinding("Missing foot joint: \(name)") }
            return matches[0]
        }
        let leftAnkle = try index("Joint_0017")
        let leftForefoot = try index("Joint_0018")
        let rightAnkle = try index("Joint_0033")
        let rightForefoot = try index("Joint_0034")
        guard skeleton.joints[leftForefoot].parentIndex == leftAnkle,
            skeleton.joints[rightForefoot].parentIndex == rightAnkle
        else {
            throw CharacterFootwearError.invalidBinding("The calibrated foot hierarchy changed.")
        }
        var globals: [simd_float4x4] = []
        for (i, joint) in skeleton.joints.enumerated() {
            if let parent = joint.parentIndex {
                guard parent >= 0, parent < i else {
                    throw CharacterFootwearError.invalidBinding("Invalid foot topology.")
                }
                globals.append(globals[parent] * reference[i].matrix)
            } else {
                globals.append(reference[i].matrix)
            }
        }
        let characterFromModel = model.transformMatrix(relativeTo: character)
        var rotations: [Int: simd_quatf] = [:]
        for (joint, sign): (Int, Float) in [(leftAnkle, 1), (leftForefoot, -1), (rightAnkle, 1), (rightForefoot, -1)] {
            guard let parentIndex = skeleton.joints[joint].parentIndex else {
                throw CharacterFootwearError.invalidBinding("A calibrated foot joint has no parent.")
            }
            let parent = Transform(matrix: characterFromModel * globals[parentIndex]).rotation
            // Lower the heel while counter-rotating the forefoot to retain its level toe surface.
            let rotation = simd_quatf(angle: sign * 28 * .pi / 180, axis: [1, 0, 0])
            rotations[joint] = simd_normalize(parent.inverse * rotation * parent * reference[joint].rotation)
        }
        var contents = component.mesh.contents
        var removedParts = 0
        for var mesh in contents.models {
            var retained: [MeshResource.Part] = []
            for var part in mesh.parts where !heelIndices.contains(part.materialIndex) {
                let vertexCount = part.positions.elements.count
                guard let indices = part.triangleIndices?.elements, !indices.isEmpty,
                    indices.count % 3 == 0, indices.allSatisfy({ Int($0) < vertexCount })
                else {
                    throw CharacterFootwearError.invalidBinding("Invalid retained mesh indices.")
                }
                // Re-encode imported index views before rebuilding. Their backing-buffer
                // offsets are unsuitable for visionOS 27.2's cross-process mesh validation.
                part.triangleIndices = MeshBuffers.TriangleIndices(indices)
                retained.append(part)
            }
            removedParts += mesh.parts.count - retained.count
            mesh.parts = MeshPartCollection(retained)
            contents.models.update(mesh)
        }
        guard removedParts > 0 else { throw CharacterFootwearError.invalidBinding("The water-heel mesh is missing.") }
        let barefootMesh = try MeshResource.generate(from: contents)
        let originalWeights = BlendShapeWeightsComponent(
            weightsMapping: BlendShapeWeightsMapping(meshResource: component.mesh))
        let barefootWeights = BlendShapeWeightsComponent(
            weightsMapping: BlendShapeWeightsMapping(meshResource: barefootMesh))
        guard originalWeights.weightSet.map(\.id) == barefootWeights.weightSet.map(\.id),
            originalWeights.weightSet.map({ Set($0.weightNames) })
                == barefootWeights.weightSet.map({ Set($0.weightNames) }),
            barefootMesh.contents.skeletons.first?.joints == skeleton.joints
        else {
            throw CharacterFootwearError.invalidBinding("Footwear preparation changed the facial mapping or skeleton.")
        }
        let imported = model.jointTransforms
        defer { model.jointTransforms = imported }
        model.jointTransforms = reference
        let waterContact = try CharacterGroundContact.measure(in: character)
        var barePose = reference
        for (index, rotation) in rotations { barePose[index].rotation = rotation }
        model.jointTransforms = barePose
        let bareContact = try CharacterGroundContact.measure(in: character, footwear: .barefoot)

        self.model = model
        originalMesh = component.mesh
        self.barefootMesh = barefootMesh
        referenceCount = reference.count
        barefootRotations = rotations
        waterHeelContact = waterContact
        barefootContact = bareContact
    }

    func contact(for mode: CharacterFootwearMode) -> CharacterGroundContact {
        mode == .waterHeels ? waterHeelContact : barefootContact
    }

    func apply(_ mode: CharacterFootwearMode, to transforms: inout [Transform]) throws {
        guard transforms.count == referenceCount, var component = model.model,
            component.mesh === originalMesh || component.mesh === barefootMesh
        else {
            throw CharacterFootwearError.invalidBinding("The footwear rig or mesh was replaced.")
        }
        let mesh = mode == .waterHeels ? originalMesh : barefootMesh
        if component.mesh !== mesh {
            // Keep every material slot and current facial/debug state; remove geometry instead of
            // zeroing opacity, which can leave the hidden heel's shadow in the renderer.
            component.mesh = mesh
            model.model = component
        }
        if mode == .barefoot {
            for (index, rotation) in barefootRotations { transforms[index].rotation = rotation }
        }
    }

    func restore() {
        guard var component = model.model, component.mesh === barefootMesh else { return }
        component.mesh = originalMesh
        model.model = component
    }
}

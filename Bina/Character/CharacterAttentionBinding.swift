import RealityKit
import simd

/// Converts upright character-frame attention into the asset's parent-local joint axes.
@MainActor
struct CharacterAttentionBinding {
    private let neck: Int
    private let head: Int
    private let neckParents: [Int]
    private let headParents: [Int]
    private let neutralHeadPosition: SIMD3<Float>

    init(model: ModelEntity, character: Entity, reference: [Transform], neck: Int, head: Int) throws {
        guard let skeleton = model.model?.mesh.contents.skeletons.first,
              skeleton.joints.count == reference.count,
              skeleton.joints.map(\.name) == model.jointNames else {
            throw CharacterIdleError.invalidConfiguration("Head attention requires the imported mesh skeleton.")
        }
        func parents(of joint: Int) throws -> [Int] {
            var result: [Int] = []
            var index = joint
            while let parent = skeleton.joints[index].parentIndex {
                guard parent >= 0, parent < index else {
                    throw CharacterIdleError.invalidConfiguration("The attention joints have invalid parent topology.")
                }
                result.append(parent)
                index = parent
            }
            return result.reversed()
        }
        self.neck = neck
        self.head = head
        neckParents = try parents(of: neck)
        headParents = try parents(of: head)
        guard headParents.contains(neck) else {
            throw CharacterIdleError.invalidConfiguration("The head joint must descend from the neck joint.")
        }
        let characterFromHead = model.transformMatrix(relativeTo: character)
            * Self.parentMatrix(headParents, transforms: reference) * reference[head].matrix
        neutralHeadPosition = SIMD3(characterFromHead.columns.3.x, characterFromHead.columns.3.y, characterFromHead.columns.3.z)
    }

    func direction(toward worldTarget: SIMD3<Float>, character: Entity) -> SIMD3<Float> {
        let worldFromCharacter = character.transformMatrix(relativeTo: nil)
        let origin = worldFromCharacter * SIMD4(neutralHeadPosition, 1)
        // Preserve physical distance when preview scale changes; only remove rotation.
        return Transform(matrix: worldFromCharacter).rotation.inverse.act(
            worldTarget - SIMD3(origin.x, origin.y, origin.z)
        )
    }

    func apply(_ angles: SIMD2<Float>, to transforms: inout [Transform], model: ModelEntity, character: Entity) {
        guard angles != .zero else { return }
        let characterFromModel = model.transformMatrix(relativeTo: character)
        let neckRotation = CharacterHeadAttention.rotation(for: angles * 0.35)
        rotate(neck, parents: neckParents, by: neckRotation, transforms: &transforms, characterFromModel: characterFromModel)
        // Remove the neck's contribution so the combined turn has the requested angle.
        let headRotation = CharacterHeadAttention.rotation(for: angles) * neckRotation.inverse
        rotate(head, parents: headParents, by: headRotation, transforms: &transforms, characterFromModel: characterFromModel)
    }

    private func rotate(
        _ joint: Int, parents: [Int], by rotation: simd_quatf,
        transforms: inout [Transform], characterFromModel: simd_float4x4
    ) {
        let parent = Transform(matrix: characterFromModel * Self.parentMatrix(parents, transforms: transforms)).rotation
        transforms[joint].rotation = simd_normalize(parent.inverse * rotation * parent * transforms[joint].rotation)
    }

    private static func parentMatrix(_ parents: [Int], transforms: [Transform]) -> simd_float4x4 {
        parents.reduce(matrix_identity_float4x4) { $0 * transforms[$1].matrix }
    }
}

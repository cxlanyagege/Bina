import Foundation
import RealityKit
import simd

/// Binds a small spring simulation to accessory bones without owning the final pose write.
@MainActor
final class CharacterHairPhysics {
    struct Segment {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        let radius: Float
    }
    struct Diagnostics {
        let segments: [Segment]
        let colliders: [SpringCapsule]
        let maximumPenetration: Float
        let resetCount: Int
    }
    private struct Bone {
        let index: Int
        let parents: [Int]
        let tail: SIMD3<Float>
    }
    private struct Chain {
        let settings: CharacterPhysicsProfile.Chain
        let bones: [Bone]
    }
    private struct Collider {
        let settings: CharacterPhysicsProfile.Collider
        let path: [Int]
    }

    private let model: ModelEntity
    private let character: Entity
    private let characterFromModel: simd_float4x4
    private let chains: [Chain]
    private let colliders: [Collider]
    private var states: [[SpringBoneState]] = []
    private var clock = SpringSimulationClock()
    private var needsReset = true
    private var resetCount = 0
    private var influence: Float = 1
    private var lastPlacement: simd_float4x4?
    private var overlay: CharacterPhysicsDebugOverlay?
    private(set) var diagnostics = Diagnostics(segments: [], colliders: [], maximumPenetration: 0, resetCount: 0)

    init(model: ModelEntity, character: Entity, reference: [Transform], pose: CharacterIdlePose, profile: CharacterPhysicsProfile) throws {
        try profile.validate()
        try pose.validate()
        guard profile.modelSHA256 == pose.modelSHA256,
              let skeleton = model.model?.mesh.contents.skeletons.first,
              skeleton.joints.count == reference.count, skeleton.joints.map(\.name) == model.jointNames else {
            throw CharacterPhysicsError.invalidBinding("Profile and imported skeleton do not agree.")
        }
        let leaves = model.jointNames.map { String($0.split(separator: "/").last!) }
        guard Set(leaves).count == leaves.count else {
            throw CharacterPhysicsError.invalidBinding("Ambiguous joint names.")
        }
        let indices = Dictionary(uniqueKeysWithValues: leaves.enumerated().map { ($1, $0) })
        func index(_ name: String) throws -> Int {
            guard let i = indices[name] else { throw CharacterPhysicsError.invalidBinding("Missing \(name)") }
            return i
        }
        func parents(_ index: Int) throws -> [Int] {
            var result: [Int] = [], current = index
            while let parent = skeleton.joints[current].parentIndex {
                guard parent >= 0, parent < current else { throw CharacterPhysicsError.invalidBinding("Invalid parent topology.") }
                result.append(parent); current = parent
            }
            return result.reversed()
        }
        let characterFromModel = model.transformMatrix(relativeTo: character)
        let head = try index(pose.motionJoints["head"]!)
        let protected = Set(pose.fixedJoints + Array(pose.motionJoints.values) + Array(pose.jointDeltas.keys))
        var chains: [Chain] = []
        for settings in profile.chains {
            let jointIndices = try settings.joints.map(index)
            var bones: [Bone] = []
            for (offset, i) in jointIndices.enumerated() {
                let path = try parents(i)
                guard path.contains(head), !protected.contains(leaves[i]),
                      offset == 0 || skeleton.joints[i].parentIndex == jointIndices[offset - 1] else {
                    throw CharacterPhysicsError.invalidBinding("A hair chain crosses protected or noncontiguous joints.")
                }
                let tail: SIMD3<Float>
                if offset + 1 < jointIndices.count {
                    tail = reference[jointIndices[offset + 1]].translation
                } else { tail = SIMD3(settings.tipOffset) }
                let length = simd_length(tail)
                guard length.isFinite, length > 0.001, length < 0.5 else {
                    throw CharacterPhysicsError.invalidBinding("Invalid hair segment length.")
                }
                bones.append(Bone(index: i, parents: path, tail: tail))
            }
            chains.append(Chain(settings: settings, bones: bones))
        }
        self.model = model
        self.character = character
        self.characterFromModel = characterFromModel
        self.chains = chains
        colliders = try profile.colliders.map { settings in
            let i = try index(settings.joint)
            guard !profile.chains.flatMap(\.joints).contains(settings.joint) else {
                throw CharacterPhysicsError.invalidBinding("A collider cannot depend on a simulated hair joint.")
            }
            return Collider(settings: settings, path: try parents(i) + [i])
        }
    }

    func invalidate(restartBlend: Bool = false) {
        needsReset = true
        if restartBlend { influence = 0 }
    }

    func showDebug(_ visible: Bool) {
        if visible, overlay == nil { overlay = CharacterPhysicsDebugOverlay(character: character, model: model) }
        if visible {
            let transforms = model.jointTransforms
            let segments = chains.flatMap { chain in chain.bones.map { bone in
                let frame = global(bone.parents + [bone.index], transforms: transforms)
                return Segment(start: Self.point(frame, .zero), end: Self.point(frame, bone.tail), radius: chain.settings.radius)
            } }
            overlay?.update(segments: segments, colliders: collisionShapes(transforms), isVisible: true)
        } else { overlay?.isVisible = false }
    }

    func dispose() {
        overlay?.remove()
        overlay = nil
    }

    func apply(to transforms: inout [Transform], deltaTime: TimeInterval, enabled: Bool, poseWeight: Float, showsDebug: Bool) throws {
        let placement = character.transformMatrix(relativeTo: nil)
        if let lastPlacement, Self.matrixDifference(placement, lastPlacement) > 0.02 { needsReset = true }
        lastPlacement = placement
        let tick = clock.advance(deltaTime)
        needsReset = needsReset || tick.needsReset
        let step = Float(min(max(deltaTime.isFinite ? deltaTime : 0, 0), 0.05))
        influence = enabled ? min(1, influence + step / 0.25) : max(0, influence - step / 0.25)
        if influence == 0, !enabled, !showsDebug { needsReset = true; return }
        let primary = transforms
        let capsules = collisionShapes(primary)
        if needsReset || states.isEmpty {
            states = chains.map { chain in chain.bones.map { bone in
                let frame = global(bone.parents + [bone.index], transforms: primary)
                return SpringBoneState(tail: Self.point(frame, bone.tail))
            } }
            clock.reset()
            needsReset = false
            resetCount += 1
            // Resolve initial contacts before presentation, with no carried velocity.
            for _ in 0..<16 { _ = try sample(primary, capsules: capsules, advancesTime: true) }
            for c in states.indices {
                states[c] = states[c].map { SpringBoneState(tail: $0.tail) }
            }
        }
        for _ in 0..<tick.steps { _ = try sample(primary, capsules: capsules, advancesTime: true) }
        var result = try sample(primary, capsules: capsules, advancesTime: false)
        let weight = influence * poseWeight
        if weight < 1 {
            for chain in chains {
                for bone in chain.bones {
                    result[bone.index].rotation = simd_slerp(primary[bone.index].rotation, result[bone.index].rotation, weight)
                }
            }
        }
        let segments = chains.flatMap { chain in chain.bones.map { bone in
            let frame = global(bone.parents + [bone.index], transforms: result)
            return Segment(start: Self.point(frame, .zero), end: Self.point(frame, bone.tail), radius: chain.settings.radius)
        } }
        let penetration = segments.flatMap { segment in capsules.map { capsule -> Float in
            let pair = SpringCapsule.closestPair(segment.start, segment.end, capsule.start, capsule.end)
            return pair.amount > 0.01 ? max(0, segment.radius + capsule.radius - simd_distance(pair.first, pair.second)) : 0
        } }.max() ?? 0
        diagnostics = Diagnostics(segments: segments, colliders: capsules, maximumPenetration: penetration, resetCount: resetCount)
        transforms = result
        if showsDebug {
            if overlay == nil { overlay = CharacterPhysicsDebugOverlay(character: character, model: model) }
            overlay?.update(segments: segments, colliders: capsules, isVisible: true)
        } else { overlay?.isVisible = false }
    }

    private func sample(_ primary: [Transform], capsules: [SpringCapsule], advancesTime: Bool) throws -> [Transform] {
        var result = primary
        for (c, chain) in chains.enumerated() {
            for (b, bone) in chain.bones.enumerated() {
                let parent = global(bone.parents, transforms: result)
                let frame = parent * primary[bone.index].matrix
                let root = Self.point(frame, .zero), restTail = Self.point(frame, bone.tail)
                if advancesTime {
                    guard states[c][b].advance(root: root, restTail: restTail, step: Float(SpringSimulationClock.step), settings: chain.settings, colliders: capsules) else {
                        throw CharacterPhysicsError.unstableSimulation
                    }
                }
                let desired = states[c][b].tail - root
                guard simd_length_squared(desired) > 0.00000001 else { throw CharacterPhysicsError.unstableSimulation }
                let rotation = simd_quatf(from: simd_normalize(restTail - root), to: simd_normalize(desired))
                let parentRotation = Transform(matrix: parent).rotation
                let local = simd_normalize(parentRotation.inverse * rotation * parentRotation * primary[bone.index].rotation)
                guard (0..<4).allSatisfy({ local.vector[$0].isFinite }) else { throw CharacterPhysicsError.unstableSimulation }
                result[bone.index].rotation = local
            }
        }
        return result
    }

    private func collisionShapes(_ transforms: [Transform]) -> [SpringCapsule] {
        colliders.map { collider in
            let frame = global(collider.path, transforms: transforms)
            return SpringCapsule(start: Self.point(frame, SIMD3(collider.settings.start)),
                                 end: Self.point(frame, SIMD3(collider.settings.end)), radius: collider.settings.radius)
        }
    }

    private func global(_ path: [Int], transforms: [Transform]) -> simd_float4x4 {
        path.reduce(characterFromModel) { $0 * transforms[$1].matrix }
    }

    private static func point(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let result = matrix * SIMD4(point, 1)
        return SIMD3(result.x, result.y, result.z)
    }

    private static func matrixDifference(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        (0..<4).flatMap { c in (0..<4).map { r in abs(a[c][r] - b[c][r]) } }.max() ?? 0
    }
}

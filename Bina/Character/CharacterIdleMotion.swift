import Foundation
import Observation
import RealityKit
import simd

/// Owns the current character's joint presentation independently of world placement.
@MainActor
@Observable
final class CharacterIdleMotion {
    private(set) var mode = CharacterIdlePlayback.Mode.playing
    @ObservationIgnored private var playback = CharacterIdlePlayback()
    @ObservationIgnored private let rigs: [Rig]

    var cycleTime: TimeInterval { playback.cycleTime }

    init(character: Entity, pose: CharacterIdlePose) throws {
        try pose.validate()
        rigs = try Self.skinnedModels(in: character).map { try Rig(model: $0, pose: pose) }
        guard !rigs.isEmpty else { throw CharacterIdleError.missingSkeleton }
        applyPose()
    }

    func advance(by deltaTime: TimeInterval, isVisible: Bool) {
        guard playback.advance(by: deltaTime, isVisible: isVisible) else { return }
        applyPose()
    }

    func pause() {
        playback.pause()
        mode = playback.mode
    }

    func resume() {
        playback.resume()
        mode = playback.mode
    }

    func showReference() {
        playback.showReference()
        mode = playback.mode
        for rig in rigs { rig.model.jointTransforms = rig.reference }
    }

    func showNatural() {
        playback.showNatural()
        mode = playback.mode
        applyPose()
    }

    private func applyPose() {
        let weight = playback.naturalPoseWeight
        let breath = playback.breath * weight
        let sway = playback.sway * weight
        for rig in rigs {
            var transforms = rig.natural
            if weight < 1 {
                for index in transforms.indices {
                    let source = rig.reference[index]
                    let target = rig.natural[index]
                    transforms[index] = Transform(
                        scale: simd_mix(source.scale, target.scale, SIMD3(repeating: weight)),
                        rotation: simd_slerp(source.rotation, target.rotation, weight),
                        translation: simd_mix(source.translation, target.translation, SIMD3(repeating: weight))
                    )
                }
            }
            // Only upper-body joints move. The pelvis, legs, feet, model pivot,
            // and world anchor retain their reference transforms.
            Self.rotate(&transforms[rig.spine], degrees: -0.12 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.spine], degrees: 0.16 * sway, axis: [0, 0, 1])
            Self.rotate(&transforms[rig.chest], degrees: 0.45 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.neck], degrees: -0.18 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.head], degrees: -0.08 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.head], degrees: 0.18 * sway, axis: [0, 1, 0])
            rig.model.jointTransforms = transforms
        }
    }

    private static func rotate(_ transform: inout Transform, degrees: Float, axis: SIMD3<Float>) {
        transform.rotation = simd_normalize(
            transform.rotation * simd_quatf(angle: degrees * .pi / 180, axis: axis)
        )
    }

    private static func skinnedModels(in entity: Entity) -> [ModelEntity] {
        let own = (entity as? ModelEntity).map { $0.jointNames.isEmpty ? [] : [$0] } ?? []
        return own + entity.children.flatMap { skinnedModels(in: $0) }
    }

    @MainActor
    private struct Rig {
        let model: ModelEntity
        let reference: [Transform]
        let natural: [Transform]
        let spine: Int
        let chest: Int
        let neck: Int
        let head: Int

        init(model: ModelEntity, pose: CharacterIdlePose) throws {
            self.model = model
            reference = model.jointTransforms
            let leaves = model.jointNames.map { String($0.split(separator: "/").last ?? "") }
            guard reference.count == leaves.count, Set(leaves).count == leaves.count else {
                throw CharacterIdleError.invalidConfiguration("The imported skeleton has ambiguous joint paths.")
            }
            let indices = Dictionary(uniqueKeysWithValues: leaves.enumerated().map { ($1, $0) })
            func index(_ name: String) throws -> Int {
                guard let result = indices[name] else { throw CharacterIdleError.missingJoint(name) }
                return result
            }
            func roleIndex(_ role: String) throws -> Int {
                guard let name = pose.motionJoints[role] else {
                    throw CharacterIdleError.invalidConfiguration("Missing motion role: \(role)")
                }
                return try index(name)
            }
            var target = reference
            for (name, values) in pose.jointDeltas {
                let joint = try index(name)
                let delta = simd_float4x4(columns: (
                    SIMD4(values[0..<4]), SIMD4(values[4..<8]),
                    SIMD4(values[8..<12]), SIMD4(values[12..<16])
                ))
                let value = Transform(matrix: reference[joint].matrix * delta)
                guard (0..<3).allSatisfy({ value.scale[$0].isFinite && value.scale[$0] > 0.5
                    && value.scale[$0] < 2 && value.translation[$0].isFinite }),
                      (0..<4).allSatisfy({ value.rotation.vector[$0].isFinite }) else {
                    throw CharacterIdleError.invalidConfiguration("A joint delta produces a degenerate transform.")
                }
                target[joint] = value
            }
            for name in pose.fixedJoints { _ = try index(name) }
            natural = target
            spine = try roleIndex("spine")
            chest = try roleIndex("chest")
            neck = try roleIndex("neck")
            head = try roleIndex("head")
        }
    }
}

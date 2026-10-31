import Foundation
import Observation
import OSLog
import RealityKit
import simd

/// Owns the current character's joint presentation independently of world placement.
@MainActor
@Observable
final class CharacterIdleMotion {
    private(set) var mode = CharacterIdlePlayback.Mode.playing
    var isAttentionEnabled = true
    var isHairPhysicsEnabled = true {
        didSet { if isHairPhysicsEnabled { hairPhysics?.invalidate(restartBlend: true) } }
    }
    var showsPhysicsDebug = false {
        didSet { hairPhysics?.showDebug(showsPhysicsDebug && mode != .reference) }
    }
    private(set) var isHairPhysicsAvailable = false
    private(set) var hairPhysicsMessage: String? = CharacterPhysicsError.missingProfile.errorDescription
    private(set) var physicsTimingDescription: String?
    private(set) var face: CharacterFaceMotion?
    private(set) var faceMessage: String? = CharacterFaceError.missingProfile.errorDescription
    private(set) var footwearMode = CharacterFootwearMode.waterHeels
    private(set) var footwearMessage: String?
    private(set) var footwear: CharacterFootwear?
    @ObservationIgnored private var playback = CharacterIdlePlayback()
    @ObservationIgnored private var attention = CharacterHeadAttention()
    @ObservationIgnored private let character: Entity
    @ObservationIgnored private let rigs: [Rig]
    @ObservationIgnored private let modelSHA256: String
    @ObservationIgnored private var hairPhysics: CharacterHairPhysics?
    @ObservationIgnored private var physicsDurations: [Double] = []
    @ObservationIgnored private var timingCursor = 0
    @ObservationIgnored private let logger = Logger(subsystem: "Bina", category: "CharacterPhysics")
    @ObservationIgnored private let faceLogger = Logger(subsystem: "Bina", category: "CharacterFace")
    @ObservationIgnored private let footwearLogger = Logger(subsystem: "Bina", category: "CharacterFootwear")

    var cycleTime: TimeInterval { playback.cycleTime }
    var hairPhysicsDiagnostics: CharacterHairPhysics.Diagnostics? { hairPhysics?.diagnostics }
    var canChangeFootwear: Bool { footwear != nil && mode == .playing }
    var footwearGroundContact: CharacterGroundContact? {
        footwear?.contact(for: mode == .reference ? .waterHeels : footwearMode)
    }

    func configureFootwear() throws {
        guard rigs.count == 1, footwear == nil else {
            throw CharacterFootwearError.invalidBinding("Footwear requires one unconfigured rig.")
        }
        let rig = rigs[0]
        footwear = try CharacterFootwear(character: character, model: rig.model, reference: rig.reference)
        footwearMessage = nil
    }

    func setFootwearMode(_ value: CharacterFootwearMode) {
        guard canChangeFootwear, footwearMode != value else { return }
        footwearMode = value
        applyPose()
    }

    func reportFootwearUnavailable(_ error: Error) {
        footwear?.restore()
        footwear = nil
        footwearMode = .waterHeels
        footwearMessage = (error as? LocalizedError)?.errorDescription
            ?? CharacterFootwearError.invalidBinding("Footwear preparation failed.").errorDescription
        footwearLogger.error("Footwear unavailable: \(String(describing: error), privacy: .private)")
    }

    func configureFace(_ profile: CharacterFaceProfile) throws {
        guard rigs.count == 1, profile.modelSHA256 == modelSHA256 else { throw CharacterFaceError.mismatchedAsset }
        let rig = rigs[0]
        let binding = try CharacterFaceBinding(model: rig.model, profile: profile,
            referenceWeights: rig.referenceFaceWeights, referenceMaterials: rig.referenceMaterials)
        let replacement = CharacterFaceMotion(binding: binding)
        face?.restoreReference()
        face = replacement
        faceMessage = nil
        if mode == .reference { replacement.restoreReference() }
        else { try replacement.present(influence: 1) }
    }

    func reportFaceUnavailable(_ error: Error) {
        face?.restoreReference()
        face = nil
        faceMessage = (error as? CharacterFaceError)?.errorDescription
            ?? "无法读取面部数据，已保留原模型表情。请检查资源后重新运行。"
        faceLogger.error("Face presentation unavailable: \(String(describing: error), privacy: .private)")
    }

    func configureHairPhysics(_ profile: CharacterPhysicsProfile, pose: CharacterIdlePose) throws {
        guard rigs.count == 1 else { throw CharacterPhysicsError.invalidBinding("Expected one character rig.") }
        let rig = rigs[0]
        let replacement = try CharacterHairPhysics(model: rig.model, character: character, reference: rig.reference, pose: pose, profile: profile)
        hairPhysics?.dispose()
        hairPhysics = replacement
        isHairPhysicsAvailable = true
        hairPhysicsMessage = nil
        applyPose()
    }

    func reportHairPhysicsUnavailable(_ error: Error) {
        hairPhysics?.dispose()
        hairPhysics = nil
        isHairPhysicsAvailable = false
        hairPhysicsMessage = (error as? CharacterPhysicsError)?.errorDescription
            ?? "无法读取头发物理数据，已保留原有动作。请检查物理资源后重新运行。"
        logger.error("Hair physics unavailable: \(String(describing: error), privacy: .private)")
    }

    func recordPhysicsTiming() {
        guard !physicsDurations.isEmpty else {
            physicsTimingDescription = "角色显示并播放后可记录物理计算耗时。"
            return
        }
        let average = physicsDurations.reduce(0, +) / Double(physicsDurations.count)
        let peak = physicsDurations.max() ?? 0
        physicsTimingDescription = String(format: "最近 %d 帧：平均 %.2f ms，峰值 %.2f ms。仅含物理 CPU 计算。", physicsDurations.count, average * 1000, peak * 1000)
    }

    init(character: Entity, pose: CharacterIdlePose) throws {
        try pose.validate()
        self.character = character
        modelSHA256 = pose.modelSHA256
        rigs = try Self.skinnedModels(in: character).map { try Rig(model: $0, character: character, pose: pose) }
        guard !rigs.isEmpty else { throw CharacterIdleError.missingSkeleton }
        applyPose()
    }

    func advance(by deltaTime: TimeInterval, isVisible: Bool, attentionTarget: SIMD3<Float>? = nil) {
        guard isVisible else {
            attention.invalidateTarget()
            hairPhysics?.invalidate()
            return
        }
        guard playback.advance(by: deltaTime, isVisible: isVisible) else { return }
        let direction = isAttentionEnabled ? attentionTarget.map {
            rigs[0].attentionBinding.direction(toward: $0, character: character)
        } : nil
        attention.advance(by: deltaTime, direction: direction, poseWeight: playback.naturalPoseWeight)
        applyPose(deltaTime: deltaTime)
    }

    func pause() {
        playback.pause()
        mode = playback.mode
    }

    func resume() {
        playback.resume()
        mode = playback.mode
    }

    func invalidateAttentionTarget() {
        attention.invalidateTarget()
        hairPhysics?.invalidate()
    }

    func showReference() {
        playback.showReference()
        attention.reset()
        hairPhysics?.invalidate()
        hairPhysics?.showDebug(false)
        mode = playback.mode
        for rig in rigs {
            var transforms = rig.reference
            do { try footwear?.apply(.waterHeels, to: &transforms) }
            catch { reportFootwearUnavailable(error) }
            rig.model.jointTransforms = transforms
        }
        face?.restoreReference()
    }

    func showNatural() {
        playback.showNatural()
        attention.reset()
        hairPhysics?.invalidate()
        mode = playback.mode
        applyPose()
    }

    private func applyPose(deltaTime: TimeInterval = 0) {
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
            // Each footwear mode supplies a fixed foot pose. Idle and attention
            // still affect only the upper body; world placement has a separate owner.
            do { try footwear?.apply(footwearMode, to: &transforms) }
            catch { reportFootwearUnavailable(error) }
            Self.rotate(&transforms[rig.spine], degrees: -0.12 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.spine], degrees: 0.16 * sway, axis: [0, 0, 1])
            Self.rotate(&transforms[rig.chest], degrees: 0.45 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.neck], degrees: -0.18 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.head], degrees: -0.08 * breath, axis: [1, 0, 0])
            Self.rotate(&transforms[rig.head], degrees: 0.18 * sway, axis: [0, 1, 0])
            rig.attentionBinding.apply(attention.angles, to: &transforms, model: rig.model, character: character)
            if let hairPhysics {
                let start = ProcessInfo.processInfo.systemUptime
                do {
                    try hairPhysics.apply(to: &transforms, deltaTime: deltaTime, enabled: isHairPhysicsEnabled,
                                          poseWeight: weight, showsDebug: showsPhysicsDebug)
                    let duration = ProcessInfo.processInfo.systemUptime - start
                    if physicsDurations.count < 600 { physicsDurations.append(duration) }
                    else {
                        physicsDurations[timingCursor] = duration
                        timingCursor = (timingCursor + 1) % 600
                    }
                } catch { reportHairPhysicsUnavailable(error) }
            }
            rig.model.jointTransforms = transforms
        }
        // Facial weights and cover visibility share playback gating, while the
        // skeleton remains under the single joint-transform writer above.
        do { try face?.advance(by: deltaTime, influence: 1) }
        catch { reportFaceUnavailable(error) }
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
        let referenceFaceWeights: BlendShapeWeightsComponent?
        let referenceMaterials: [any Material]
        let natural: [Transform]
        let spine: Int
        let chest: Int
        let neck: Int
        let head: Int
        let attentionBinding: CharacterAttentionBinding

        init(model: ModelEntity, character: Entity, pose: CharacterIdlePose) throws {
            self.model = model
            reference = model.jointTransforms
            referenceFaceWeights = model.components[BlendShapeWeightsComponent.self]
            referenceMaterials = model.model?.materials ?? []
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
            attentionBinding = try CharacterAttentionBinding(
                model: model, character: character, reference: reference, neck: neck, head: head
            )
        }
    }
}

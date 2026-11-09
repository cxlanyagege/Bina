import Observation

/// Observable preview intent with non-observed per-frame facial playback state.
@MainActor
@Observable
final class CharacterFaceMotion {
    var eyeState = CharacterFacePlayback.EyeState.coveredClosed
    var expression = CharacterFacePlayback.Expression.neutral
    var mouthPose = CharacterFacePlayback.MouthPose.relaxed
    var automaticBlink = true
    var followsDialogue = true
    @ObservationIgnored private var playback: CharacterFacePlayback
    @ObservationIgnored private let binding: CharacterFaceBinding
    @ObservationIgnored private var conversationCue = CharacterConversationCue.idle
    @ObservationIgnored private var speechMouth: Float = 0
    @ObservationIgnored private var dialogueExpression: DialogueExpression?

    var sample: CharacterFacePlayback.Sample {
        let baseline = playback.sample
        var channels = baseline.channels
        if conversationCue == .listening || conversationCue == .thinking {
            channels["browRaise"] = max(channels["browRaise"] ?? 0, conversationCue == .listening ? 0.08 : 0.04)
        }
        if conversationCue == .speaking { channels["mouthOpen"] = max(channels["mouthOpen"] ?? 0, speechMouth) }
        return .init(coveringOpacity: baseline.coveringOpacity, channels: channels)
    }

    /// Overlay conversation cues without replacing selected eye forms or manual facial intent.
    func setConversationCue(_ cue: CharacterConversationCue, mouth: Float, expression: DialogueExpression? = nil) {
        conversationCue = cue
        speechMouth = mouth.isFinite ? min(0.35, max(0, mouth)) : 0
        dialogueExpression = expression
    }

    init(binding: CharacterFaceBinding, seed: UInt64 = .random(in: .min ... .max)) {
        self.binding = binding
        playback = CharacterFacePlayback(seed: seed)
    }

    func advance(by deltaTime: Double, influence: Float) throws {
        let automatic = followsDialogue ? dialogueExpression ?? .calm : nil
        let target: CharacterFacePlayback.Expression
        let strength: Float
        if let automatic {
            switch automatic.affect {
            case .calm: target = .neutral; strength = 0
            case .warm: target = .gentleSmile; strength = 0.6 * automatic.strength
            case .cheerful: target = .gentleSmile; strength = automatic.strength
            case .curious: target = .curious; strength = 0.8 * automatic.strength
            case .concerned: target = .curious; strength = 0.3 * automatic.strength
            }
        } else {
            target = expression
            strength = 1
        }
        playback.advance(by: deltaTime, intent: .init(eyeState: eyeState, expression: target, expressionStrength: strength,
                                                    mouthPose: mouthPose, automaticBlink: automaticBlink))
        try present(influence: influence)
    }

    func present(influence: Float) throws { try binding.apply(sample, influence: influence) }

    func previewBlink() {
        guard eyeState == .uncoveredOpen else { return }
        playback.requestBlink()
    }

    func resetPreview() {
        eyeState = .coveredClosed
        expression = .neutral
        mouthPose = .relaxed
        automaticBlink = true
        followsDialogue = true
        playback.cancelBlink()
    }

    func restoreReference() {
        conversationCue = .idle
        speechMouth = 0
        dialogueExpression = nil
        binding.restore()
        playback.reset()
    }
}

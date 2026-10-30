import Observation

/// Observable preview intent with non-observed per-frame facial playback state.
@MainActor
@Observable
final class CharacterFaceMotion {
    var eyeState = CharacterFacePlayback.EyeState.coveredClosed
    var expression = CharacterFacePlayback.Expression.neutral
    var mouthPose = CharacterFacePlayback.MouthPose.relaxed
    var automaticBlink = true
    @ObservationIgnored private var playback: CharacterFacePlayback
    @ObservationIgnored private let binding: CharacterFaceBinding

    var sample: CharacterFacePlayback.Sample { playback.sample }

    init(binding: CharacterFaceBinding, seed: UInt64 = .random(in: .min ... .max)) {
        self.binding = binding
        playback = CharacterFacePlayback(seed: seed)
    }

    func advance(by deltaTime: Double, influence: Float) throws {
        playback.advance(by: deltaTime, intent: .init(eyeState: eyeState, expression: expression,
                                                    mouthPose: mouthPose, automaticBlink: automaticBlink))
        try present(influence: influence)
    }

    func present(influence: Float) throws { try binding.apply(playback.sample, influence: influence) }

    func previewBlink() {
        guard eyeState == .uncoveredOpen else { return }
        playback.requestBlink()
    }

    func resetPreview() {
        eyeState = .coveredClosed
        expression = .neutral
        mouthPose = .relaxed
        automaticBlink = true
        playback.cancelBlink()
    }

    func restoreReference() {
        binding.restore()
        playback.reset()
    }
}

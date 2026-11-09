import Foundation

/// Facial intent and timing, independent of rendering and skeletal pose ownership.
nonisolated struct CharacterFacePlayback {
    enum EyeState: String, CaseIterable { case coveredClosed, uncoveredOpen }
    enum Expression: String, CaseIterable { case neutral, gentleSmile, curious }
    enum MouthPose: String, CaseIterable { case relaxed, open, round }

    struct Intent {
        var eyeState = EyeState.coveredClosed
        var expression = Expression.neutral
        var expressionStrength: Float = 1
        var mouthPose = MouthPose.relaxed
        var automaticBlink = true
    }

    struct Sample: Equatable {
        let coveringOpacity: Float
        let channels: [String: Float]
    }

    private let initialSeed: UInt64
    private var randomState: UInt64
    private var openness: Float = 0
    private var smile: Float = 0
    private var curiosity: Float = 0
    private var mouthOpen: Float = 0
    private var mouthRound: Float = 0
    private var blinkElapsed: TimeInterval?
    private var timeUntilBlink: TimeInterval = 0
    private var queuedBlink = false
    private var previousEyeState = EyeState.coveredClosed

    init(seed: UInt64 = 1) {
        initialSeed = seed
        randomState = seed
        timeUntilBlink = nextInterval()
    }

    var sample: Sample {
        // Covering and eye-opening intervals do not overlap, including reversals.
        let covering = 1 - Self.smooth(openness / 0.45)
        let closed = 1 - Self.smooth((openness - 0.45) / 0.55)
        return Sample(coveringOpacity: covering, channels: [
            "blink": max(closed, Self.blinkWeight(at: blinkElapsed)),
            "smile": Self.smooth(smile) * 0.22,
            "browSmile": Self.smooth(smile) * 0.15,
            "browRaise": Self.smooth(curiosity) * 0.18,
            "mouthOpen": Self.smooth(mouthOpen) * 0.35,
            "mouthRound": Self.smooth(mouthRound) * 0.35
        ])
    }

    mutating func requestBlink() { queuedBlink = true }

    mutating func reset() { self = Self(seed: initialSeed) }

    mutating func cancelBlink() {
        blinkElapsed = nil
        queuedBlink = false
        timeUntilBlink = nextInterval()
    }

    /// Hidden and paused scenes do not call this method; delayed frames cannot catch up.
    mutating func advance(by deltaTime: TimeInterval, intent: Intent) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let step = min(deltaTime, 0.05)
        if intent.eyeState != previousEyeState {
            blinkElapsed = nil
            timeUntilBlink = nextInterval()
            previousEyeState = intent.eyeState
        }
        openness = Self.approach(openness, target: intent.eyeState == .uncoveredOpen ? 1 : 0, step: Float(step / 0.4))
        let strength = intent.expressionStrength.isFinite ? max(0, min(1, intent.expressionStrength)) : 0
        smile = Self.approach(smile, target: intent.expression == .gentleSmile ? strength : 0, step: Float(step / 0.3))
        curiosity = Self.approach(curiosity, target: intent.expression == .curious ? strength : 0, step: Float(step / 0.3))
        mouthOpen = Self.approach(mouthOpen, target: intent.mouthPose == .open ? 1 : 0, step: Float(step / 0.18))
        mouthRound = Self.approach(mouthRound, target: intent.mouthPose == .round ? 1 : 0, step: Float(step / 0.18))

        guard intent.eyeState == .uncoveredOpen, openness == 1 else {
            blinkElapsed = nil
            if intent.eyeState == .coveredClosed { queuedBlink = false }
            return
        }
        if let elapsed = blinkElapsed {
            blinkElapsed = elapsed + step
        } else if queuedBlink {
            queuedBlink = false
            blinkElapsed = step
        } else if intent.automaticBlink {
            timeUntilBlink -= step
            if timeUntilBlink <= 0 { blinkElapsed = -timeUntilBlink }
        }
        if let elapsed = blinkElapsed, elapsed >= 0.24 {
            blinkElapsed = nil
            timeUntilBlink = nextInterval()
        }
    }

    private mutating func nextInterval() -> TimeInterval {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return 3.2 + Double(randomState >> 11) / Double(UInt64.max >> 11) * 3
    }

    private static func blinkWeight(at elapsed: TimeInterval?) -> Float {
        guard let elapsed else { return 0 }
        if elapsed < 0.07 { return smooth(Float(elapsed / 0.07)) }
        if elapsed < 0.11 { return 1 }
        return 1 - smooth(Float((elapsed - 0.11) / 0.13))
    }

    private static func approach(_ value: Float, target: Float, step: Float) -> Float {
        value < target ? min(target, value + step) : max(target, value - step)
    }

    private static func smooth(_ value: Float) -> Float {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }
}

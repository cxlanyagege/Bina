import Foundation

/// Tracks preview intent and animation time independently of the rendering API.
nonisolated struct CharacterIdlePlayback {
    enum Mode: Equatable { case playing, paused, reference }

    static let cycleDuration: TimeInterval = 11
    static let transitionDuration: TimeInterval = 0.9

    private(set) var mode = Mode.playing
    private(set) var cycleTime: TimeInterval = 0
    private var transitionTime = CharacterIdlePlayback.transitionDuration

    var naturalPoseWeight: Float {
        guard mode != .reference else { return 0 }
        let progress = transitionTime / Self.transitionDuration
        return Float(progress * progress * (3 - 2 * progress))
    }

    var breath: Float {
        Float(0.5 - 0.5 * cos(4 * .pi * cycleTime / Self.cycleDuration))
    }

    var sway: Float {
        Float(sin(2 * .pi * cycleTime / Self.cycleDuration))
    }

    /// Hidden or paused previews retain their phase; delayed frames cannot fast-forward the pose.
    @discardableResult
    mutating func advance(by deltaTime: TimeInterval, isVisible: Bool) -> Bool {
        guard mode == .playing, isVisible, deltaTime.isFinite, deltaTime > 0 else { return false }
        let previousCycleTime = cycleTime
        let previousTransitionTime = transitionTime
        let step = min(deltaTime, 0.1)
        cycleTime = (cycleTime + step).truncatingRemainder(dividingBy: Self.cycleDuration)
        transitionTime = min(transitionTime + step, Self.transitionDuration)
        return cycleTime != previousCycleTime || transitionTime != previousTransitionTime
    }

    mutating func pause() {
        guard mode == .playing else { return }
        mode = .paused
    }

    mutating func resume() {
        guard mode == .paused else { return }
        mode = .playing
    }

    mutating func showReference() {
        mode = .reference
        cycleTime = 0
        transitionTime = 0
    }

    mutating func showNatural() {
        mode = .playing
        cycleTime = 0
        transitionTime = 0
    }
}

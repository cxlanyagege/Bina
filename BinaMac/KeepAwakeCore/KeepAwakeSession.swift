import Observation

/// Owns the two-state keep-awake session independently of system UI and persistence.
@MainActor
@Observable
public final class KeepAwakeSession {
    public private(set) var isActive = false

    private let assertion: any IdleSleepPreventing
    private let didChange: () -> Void

    public init(assertion: any IdleSleepPreventing, didChange: @escaping () -> Void = {}) {
        self.assertion = assertion
        self.didChange = didChange
    }

    /// Applies the requested state only after the corresponding system operation succeeds.
    public func setEnabled(_ enabled: Bool) throws {
        guard enabled != isActive else { return }

        if enabled {
            try assertion.acquire()
        } else {
            try assertion.release()
        }

        isActive = enabled
        didChange()
    }
}

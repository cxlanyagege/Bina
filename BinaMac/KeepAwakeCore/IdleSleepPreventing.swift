/// Owns a single assertion that prevents idle sleep for the display or system.
@MainActor
public protocol IdleSleepPreventing: AnyObject {
    /// Leaves the existing assertion unchanged if acquisition fails.
    func acquire() throws

    /// Releases the assertion, retaining ownership if the operation fails.
    func release() throws
}

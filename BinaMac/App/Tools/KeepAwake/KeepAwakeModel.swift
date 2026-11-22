import Foundation
import KeepAwakeCore
import OSLog
import Observation

@MainActor
@Observable
final class KeepAwakeModel {
    private let displaySession: KeepAwakeSession
    private let systemSession: KeepAwakeSession
    var errorMessage: String?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bina", category: "KeepAwake")

    init(displaySession: KeepAwakeSession, systemSession: KeepAwakeSession) {
        self.displaySession = displaySession
        self.systemSession = systemSession
    }

    var keepsDisplayAwake: Bool {
        get { displaySession.isActive }
        set { setProtection(in: displaySession, enabled: newValue) }
    }

    // This reflects Bina's system assertion. macOS and other apps can also affect idle sleep.
    var keepsSystemAwake: Bool {
        get { systemSession.isActive }
        set { setProtection(in: systemSession, enabled: newValue) }
    }

    func shutdown() {
        // Process exit also removes assertions if explicit cleanup fails.
        keepsDisplayAwake = false
        keepsSystemAwake = false
    }

    private func setProtection(in session: KeepAwakeSession, enabled: Bool) {
        do {
            try session.setEnabled(enabled)
            errorMessage = nil
        } catch {
            logger.error("Keep-awake operation failed: \(String(reflecting: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

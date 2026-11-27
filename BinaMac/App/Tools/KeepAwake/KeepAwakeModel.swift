import Foundation
import KeepAwakeCore
import OSLog
import Observation

@MainActor
@Observable
final class KeepAwakeModel {
    private let displaySession: KeepAwakeSession
    private let systemSession: KeepAwakeSession
    private let refreshRateSession: DisplayRefreshRateSession
    var errorMessage: String?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bina", category: "KeepAwake")

    init(
        displaySession: KeepAwakeSession,
        systemSession: KeepAwakeSession,
        refreshRateSession: DisplayRefreshRateSession = DisplayRefreshRateSession()
    ) {
        self.displaySession = displaySession
        self.systemSession = systemSession
        self.refreshRateSession = refreshRateSession
    }

    var keepsDisplayAwake: Bool {
        get { displaySession.isActive }
        set { apply { try displaySession.setEnabled(newValue) } }
    }

    // This reflects Bina's system assertion. macOS and other apps can also affect idle sleep.
    var keepsSystemAwake: Bool {
        get { systemSession.isActive }
        set { apply { try systemSession.setEnabled(newValue) } }
    }

    var slowsRefreshRate: Bool {
        get { refreshRateSession.isActive }
        set { apply { try refreshRateSession.setEnabled(newValue) } }
    }

    func shutdown() {
        // Process exit also removes assertions if explicit cleanup fails.
        keepsDisplayAwake = false
        keepsSystemAwake = false
        slowsRefreshRate = false
    }

    private func apply(_ change: () throws -> Void) {
        do {
            try change()
            errorMessage = nil
        } catch {
            logger.error("Keep-awake operation failed: \(String(reflecting: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

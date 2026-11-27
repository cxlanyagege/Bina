import Foundation
import Observation

struct DisplayModeFormat: Equatable {
    let logicalSize: CGSize
    let pixelSize: CGSize
    let pixelEncoding: String?
    let flags: UInt32
}

protocol RefreshRateDisplayMode {
    var ioDisplayModeID: Int32 { get }
    var refreshRate: Double { get }
    var format: DisplayModeFormat { get }

    func isUsableForDesktopGUI() -> Bool
}

@MainActor
protocol RefreshRateDisplay {
    associatedtype Mode: RefreshRateDisplayMode

    var currentMode: Mode? { get }
    var availableModes: [Mode] { get }

    func setMode(_ mode: Mode) throws
}

/// Owns a temporary refresh-rate override for the display selected at activation.
@MainActor
@Observable
final class DisplayRefreshRateSession {
    private let mainDisplay: @MainActor () -> (any RefreshRateDisplay)?
    private var restore: (@MainActor () throws -> Void)?

    init(mainDisplay: @escaping @MainActor () -> (any RefreshRateDisplay)? = CoreGraphicsRefreshRateDisplay.main) {
        self.mainDisplay = mainDisplay
    }

    var isActive: Bool { restore != nil }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled != isActive else { return }

        if enabled {
            guard let display = mainDisplay() else { throw DisplayRefreshRateError.displayUnavailable }
            restore = try limitRefreshRate(on: display)
        } else {
            try restore?()
            restore = nil
        }
    }

    private func limitRefreshRate(on display: some RefreshRateDisplay) throws -> @MainActor () throws -> Void {
        guard let original = display.currentMode else { throw DisplayRefreshRateError.displayUnavailable }
        guard original.refreshRate != 60 else { return {} }

        let format = original.format
        guard
            let target = display.availableModes.first(where: {
                $0.refreshRate == 60 && $0.isUsableForDesktopGUI() && $0.format == format
            })
        else {
            throw DisplayRefreshRateError.matchingModeUnavailable
        }

        try display.setMode(target)
        return {
            guard let current = display.currentMode else { throw DisplayRefreshRateError.restoreDisplayUnavailable }

            // A mode selected outside Bina takes precedence over this temporary override.
            guard current.ioDisplayModeID == target.ioDisplayModeID,
                current.refreshRate == target.refreshRate, current.format == format
            else { return }

            try display.setMode(original)
        }
    }
}

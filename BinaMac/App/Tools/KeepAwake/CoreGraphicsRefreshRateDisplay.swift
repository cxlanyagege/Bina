import ColorSync
import CoreGraphics
import Foundation
import IOKit.graphics

enum DisplayRefreshRateError: LocalizedError {
    case displayUnavailable
    case matchingModeUnavailable
    case mirroredDisplay
    case restoreDisplayUnavailable
    case configurationFailed(CGError, cancellation: CGError? = nil)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            "暂时无法读取主显示器设置，请重试。"
        case .matchingModeUnavailable:
            "主显示器在当前显示设置下没有可用的 60 Hz 模式。"
        case .mirroredDisplay:
            "镜像显示期间无法单独切换主显示器的刷新率。请结束镜像后重试。"
        case .restoreDisplayUnavailable:
            "暂时无法访问开启时的主显示器。请重新连接后关闭「缓慢刷新」。"
        case .configurationFailed:
            "macOS 无法切换显示器的刷新率，请重试。"
        }
    }
}

extension CGDisplayMode: RefreshRateDisplayMode {
    var format: DisplayModeFormat {
        DisplayModeFormat(
            logicalSize: CGSize(width: width, height: height),
            pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
            // Core Graphics exposes the mode's pixel format through this legacy property.
            pixelEncoding: pixelEncoding as String?,
            // Safety flags include the default-mode marker, which can vary with refresh rate.
            flags: ioFlags & ~UInt32(kDisplayModeSafetyFlags)
        )
    }
}

@MainActor
struct CoreGraphicsRefreshRateDisplay: RefreshRateDisplay {
    private let uuid: CFUUID

    static func main() -> CoreGraphicsRefreshRateDisplay? {
        let displayID = CGMainDisplayID()
        guard displayID != 0, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return Self(uuid: uuid)
    }

    private var onlineID: CGDirectDisplayID? {
        let displayID = CGDisplayGetDisplayIDFromUUID(uuid)
        return displayID != 0 && CGDisplayIsOnline(displayID) != 0 ? displayID : nil
    }

    var currentMode: CGDisplayMode? {
        guard let displayID = onlineID else { return nil }
        return CGDisplayCopyDisplayMode(displayID)
    }

    var availableModes: [CGDisplayMode] {
        guard let displayID = onlineID else { return [] }
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] ?? []
    }

    func setMode(_ mode: CGDisplayMode) throws {
        guard let displayID = onlineID else { throw DisplayRefreshRateError.displayUnavailable }
        guard CGDisplayIsInMirrorSet(displayID) == 0 else { throw DisplayRefreshRateError.mirroredDisplay }

        var configuration: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&configuration)
        guard begin == .success else { throw DisplayRefreshRateError.configurationFailed(begin) }

        let update = CGConfigureDisplayWithDisplayMode(configuration, displayID, mode, nil)
        guard update == .success else {
            let cancellation = CGCancelDisplayConfiguration(configuration)
            throw DisplayRefreshRateError.configurationFailed(update, cancellation: cancellation)
        }

        // The app-only scope lets macOS clean up the override if Bina exits unexpectedly.
        let commit = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard commit == .success else { throw DisplayRefreshRateError.configurationFailed(commit) }
    }
}

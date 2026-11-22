import AppIntents
import Foundation
import KeepAwakeCore

/// Identifiers shared by the containing app and its control extension.
enum KeepAwakeControlConfiguration {
    static let kind = "cxlanyagege.Bina.Mac.KeepAwake"
    static let sessionDependencyKey = "bina.mac.keepAwakeSession"
}

struct SetKeepAwakeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "设置保持常亮"
    static let description = IntentDescription("开启时保持屏幕常亮，关闭时按系统设置熄屏。")
    static let supportedModes: IntentModes = .foreground(.dynamic)
    static let isDiscoverable = false

    @Parameter(title: "保持常亮")
    var value: Bool

    @AppDependency(key: KeepAwakeControlConfiguration.sessionDependencyKey)
    private var session: KeepAwakeSession

    @MainActor
    func perform() async throws -> some IntentResult {
        // An extension must not own a long-lived assertion: its process may be reclaimed.
        guard Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else {
            throw KeepAwakeIntentError.hostAppRequired
        }
        try session.setEnabled(value)
        return .result()
    }
}

enum KeepAwakeIntentError: LocalizedError {
    case hostAppRequired

    var errorDescription: String? {
        "请先打开 Bina，再切换保持常亮。"
    }
}

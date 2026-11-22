import Foundation
import IOKit.pwr_mgt
import KeepAwakeCore
import OSLog

/// An IOKit failure with the target and operation needed to diagnose it.
public struct IdleSleepAssertionError: LocalizedError {
    public enum Operation: String, Sendable {
        case acquire
        case release
        case inspect
    }

    public let target: IdleSleepAssertion.Target
    public let operation: Operation
    public let code: IOReturn

    public init(target: IdleSleepAssertion.Target, operation: Operation, code: IOReturn) {
        self.target = target
        self.operation = operation
        self.code = code
    }

    public var errorDescription: String? {
        switch (target, operation) {
        case (.display, .acquire): "无法开启「保持常亮」，请重试。"
        case (.display, .release): "无法关闭「保持常亮」，请重试或退出 Bina。"
        case (.system, .acquire): "无法开启「不要入眠」，请重试。"
        case (.system, .release): "无法关闭「不要入眠」，请重试或退出 Bina。"
        case (_, .inspect): "暂时无法读取电源状态，请重试。"
        }
    }
}

/// Owns one idle sleep assertion for the lifetime of an app session.
@MainActor
public final class IdleSleepAssertion: IdleSleepPreventing {
    /// A display assertion also blocks idle system sleep. A system assertion allows the display to sleep.
    public enum Target: Sendable {
        case display
        case system

        var type: String {
            switch self {
            case .display: kIOPMAssertPreventUserIdleDisplaySleep
            case .system: kIOPMAssertPreventUserIdleSystemSleep
            }
        }

        var name: String {
            switch self {
            case .display: "cxlanyagege.Bina.Mac: keeping the display awake"
            case .system: "cxlanyagege.Bina.Mac: preventing idle system sleep"
            }
        }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bina", category: "Power")
    private let target: Target
    private var assertionID: IOPMAssertionID?

    public init(target: Target) {
        self.target = target
    }

    isolated deinit {
        do {
            try release()
        } catch {
            Self.logger.error("Idle sleep assertion cleanup failed: \(String(reflecting: error), privacy: .public)")
        }
    }

    public func acquire() throws {
        guard assertionID == nil else { return }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            target.type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            target.name as CFString,
            &newID
        )

        guard result == kIOReturnSuccess else {
            throw IdleSleepAssertionError(target: target, operation: .acquire, code: result)
        }
        assertionID = newID
    }

    public func release() throws {
        guard let assertionID else { return }
        let result = IOPMAssertionRelease(assertionID)
        guard result == kIOReturnSuccess else {
            throw IdleSleepAssertionError(target: target, operation: .release, code: result)
        }
        self.assertionID = nil
    }
}

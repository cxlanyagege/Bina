import Foundation
import IOKit.pwr_mgt
import KeepAwakePower
import Testing

@Suite("Live idle sleep assertions", .serialized)
@MainActor
struct IdleSleepAssertionTests {
    @Test(arguments: [IdleSleepAssertion.Target.display, .system])
    func acquiresOneAssertionOfTheRequestedType(_ target: IdleSleepAssertion.Target) throws {
        let assertion = IdleSleepAssertion(target: target)
        defer {
            do {
                try assertion.release()
            } catch {
                Issue.record(error, "Failed to clean up the test assertion.")
            }
        }

        let processID = ProcessInfo.processInfo.processIdentifier
        let initialCount = try assertionCount(for: target)
        let otherTarget: IdleSleepAssertion.Target = target == .display ? .system : .display
        let otherCount = try assertionCount(for: otherTarget)
        #expect(try !IdleSleepAssertionStatus.isEnabled(for: target, processID: processID))

        try assertion.acquire()
        #expect(try assertionCount(for: target) == initialCount + 1)
        #expect(try assertionCount(for: otherTarget) == otherCount)
        #expect(try IdleSleepAssertionStatus.isEnabled(for: target, processID: processID))

        try assertion.acquire()
        #expect(try assertionCount(for: target) == initialCount + 1)

        try assertion.release()
        #expect(try assertionCount(for: target) == initialCount)
        #expect(try !IdleSleepAssertionStatus.isEnabled(for: target, processID: processID))

        try assertion.release()
        #expect(try assertionCount(for: target) == initialCount)
    }

    @Test(arguments: [IdleSleepAssertion.Target.display, .system])
    func deallocatingTheOwnerReleasesItsAssertion(_ target: IdleSleepAssertion.Target) throws {
        let initialCount = try assertionCount(for: target)

        do {
            let assertion = IdleSleepAssertion(target: target)
            try assertion.acquire()
            let countWhileOwned = try withExtendedLifetime(assertion) {
                try assertionCount(for: target)
            }
            #expect(countWhileOwned == initialCount + 1)
        }

        #expect(try assertionCount(for: target) == initialCount)
    }

    private func assertionCount(for target: IdleSleepAssertion.Target) throws -> Int {
        var assertions: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertions)
        guard result == kIOReturnSuccess else {
            throw IdleSleepAssertionError(target: target, operation: .inspect, code: result)
        }
        let dictionary = try #require(assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]])
        let processID = NSNumber(value: ProcessInfo.processInfo.processIdentifier)
        let expectedType =
            switch target {
            case .display: kIOPMAssertPreventUserIdleDisplaySleep
            case .system: kIOPMAssertPreventUserIdleSystemSleep
            }
        return (dictionary[processID] ?? []).filter {
            $0[kIOPMAssertionTypeKey] as? String == expectedType
                && $0[kIOPMAssertionLevelKey] as? Int == kIOPMAssertionLevelOn
        }.count
    }
}

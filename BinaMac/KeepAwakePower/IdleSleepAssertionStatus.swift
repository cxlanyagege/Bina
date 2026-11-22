import Foundation
import IOKit.pwr_mgt

/// Reads Bina's live assertions so the observed state follows their process lifetime.
public enum IdleSleepAssertionStatus {
    public static func isEnabled(for target: IdleSleepAssertion.Target, processID: Int32? = nil) throws -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertions)
        guard result == kIOReturnSuccess else {
            throw IdleSleepAssertionError(target: target, operation: .inspect, code: result)
        }
        guard let dictionary = assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            throw IdleSleepAssertionError(target: target, operation: .inspect, code: kIOReturnError)
        }

        let name = target.name
        let type = target.type
        return dictionary.contains { pid, records in
            guard processID == nil || pid.int32Value == processID else { return false }
            return records.contains {
                $0[kIOPMAssertionNameKey] as? String == name
                    && $0[kIOPMAssertionTypeKey] as? String == type
                    && $0[kIOPMAssertionLevelKey] as? Int == kIOPMAssertionLevelOn
            }
        }
    }
}

import Testing

@testable import KeepAwakeCore

@MainActor
private final class FakeAssertion: IdleSleepPreventing {
    enum Failure: Error { case requested }

    var acquisitionCount = 0
    var releaseCount = 0
    var failAcquisition = false
    var failRelease = false

    func acquire() throws {
        if failAcquisition { throw Failure.requested }
        acquisitionCount += 1
    }

    func release() throws {
        if failRelease { throw Failure.requested }
        releaseCount += 1
    }
}

@Suite("Two-state keep-awake sessions")
@MainActor
struct KeepAwakeSessionTests {
    @Test func startsFollowingSystemSettings() {
        let assertion = FakeAssertion()
        let session = KeepAwakeSession(assertion: assertion)
        #expect(!session.isActive)
        #expect(assertion.acquisitionCount == 0)
    }

    @Test func repeatedEnableDoesNotDuplicateTheAssertion() throws {
        let assertion = FakeAssertion()
        var changes = 0
        let session = KeepAwakeSession(assertion: assertion) { changes += 1 }
        try session.setEnabled(true)
        try session.setEnabled(true)
        #expect(session.isActive)
        #expect(assertion.acquisitionCount == 1)
        #expect(changes == 1)
    }

    @Test func disablingRestoresSystemBehaviorAndAllowsRestart() throws {
        let assertion = FakeAssertion()
        var changes = 0
        let session = KeepAwakeSession(assertion: assertion) { changes += 1 }
        try session.setEnabled(true)
        try session.setEnabled(false)
        try session.setEnabled(false)
        #expect(!session.isActive)
        #expect(assertion.releaseCount == 1)
        #expect(changes == 2)

        try session.setEnabled(true)
        #expect(session.isActive)
        #expect(assertion.acquisitionCount == 2)
    }

    @Test func acquisitionFailureDoesNotPublishAnEnabledState() {
        let assertion = FakeAssertion()
        assertion.failAcquisition = true
        var changes = 0
        let session = KeepAwakeSession(assertion: assertion) { changes += 1 }
        #expect(throws: FakeAssertion.Failure.self) {
            try session.setEnabled(true)
        }
        #expect(!session.isActive)
        #expect(changes == 0)
    }

    @Test func releaseFailureRetainsTheEnabledStateForRetry() throws {
        let assertion = FakeAssertion()
        var changes = 0
        let session = KeepAwakeSession(assertion: assertion) { changes += 1 }
        try session.setEnabled(true)
        assertion.failRelease = true
        #expect(throws: FakeAssertion.Failure.self) {
            try session.setEnabled(false)
        }
        #expect(session.isActive)
        #expect(changes == 1)

        assertion.failRelease = false
        try session.setEnabled(false)
        #expect(!session.isActive)
        #expect(changes == 2)
    }
}

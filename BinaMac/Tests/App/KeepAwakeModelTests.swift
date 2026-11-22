import KeepAwakeCore
import Observation
import Testing

@testable import BinaMac

@MainActor
private final class RetriableAssertion: IdleSleepPreventing {
    enum Failure: Error { case acquire, release }

    var failAcquire = false
    var failRelease = false
    var acquisitionCount = 0
    var releaseCount = 0

    func acquire() throws {
        if failAcquire { throw Failure.acquire }
        acquisitionCount += 1
    }

    func release() throws {
        if failRelease {
            throw Failure.release
        }
        releaseCount += 1
    }
}

@Suite("Keep-awake presentation")
@MainActor
struct KeepAwakeModelTests {
    @Test func retryClearsTheErrorAfterSuccessfulRelease() {
        let assertion = RetriableAssertion()
        let model = makeModel(display: assertion)
        model.keepsDisplayAwake = true
        assertion.failRelease = true
        model.keepsDisplayAwake = false
        #expect(model.errorMessage != nil)
        #expect(model.keepsDisplayAwake)

        assertion.failRelease = false
        model.keepsDisplayAwake = false
        #expect(model.errorMessage == nil)
        #expect(!model.keepsDisplayAwake)
    }

    @Test func displayAndSystemSleepCanBeControlledIndependently() {
        let display = RetriableAssertion()
        let system = RetriableAssertion()
        let model = makeModel(display: display, system: system)

        #expect(!model.keepsDisplayAwake)
        #expect(!model.keepsSystemAwake)
        #expect(display.acquisitionCount == 0)
        #expect(system.acquisitionCount == 0)

        model.keepsSystemAwake = true
        #expect(model.keepsSystemAwake)
        #expect(!model.keepsDisplayAwake)
        #expect(system.acquisitionCount == 1)
        #expect(display.acquisitionCount == 0)

        model.keepsDisplayAwake = true
        model.keepsDisplayAwake = false
        #expect(model.keepsSystemAwake)
        #expect(system.releaseCount == 0)

        model.keepsDisplayAwake = true
        model.keepsSystemAwake = false
        #expect(!model.keepsSystemAwake)
        #expect(model.keepsDisplayAwake)
        #expect(system.releaseCount == 1)
        #expect(display.releaseCount == 1)
    }

    @Test func systemSleepProtectionRetainsItsPreviousSettingOnFailure() {
        let system = RetriableAssertion()
        let model = makeModel(system: system)
        system.failAcquire = true
        model.keepsSystemAwake = true
        #expect(!model.keepsSystemAwake)
        #expect(model.errorMessage != nil)

        system.failAcquire = false
        model.keepsSystemAwake = true
        #expect(model.keepsSystemAwake)
        #expect(model.errorMessage == nil)

        system.failRelease = true
        model.keepsSystemAwake = false
        #expect(model.keepsSystemAwake)
        #expect(model.errorMessage != nil)

        system.failRelease = false
        model.keepsSystemAwake = false
        #expect(!model.keepsSystemAwake)
        #expect(model.errorMessage == nil)
    }

    @Test func shutdownReleasesBothSessions() {
        let display = RetriableAssertion()
        let system = RetriableAssertion()
        let model = makeModel(display: display, system: system)
        model.keepsDisplayAwake = true
        model.keepsSystemAwake = true
        model.shutdown()
        #expect(!model.keepsDisplayAwake)
        #expect(!model.keepsSystemAwake)
        #expect(display.releaseCount == 1)
        #expect(system.releaseCount == 1)
    }

    @Test func shutdownReleasesSystemProtectionEvenIfDisplayReleaseFails() {
        let display = RetriableAssertion()
        let system = RetriableAssertion()
        let model = makeModel(display: display, system: system)
        model.keepsDisplayAwake = true
        model.keepsSystemAwake = true
        display.failRelease = true

        model.shutdown()

        #expect(model.keepsDisplayAwake)
        #expect(!model.keepsSystemAwake)
        #expect(system.releaseCount == 1)
    }

    @Test func observesChangesMadeThroughTheSharedSession() async throws {
        let session = KeepAwakeSession(assertion: RetriableAssertion())
        let model = KeepAwakeModel(
            displaySession: session,
            systemSession: KeepAwakeSession(assertion: RetriableAssertion())
        )

        try await confirmation("A session change invalidates the displayed state") { changed in
            let initialState = withObservationTracking {
                model.keepsDisplayAwake
            } onChange: {
                changed()
            }
            #expect(!initialState)

            try session.setEnabled(true)
            #expect(model.keepsDisplayAwake)
        }
    }

    private func makeModel(
        display: RetriableAssertion = RetriableAssertion(),
        system: RetriableAssertion = RetriableAssertion()
    ) -> KeepAwakeModel {
        KeepAwakeModel(
            displaySession: KeepAwakeSession(assertion: display),
            systemSession: KeepAwakeSession(assertion: system)
        )
    }
}

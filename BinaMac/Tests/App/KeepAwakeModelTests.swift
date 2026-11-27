import Foundation
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

private struct TestDisplayMode: RefreshRateDisplayMode {
    let ioDisplayModeID: Int32
    let refreshRate: Double
    let format: DisplayModeFormat
    var usable = true

    func isUsableForDesktopGUI() -> Bool { usable }
}

@MainActor
private final class TestRefreshRateDisplay: RefreshRateDisplay {
    enum Failure: Error { case setMode }

    static let format = DisplayModeFormat(
        logicalSize: CGSize(width: 1512, height: 982),
        pixelSize: CGSize(width: 3024, height: 1964),
        pixelEncoding: "RGB",
        flags: 0
    )
    static let adaptive = TestDisplayMode(ioDisplayModeID: 1, refreshRate: 0, format: format)
    static let fixed = TestDisplayMode(ioDisplayModeID: 2, refreshRate: 60, format: format)

    var currentMode: TestDisplayMode? = TestRefreshRateDisplay.adaptive
    var availableModes = [TestRefreshRateDisplay.adaptive, TestRefreshRateDisplay.fixed]
    var failSetMode = false
    private(set) var appliedModeIDs: [Int32] = []

    func setMode(_ mode: TestDisplayMode) throws {
        if failSetMode { throw Failure.setMode }
        appliedModeIDs.append(mode.ioDisplayModeID)
        currentMode = mode
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

    @Test func shutdownReleasesSleepAssertionsAndRestoresRefreshRate() {
        let display = RetriableAssertion()
        let system = RetriableAssertion()
        let refreshDisplay = TestRefreshRateDisplay()
        let model = makeModel(display: display, system: system, refreshDisplay: refreshDisplay)
        model.keepsDisplayAwake = true
        model.keepsSystemAwake = true
        model.slowsRefreshRate = true
        model.shutdown()
        #expect(!model.keepsDisplayAwake)
        #expect(!model.keepsSystemAwake)
        #expect(!model.slowsRefreshRate)
        #expect(display.releaseCount == 1)
        #expect(system.releaseCount == 1)
        #expect(
            refreshDisplay.appliedModeIDs == [
                TestRefreshRateDisplay.fixed.ioDisplayModeID, TestRefreshRateDisplay.adaptive.ioDisplayModeID,
            ])
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

    @Test func slowRefreshOnlyUses60HzAtTheCurrentDisplayFormat() {
        let display = TestRefreshRateDisplay()
        let scaledFormat = DisplayModeFormat(
            logicalSize: TestRefreshRateDisplay.format.logicalSize,
            pixelSize: TestRefreshRateDisplay.format.logicalSize,
            pixelEncoding: TestRefreshRateDisplay.format.pixelEncoding,
            flags: TestRefreshRateDisplay.format.flags
        )
        display.availableModes = [
            TestDisplayMode(ioDisplayModeID: 3, refreshRate: 60, format: scaledFormat),
            TestDisplayMode(ioDisplayModeID: 4, refreshRate: 59.94, format: TestRefreshRateDisplay.format),
            TestDisplayMode(ioDisplayModeID: 5, refreshRate: 60, format: TestRefreshRateDisplay.format, usable: false),
        ]
        let model = makeModel(refreshDisplay: display)
        #expect(!model.slowsRefreshRate)

        model.slowsRefreshRate = true
        #expect(model.errorMessage != nil)
        #expect(!model.slowsRefreshRate)
        #expect(display.appliedModeIDs.isEmpty)

        display.availableModes.append(TestRefreshRateDisplay.fixed)
        model.slowsRefreshRate = true
        #expect(model.errorMessage == nil)
        #expect(model.slowsRefreshRate)
        #expect(display.currentMode?.refreshRate == 60)
        #expect(display.currentMode?.format == TestRefreshRateDisplay.format)
        #expect(!model.keepsDisplayAwake)
        #expect(!model.keepsSystemAwake)

        model.slowsRefreshRate = false
        #expect(!model.slowsRefreshRate)
        #expect(display.currentMode?.ioDisplayModeID == TestRefreshRateDisplay.adaptive.ioDisplayModeID)
    }

    @Test func slowRefreshRetainsItsPreviousStateUntilTheModeChangeSucceeds() {
        let display = TestRefreshRateDisplay()
        let model = makeModel(refreshDisplay: display)
        display.failSetMode = true

        model.slowsRefreshRate = true
        #expect(!model.slowsRefreshRate)
        #expect(model.errorMessage != nil)

        display.failSetMode = false
        model.slowsRefreshRate = true
        #expect(model.slowsRefreshRate)

        display.failSetMode = true
        model.slowsRefreshRate = false
        #expect(model.slowsRefreshRate)
        #expect(model.errorMessage != nil)

        display.failSetMode = false
        model.slowsRefreshRate = false
        #expect(!model.slowsRefreshRate)
        #expect(model.errorMessage == nil)
        #expect(display.currentMode?.ioDisplayModeID == TestRefreshRateDisplay.adaptive.ioDisplayModeID)
    }

    @Test func slowRefreshLeavesAnExisting60HzModeAlone() {
        let display = TestRefreshRateDisplay()
        display.currentMode = TestRefreshRateDisplay.fixed
        let model = makeModel(refreshDisplay: display)
        model.slowsRefreshRate = true
        #expect(model.slowsRefreshRate)
        model.slowsRefreshRate = false
        #expect(display.appliedModeIDs.isEmpty)
    }

    @Test func slowRefreshCanRestoreTheModeAfterTheDisplayReconnects() {
        let display = TestRefreshRateDisplay()
        let model = makeModel(refreshDisplay: display)
        model.slowsRefreshRate = true

        display.currentMode = nil
        model.slowsRefreshRate = false
        #expect(model.slowsRefreshRate)
        #expect(model.errorMessage != nil)

        display.currentMode = TestRefreshRateDisplay.fixed
        model.slowsRefreshRate = false
        #expect(!model.slowsRefreshRate)
        #expect(model.errorMessage == nil)
        #expect(display.currentMode?.ioDisplayModeID == TestRefreshRateDisplay.adaptive.ioDisplayModeID)
    }

    @Test func slowRefreshPreservesASeparateDisplayModeChange() {
        let display = TestRefreshRateDisplay()
        let model = makeModel(refreshDisplay: display)
        model.slowsRefreshRate = true

        let manuallySelected = TestDisplayMode(
            ioDisplayModeID: 6, refreshRate: 50, format: TestRefreshRateDisplay.format)
        display.currentMode = manuallySelected
        model.slowsRefreshRate = false

        #expect(!model.slowsRefreshRate)
        #expect(display.currentMode?.ioDisplayModeID == manuallySelected.ioDisplayModeID)
        #expect(display.appliedModeIDs == [TestRefreshRateDisplay.fixed.ioDisplayModeID])
    }

    private func makeModel(
        display: RetriableAssertion = RetriableAssertion(),
        system: RetriableAssertion = RetriableAssertion(),
        refreshDisplay: TestRefreshRateDisplay = TestRefreshRateDisplay()
    ) -> KeepAwakeModel {
        KeepAwakeModel(
            displaySession: KeepAwakeSession(assertion: display),
            systemSession: KeepAwakeSession(assertion: system),
            refreshRateSession: DisplayRefreshRateSession(mainDisplay: { refreshDisplay })
        )
    }
}

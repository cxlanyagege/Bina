import Foundation
import Synchronization
import Testing

@testable import BinaMac

@MainActor
@Suite("Application management cache")
struct AppManagementModelTests {
    @Test func reusesTheCatalogAndResultsWithinTheCacheLifetime() async throws {
        let old = application("Example", version: "1.0")
        let current = application("Example", version: "1.1")
        let checkedVersions = Mutex([String]())
        let checks = ApplicationUpdateChecks { application in
            checkedVersions.withLock { $0.append(application.version.displayVersion ?? "unknown") }
            return Self.updateResult(for: application)
        }
        defer { checks.cancel() }

        var instant = ContinuousClock.now
        var scans = 0
        let model = AppManagementModel(
            updateChecks: checks, cacheLifetime: .seconds(60), now: { instant },
            loadCatalog: {
                scans += 1
                return InstalledApplicationCatalog(
                    applications: [scans == 1 ? old : current], hasUnreadableLocations: false)
            })

        await model.refreshIfNeeded()
        try await waitUntil { !checks.isChecking }
        #expect(scans == 1)
        #expect(model.catalog?.applications == [old])
        #expect(checks.results[old.id]?.installedVersion == old.version)

        instant = instant.advanced(by: .seconds(59))
        await model.refreshIfNeeded()
        #expect(scans == 1)
        #expect(checks.results[old.id]?.installedVersion == old.version)
        #expect(checkedVersions.withLock { $0 } == ["1.0"])

        instant = instant.advanced(by: .seconds(1))
        await model.refreshIfNeeded()
        try await waitUntil { !checks.isChecking }
        #expect(scans == 2)
        #expect(model.catalog?.applications == [current])
        #expect(checks.results[current.id]?.installedVersion == current.version)
        #expect(checkedVersions.withLock { $0 } == ["1.0", "1.1"])
    }

    @Test func sharesAScanAcrossEntriesAndKeepsAnUninstalledAppOutOfTheRefreshedCatalog() async throws {
        let removed = application("Removed", version: "1.0")
        let remaining = application("Remaining", version: "1.0")
        let checks = ApplicationUpdateChecks(checkApplication: Self.updateResult)
        let (scanGate, finishScan) = AsyncStream<Void>.makeStream()
        defer {
            finishScan.finish()
            checks.cancel()
        }

        var instant = ContinuousClock.now
        var scans = 0
        let model = AppManagementModel(
            updateChecks: checks, cacheLifetime: .seconds(1), now: { instant },
            loadCatalog: {
                scans += 1
                if scans > 1 {
                    var iterator = scanGate.makeAsyncIterator()
                    _ = await iterator.next()
                }
                return InstalledApplicationCatalog(applications: [removed, remaining], hasUnreadableLocations: false)
            })

        await model.refreshIfNeeded()
        try await waitUntil { !checks.isChecking }
        instant = instant.advanced(by: .seconds(1))
        let firstAppearance = Task { await model.refreshIfNeeded() }
        try await waitUntil { model.isRefreshing && scans == 2 }
        #expect(model.catalog?.applications == [removed, remaining])
        firstAppearance.cancel()

        let secondAppearance = Task { await model.refreshIfNeeded() }
        model.remove(removed)
        finishScan.finish()
        await firstAppearance.value
        await secondAppearance.value
        try await waitUntil { !checks.isChecking }

        #expect(scans == 2)
        #expect(model.catalog?.applications == [remaining])
        #expect(checks.results[removed.id] == nil)
        #expect(checks.results[remaining.id] != nil)
    }

    @Test func coalescesApplicationChangesAndRefreshesUpdateResultsBeforeExpiry() async throws {
        let old = application("Example", version: "1.0")
        let current = application("Example", version: "1.1")
        let removed = application("Removed", version: "1.0")
        let installed = application("New", version: "1.0")
        let checks = ApplicationUpdateChecks(checkApplication: Self.updateResult)
        defer { checks.cancel() }

        var scans = 0
        let model = AppManagementModel(
            updateChecks: checks, changeDebounce: .milliseconds(40),
            loadCatalog: {
                scans += 1
                return InstalledApplicationCatalog(
                    applications: scans == 1 ? [old, removed] : [current, installed], hasUnreadableLocations: false)
            })
        model.isPresented = true

        await model.refreshIfNeeded()
        try await waitUntil { !checks.isChecking }
        model.installedApplicationsDidChange()
        model.installedApplicationsDidChange()
        model.installedApplicationsDidChange()
        #expect(model.catalog?.applications == [old, removed])

        try await waitUntil { model.catalog?.applications == [current, installed] && !checks.isChecking }
        #expect(scans == 2)
        #expect(checks.results[current.id]?.installedVersion == current.version)
        #expect(checks.results[installed.id]?.installedVersion == installed.version)
        #expect(checks.results[removed.id] == nil)
        await model.refreshIfNeeded()
        #expect(scans == 2)
    }

    @Test func refreshesAnInvalidatedCacheWhenReturningToApplicationManagement() async throws {
        let checks = ApplicationUpdateChecks(checkApplication: Self.updateResult)
        defer { checks.cancel() }
        var scans = 0
        let model = AppManagementModel(
            updateChecks: checks, changeDebounce: .milliseconds(30),
            loadCatalog: {
                scans += 1
                return InstalledApplicationCatalog(applications: [], hasUnreadableLocations: false)
            })

        await model.refreshIfNeeded()
        model.installedApplicationsDidChange()
        try await Task.sleep(for: .milliseconds(80))
        #expect(scans == 1)

        model.isPresented = true
        await model.refreshIfNeeded()
        #expect(scans == 2)
    }

    @Test func keepsThePreviousListWhenAChangeInvalidatesAnInFlightScan() async throws {
        let old = application("Example", version: "1.0")
        let temporary = application("Example", version: "1.1")
        let current = application("Example", version: "1.2")
        let checks = ApplicationUpdateChecks(checkApplication: Self.updateResult)
        let (scanGate, finishScan) = AsyncStream<Void>.makeStream()
        defer {
            finishScan.finish()
            checks.cancel()
        }

        var scans = 0
        let model = AppManagementModel(
            updateChecks: checks, changeDebounce: .milliseconds(30),
            loadCatalog: {
                scans += 1
                let snapshot =
                    switch scans {
                    case 1: [old]
                    case 2: [temporary]
                    default: [current]
                    }
                if scans == 2 || scans == 3 {
                    var iterator = scanGate.makeAsyncIterator()
                    _ = await iterator.next()
                }
                return InstalledApplicationCatalog(applications: snapshot, hasUnreadableLocations: false)
            })
        model.isPresented = true

        await model.refreshIfNeeded()
        model.installedApplicationsDidChange()
        try await waitUntil { scans == 2 }
        model.installedApplicationsDidChange()
        finishScan.yield(())
        try await waitUntil { scans == 3 }
        #expect(model.catalog?.applications == [old])

        finishScan.finish()
        try await waitUntil { model.catalog?.applications == [current] && !checks.isChecking }
        #expect(checks.results[current.id]?.installedVersion == current.version)
        #expect(scans == 3)
    }

    private nonisolated static func updateResult(for application: InstalledApplication) -> ApplicationUpdateResult {
        let release = ApplicationVersion(shortVersion: "1.2", buildVersion: nil)
        return ApplicationUpdateResult(installedVersion: application.version, source: nil, outcome: .available(release))
    }

    private func application(_ name: String, version: String) -> InstalledApplication {
        InstalledApplication(
            url: URL(filePath: "/Applications/\(name).app"), name: name,
            version: ApplicationVersion(shortVersion: version, buildVersion: nil), bundleIdentifier: "test.\(name)")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while !condition() && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

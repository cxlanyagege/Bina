import Foundation
import Synchronization
import Testing

@testable import BinaMac

@MainActor
@Suite("Application update list")
struct ApplicationUpdateChecksTests {
    @Test func sharesSingleAndBatchResultsAndListsUpdatesAsTheyArrive() async throws {
        let firstCopy = application("First Copy")
        let secondCopy = application("Second Copy")
        let incompatible = application("Incompatible")
        let (slowCheck, finishSlowCheck) = AsyncStream<Void>.makeStream()
        let callCount = Mutex(0)
        let installed = ApplicationVersion(shortVersion: "1.0", buildVersion: "10")
        let available = ApplicationVersion(shortVersion: "1.1", buildVersion: "11")

        let checks = ApplicationUpdateChecks { application in
            switch application.id {
            case secondCopy.id:
                callCount.withLock { $0 += 1 }
                var iterator = slowCheck.makeAsyncIterator()
                _ = await iterator.next()
                return ApplicationUpdateResult(installedVersion: installed, source: nil, outcome: .available(available))
            case incompatible.id:
                return ApplicationUpdateResult(
                    installedVersion: installed, source: nil, outcome: .incompatible(available, .minimumMacOS("99")))
            default:
                return ApplicationUpdateResult(installedVersion: installed, source: nil, outcome: .available(available))
            }
        }
        defer {
            checks.cancel()
            finishSlowCheck.finish()
        }

        checks.check(secondCopy)
        let applications = [firstCopy, secondCopy, incompatible]
        checks.checkAll(applications)
        #expect(checks.isChecking)
        try await waitUntil { checks.results[incompatible.id] != nil && checks.results[firstCopy.id] != nil }
        let partialUpdates = checks.availableUpdates(for: applications)
        let update = try #require(partialUpdates.first)
        #expect(partialUpdates.map(\.id) == [firstCopy.id])
        #expect(update.installedVersion.displayVersion == "1.0")
        #expect(update.availableVersion.displayVersion == "1.1")
        #expect(checks.isChecking(secondCopy))

        finishSlowCheck.finish()
        try await waitUntil { !checks.isChecking }
        #expect(checks.availableUpdates(for: applications).map(\.id) == [firstCopy.id, secondCopy.id])
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test func limitsConcurrentChecksAndForgetsRemovedCopies() async throws {
        let applications = (0..<6).map { application("Copy \($0)") }
        let gates = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, AsyncStream<Void>.makeStream()) })
        let started = Mutex(Set<URL>())
        let installed = ApplicationVersion(shortVersion: "1.0", buildVersion: "10")
        let available = ApplicationVersion(shortVersion: "1.0", buildVersion: "11")
        let checks = ApplicationUpdateChecks { application in
            started.withLock { _ = $0.insert(application.id) }
            if let gate = gates[application.id] {
                var iterator = gate.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
            return ApplicationUpdateResult(installedVersion: installed, source: nil, outcome: .available(available))
        }
        defer {
            checks.cancel()
            for gate in gates.values { gate.continuation.finish() }
        }

        checks.checkAll(applications)
        try await waitUntil { started.withLock { $0.count } >= 4 }
        #expect(started.withLock { $0 } == Set(applications.prefix(4).map(\.id)))

        let runningCopy = applications[0]
        let pendingCopy = applications[5]
        checks.remove(pendingCopy)
        checks.remove(runningCopy)
        try await waitUntil { started.withLock { $0.contains(applications[4].id) } }
        for gate in gates.values { gate.continuation.finish() }
        try await waitUntil { !checks.isChecking }

        #expect(!started.withLock { $0.contains(pendingCopy.id) })
        #expect(checks.results[runningCopy.id] == nil)
        #expect(checks.availableUpdates(for: applications).map(\.id) == applications[1...4].map(\.id))
    }

    private func application(_ name: String) -> InstalledApplication {
        InstalledApplication(
            url: URL(filePath: "/Applications/\(name).app"), name: name,
            version: ApplicationVersion(shortVersion: "0.9", buildVersion: "9"), bundleIdentifier: "test.Bina.Updates")
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

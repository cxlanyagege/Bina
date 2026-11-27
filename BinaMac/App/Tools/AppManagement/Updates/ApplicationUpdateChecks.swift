import Foundation
import Observation

/// Runs update checks for individual copies and shares their results between the list and details.
@MainActor
@Observable
final class ApplicationUpdateChecks {
    struct AvailableUpdate: Identifiable {
        let application: InstalledApplication
        let installedVersion: ApplicationVersion
        let availableVersion: ApplicationVersion

        var id: URL { application.id }
    }

    private static let maximumConcurrentChecks = 4
    private typealias Check = @Sendable (InstalledApplication) async -> ApplicationUpdateResult

    private struct Request {
        let application: InstalledApplication
        let check: Check
    }

    private let makeCheck: () -> Check
    private var pending: ArraySlice<Request> = []
    private var running: [URL: Task<Void, Never>] = [:]
    private(set) var results: [URL: ApplicationUpdateResult] = [:]

    init() {
        makeCheck = { ApplicationUpdateChecker().check }
    }

    init(checkApplication: @escaping @Sendable (InstalledApplication) async -> ApplicationUpdateResult) {
        makeCheck = { checkApplication }
    }

    var isChecking: Bool { !running.isEmpty || !pending.isEmpty }

    func isChecking(_ application: InstalledApplication) -> Bool {
        running[application.id] != nil || pending.contains { $0.application.id == application.id }
    }

    func availableUpdates(for applications: [InstalledApplication]) -> [AvailableUpdate] {
        applications.compactMap { application in
            guard let result = results[application.id], let installedVersion = result.installedVersion,
                case .available(let availableVersion) = result.outcome
            else { return nil }
            return AvailableUpdate(
                application: application, installedVersion: installedVersion, availableVersion: availableVersion)
        }
    }

    func refresh(_ applications: [InstalledApplication]) {
        cancel()
        results.removeAll()
        checkAll(applications)
    }

    func checkAll(_ applications: [InstalledApplication]) {
        var queuedIDs = Set(running.keys).union(pending.map(\.application.id))
        let check = makeCheck()
        pending.append(
            contentsOf: applications.compactMap { application in
                queuedIDs.insert(application.id).inserted ? Request(application: application, check: check) : nil
            })
        startPendingChecks()
    }

    func check(_ application: InstalledApplication) {
        guard !isChecking(application) else { return }
        pending.append(Request(application: application, check: makeCheck()))
        startPendingChecks()
    }

    func remove(_ application: InstalledApplication) {
        pending.removeAll { $0.application.id == application.id }
        running.removeValue(forKey: application.id)?.cancel()
        results.removeValue(forKey: application.id)
        startPendingChecks()
    }

    func cancel() {
        pending.removeAll()
        for task in running.values { task.cancel() }
        running.removeAll()
    }

    private func startPendingChecks() {
        while running.count < Self.maximumConcurrentChecks, let request = pending.popFirst() {
            let application = request.application
            running[application.id] = Task { [weak self] in
                guard !Task.isCancelled else { return }
                let result = await request.check(application)
                // An uninstalled copy must not regain a result if its check finishes after cancellation.
                guard let self, !Task.isCancelled else { return }
                results[application.id] = result
                running.removeValue(forKey: application.id)
                startPendingChecks()
            }
        }
    }
}

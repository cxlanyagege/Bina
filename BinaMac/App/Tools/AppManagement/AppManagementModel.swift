import Foundation
import Observation

/// Keeps the installed app catalog and its update results for the lifetime of a window.
@MainActor
@Observable
final class AppManagementModel {
    let updateChecks: ApplicationUpdateChecks
    private(set) var catalog: InstalledApplicationCatalog?
    var isPresented = false
    private let cacheLifetime: Duration
    private let changeDebounce: Duration
    private let now: () -> ContinuousClock.Instant
    private let loadCatalog: @MainActor () async -> InstalledApplicationCatalog
    private var expiresAt: ContinuousClock.Instant?
    private var refreshTask: Task<Void, Never>?
    private var removedDuringRefresh: Set<URL> = []
    private var changeMonitor: InstalledApplicationChanges?
    private var changeRefreshTask: Task<Void, Never>?
    private var catalogRevision = 0

    init(
        updateChecks: ApplicationUpdateChecks = ApplicationUpdateChecks(),
        cacheLifetime: Duration = .seconds(15 * 60), changeDebounce: Duration = .seconds(1),
        now: @escaping () -> ContinuousClock.Instant = { .now },
        loadCatalog: @escaping @MainActor () async -> InstalledApplicationCatalog = InstalledApplicationCatalog.load
    ) {
        self.updateChecks = updateChecks
        self.cacheLifetime = cacheLifetime
        self.changeDebounce = changeDebounce
        self.now = now
        self.loadCatalog = loadCatalog
    }

    isolated deinit {
        changeRefreshTask?.cancel()
        refreshTask?.cancel()
    }

    var isRefreshing: Bool { refreshTask != nil }

    func startObservingChangesIfNeeded() {
        guard changeMonitor == nil else { return }
        changeMonitor = InstalledApplicationChanges { [weak self] in
            self?.installedApplicationsDidChange()
        }
    }

    func installedApplicationsDidChange() {
        catalogRevision &+= 1
        expiresAt = nil
        changeRefreshTask?.cancel()
        changeRefreshTask = Task { [weak self, changeDebounce] in
            do {
                try await Task.sleep(for: changeDebounce)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            changeRefreshTask = nil
            if isPresented { await refreshIfNeeded() }
        }
    }

    func refreshIfNeeded() async {
        if let refreshTask {
            await refreshTask.value
        }
        guard !Task.isCancelled, refreshTask == nil, changeRefreshTask == nil else { return }
        if let expiresAt, now() < expiresAt { return }

        // The window owns this task so another sidebar view can appear without interrupting the scan.
        let revision = catalogRevision
        let task = Task { [weak self, loadCatalog] in
            let scanned = await loadCatalog()
            guard let self else { return }
            defer {
                removedDuringRefresh.removeAll()
                refreshTask = nil
            }
            // An installer may change the disk while a scan is building its snapshot.
            guard revision == catalogRevision else { return }
            let applications = scanned.applications.filter { !removedDuringRefresh.contains($0.id) }
            catalog = InstalledApplicationCatalog(
                applications: applications, hasUnreadableLocations: scanned.hasUnreadableLocations)
            expiresAt = now().advanced(by: cacheLifetime)
            updateChecks.refresh(applications)
        }
        refreshTask = task
        await task.value
    }

    func remove(_ application: InstalledApplication) {
        if isRefreshing { removedDuringRefresh.insert(application.id) }
        updateChecks.remove(application)
        if let catalog {
            self.catalog = InstalledApplicationCatalog(
                applications: catalog.applications.filter { $0.id != application.id },
                hasUnreadableLocations: catalog.hasUnreadableLocations)
        }
    }
}

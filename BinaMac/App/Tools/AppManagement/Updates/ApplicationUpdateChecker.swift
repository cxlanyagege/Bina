import Foundation
import OSLog

/// Chooses the update source for the copy at the catalog URL using current local metadata.
struct ApplicationUpdateChecker: Sendable {
    private static let logger = Logger(subsystem: "BinaMac", category: "ApplicationUpdateCheck")
    private let homebrew: HomebrewUpdateCatalog
    private let appStore: AppStoreUpdateChecker
    private let sparkle: SparkleUpdateChecker
    private let published: PublishedApplicationUpdateChecker

    init(
        homebrew: HomebrewUpdateCatalog = HomebrewUpdateCatalog(),
        appStore: AppStoreUpdateChecker = AppStoreUpdateChecker(),
        sparkle: SparkleUpdateChecker = SparkleUpdateChecker(),
        published: PublishedApplicationUpdateChecker = PublishedApplicationUpdateChecker()
    ) {
        self.homebrew = homebrew
        self.appStore = appStore
        self.sparkle = sparkle
        self.published = published
    }

    @concurrent
    func check(_ application: InstalledApplication) async -> ApplicationUpdateResult {
        let unreadable = ApplicationUpdateResult(installedVersion: nil, source: nil, outcome: .unreadableApplication)
        let metadata: ApplicationBundleMetadata
        do {
            metadata = try ApplicationBundleMetadata(reading: application.url)
        } catch {
            Self.logger.error("Could not read the installed version: \(error.localizedDescription, privacy: .private)")
            return unreadable
        }
        guard metadata.bundleIdentifier == application.bundleIdentifier else { return unreadable }

        if let result = await appStore.checkIfInstalled(application.url, metadata: metadata) { return result }

        let inventory = await homebrew.snapshot()
        if let cask = inventory.casksByPath[application.url.resolvingSymlinksInPath().standardizedFileURL.path] {
            if cask.prefersSparkle && metadata.sparkleFeed != nil {
                let result = await sparkle.check(metadata)
                switch result.outcome {
                case .invalidFeedURL, .uncomparableVersion:
                    if cask.publishedVersion == nil { return result }
                default:
                    return result
                }
            }
            return cask.check(installedVersion: metadata.version)
        }

        if metadata.sparkleFeed != nil { return await sparkle.check(metadata) }
        if let result = await published.checkIfKnown(metadata) { return result }
        return ApplicationUpdateResult(
            installedVersion: metadata.version, source: nil,
            outcome: inventory.hadFailure ? .homebrewUnavailable : .noSource)
    }
}

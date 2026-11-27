import Foundation
import OSLog

/// Checks the default Sparkle feed declared by one installed app without running its updater.
struct SparkleUpdateChecker: Sendable {
    private static let logger = Logger(subsystem: "BinaMac", category: "SparkleUpdateCheck")
    private let fetch: @Sendable (URL) async throws -> Data

    init(fetch: @escaping @Sendable (URL) async throws -> Data = UpdateHTTPClient.fetch) {
        self.fetch = fetch
    }

    @concurrent
    func check(_ metadata: ApplicationBundleMetadata) async -> ApplicationUpdateResult {
        guard let feed = metadata.sparkleFeed else {
            return ApplicationUpdateResult(installedVersion: metadata.version, source: nil, outcome: .noSource)
        }
        let url = URL(string: feed)
        let source = ApplicationUpdateResult.Source.sparkle(host: url?.host())

        func result(_ outcome: ApplicationUpdateResult.Outcome) -> ApplicationUpdateResult {
            ApplicationUpdateResult(installedVersion: metadata.version, source: source, outcome: outcome)
        }

        guard let url, UpdateHTTPClient.isSecure(url) else { return result(.invalidFeedURL) }
        guard let build = metadata.version.buildVersion, let buildNumber = NumericApplicationVersion(build) else {
            return result(.uncomparableVersion)
        }

        let data: Data
        do {
            data = try await fetch(url)
        } catch {
            if !Task.isCancelled {
                Self.logger.error("Could not fetch the appcast: \(error.localizedDescription, privacy: .private)")
            }
            return result(.requestFailed)
        }

        do {
            let appcast = try SparkleAppcast(data: data, url: url, bundleIdentifier: metadata.bundleIdentifier)
            return result(
                appcast.evaluate(
                    installedBuild: build, buildNumber: buildNumber,
                    macOS: ProcessInfo.processInfo.operatingSystemVersion,
                    isAppleSilicon: ApplicationUpdatePlatform.isAppleSilicon))
        } catch {
            Self.logger.error("Could not read the appcast: \(error.localizedDescription, privacy: .private)")
            return result(.invalidAppcast)
        }
    }

}

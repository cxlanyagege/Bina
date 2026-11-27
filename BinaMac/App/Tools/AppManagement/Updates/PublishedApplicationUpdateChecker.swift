import Foundation
import OSLog

/// Checks curated direct-distribution releases after the installed update channels have been considered.
struct PublishedApplicationUpdateChecker: Sendable {
    private struct Repository: Sendable {
        let slug: String
        var matchInstalledMajor = false
        let packageName: @Sendable (_ version: String, _ isAppleSilicon: Bool) -> String
    }

    private struct VersionFeed: Sendable {
        let url: String
        let versionKey: String
    }

    private enum Entry: Sendable {
        case github(Repository)
        case website(page: String, feed: VersionFeed?)
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
        }

        let tag: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case draft, prerelease, assets
        }

        var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
    }

    // Each entry names a specific distribution variant and its official publication source.
    private static let entries: [String: Entry] = [
        "io.github.clash-verge-rev.clash-verge-rev": .github(
            Repository(slug: "clash-verge-rev/clash-verge-rev") { version, silicon in
                "Clash.Verge_\(version)_\(silicon ? "aarch64" : "x64").dmg"
            }),
        "com.electron.ollama": .github(
            Repository(slug: "ollama/ollama") { _, _ in "Ollama-darwin.zip" }),
        "ai.opencode.desktop": .github(
            Repository(slug: "anomalyco/opencode", matchInstalledMajor: true) { _, silicon in
                "opencode-desktop-mac-\(silicon ? "arm64" : "x64").dmg"
            }),
        "com.microsoft.VSCode": .website(
            page: "https://code.visualstudio.com/download",
            feed: VersionFeed(
                url: "https://update.code.visualstudio.com/api/update/darwin-universal/stable/latest",
                versionKey: "productVersion")),
        "com.anythingllm": .website(page: "https://anythingllm.com/download", feed: nil),
    ]

    private static let logger = Logger(subsystem: "BinaMac", category: "PublishedApplicationUpdate")
    private let isAppleSilicon: Bool
    private let fetch: @Sendable (URL) async throws -> Data

    init(
        isAppleSilicon: Bool = ApplicationUpdatePlatform.isAppleSilicon,
        fetch: @escaping @Sendable (URL) async throws -> Data = UpdateHTTPClient.fetch
    ) {
        self.isAppleSilicon = isAppleSilicon
        self.fetch = fetch
    }

    @concurrent
    func checkIfKnown(_ metadata: ApplicationBundleMetadata) async -> ApplicationUpdateResult? {
        guard let id = metadata.bundleIdentifier, let entry = Self.entries[id] else { return nil }
        let installed = metadata.version
        switch entry {
        case .github(let repository):
            guard let url = URL(string: "https://github.com/\(repository.slug)/releases") else { return nil }
            return await check(installed, source: .github(repository: repository.slug, releasesURL: url)) {
                try await latestGitHubVersion(repository, installed: installed)
            }
        case .website(let page, let feed):
            guard let url = URL(string: page) else { return nil }
            let source = ApplicationUpdateResult.Source.website(downloadPage: url)
            guard let feed else {
                return ApplicationUpdateResult(installedVersion: installed, source: source, outcome: .manualCheck)
            }
            return await check(installed, source: source) { try await latestWebsiteVersion(feed) }
        }
    }

    private func check(
        _ installed: ApplicationVersion, source: ApplicationUpdateResult.Source,
        latest: () async throws -> String?
    ) async -> ApplicationUpdateResult {
        func result(_ outcome: ApplicationUpdateResult.Outcome) -> ApplicationUpdateResult {
            ApplicationUpdateResult(installedVersion: installed, source: source, outcome: outcome)
        }

        guard let current = installed.shortVersion, let installedNumber = NumericApplicationVersion(current) else {
            return result(.uncomparableVersion)
        }
        do {
            guard let version = try await latest() else { return result(.noMatchingRelease) }
            guard let offered = NumericApplicationVersion(version) else { return result(.uncomparableVersion) }
            let release = ApplicationVersion(shortVersion: version, buildVersion: nil)
            return result(installedNumber < offered ? .available(release) : .noUpdate(release))
        } catch {
            if !Task.isCancelled {
                Self.logger.error(
                    "Could not query the release source: \(error.localizedDescription, privacy: .private)")
            }
            return result(.requestFailed)
        }
    }

    private func latestGitHubVersion(_ repository: Repository, installed: ApplicationVersion) async throws -> String? {
        // OpenCode publishes multiple supported series under one bundle ID. Its default release may be from another series.
        let tail = repository.matchInstalledMajor ? "?per_page=20" : "/latest"
        guard let url = URL(string: "https://api.github.com/repos/\(repository.slug)/releases\(tail)") else {
            throw URLError(.badURL)
        }
        let data = try await fetch(url)
        let decoder = JSONDecoder()
        let releases =
            repository.matchInstalledMajor
            ? try decoder.decode([GitHubRelease].self, from: data)
            : [try decoder.decode(GitHubRelease.self, from: data)]
        let installedMajor = installed.shortVersion.flatMap(Self.majorVersion)

        return releases.compactMap { release -> (version: String, number: NumericApplicationVersion)? in
            let version = release.version
            guard !release.draft, !release.prerelease, let number = NumericApplicationVersion(version),
                !repository.matchInstalledMajor || Self.majorVersion(version) == installedMajor
            else { return nil }
            let asset = repository.packageName(version, isAppleSilicon)
            guard release.assets.contains(where: { $0.name == asset && $0.state == "uploaded" }) else { return nil }
            return (version, number)
        }.max { $0.number < $1.number }?.version
    }

    private func latestWebsiteVersion(_ feed: VersionFeed) async throws -> String? {
        guard let url = URL(string: feed.url) else { throw URLError(.badURL) }
        let data = try await fetch(url)
        let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return metadata?[feed.versionKey] as? String
    }

    private static func majorVersion(_ version: String) -> UInt64? {
        version.split(separator: ".").first.flatMap { UInt64($0) }
    }
}

import Foundation

/// Reads the appcast metadata needed for a manual check of Sparkle's default channel.
struct SparkleAppcast {
    private enum ParseError: LocalizedError {
        case invalidFeed
        case bundleIdentifierMismatch

        var errorDescription: String? {
            switch self {
            case .invalidFeed: "The feed does not contain a valid Sparkle appcast."
            case .bundleIdentifierMismatch: "The appcast identifies a different application."
            }
        }
    }

    private let releases: [Release]

    init(data: Data, url: URL, bundleIdentifier: String?) throws {
        let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        guard let root = document.rootElement(), root.name == "rss",
            let channel = root.elements(forName: "channel").first
        else { throw ParseError.invalidFeed }
        if let declaredIdentifier = channel.sparkleText("bundleIdentifier"), declaredIdentifier != bundleIdentifier {
            throw ParseError.bundleIdentifierMismatch
        }

        let items = channel.elements(forName: "item")
        releases = items.compactMap { Release(item: $0, feedURL: url) }
        guard items.isEmpty || !releases.isEmpty else { throw ParseError.invalidFeed }
    }

    func evaluate(
        installedBuild: String, buildNumber: NumericApplicationVersion, macOS: OperatingSystemVersion,
        isAppleSilicon: Bool
    ) -> ApplicationUpdateResult.Outcome {
        let defaultReleases = releases.filter(\.isDefaultMacRelease)
        let ordered = defaultReleases.compactMap { release in
            release.buildNumber.map { (number: $0, release: release) }
        }.sorted { $0.number > $1.number }

        let systemVersion = NumericApplicationVersion(macOS)
        var newestBlockedRelease: ApplicationUpdateResult.Outcome?
        for (number, release) in ordered where number > buildNumber {
            let outcome = release.evaluate(
                installedBuild: installedBuild, buildNumber: buildNumber, systemVersion: systemVersion,
                isAppleSilicon: isAppleSilicon)
            if case .available = outcome { return outcome }
            if newestBlockedRelease == nil { newestBlockedRelease = outcome }
        }

        if let newestBlockedRelease { return newestBlockedRelease }
        guard ordered.count == defaultReleases.count else { return .uncomparableVersion }
        return .noUpdate(ordered.first?.release.version)
    }

    private struct Release {
        let version: ApplicationVersion
        let buildNumber: NumericApplicationVersion?
        let isDefaultMacRelease: Bool
        let hasFullUpdate: Bool
        let informationOnlyRule: InformationOnlyRule?
        let minimumSystemVersion: String?
        let maximumSystemVersion: String?
        let minimumUpdateVersion: String?
        let requiresAppleSilicon: Bool

        init?(item: XMLElement, feedURL: URL) {
            let enclosure = item.elements(forName: "enclosure").first
            guard let build = enclosure?.sparkleAttribute("version") ?? item.sparkleText("version") else { return nil }
            let download = enclosure?.attribute(forName: "url")?.stringValue
            hasFullUpdate =
                enclosure?.sparkleAttribute("deltaFrom") == nil && Self.hasWebURL(download, relativeTo: feedURL)
            let infoLink = item.elements(forName: "link").first?.stringValue
            let hasInfoLink = Self.hasWebURL(infoLink, relativeTo: feedURL)
            guard hasFullUpdate || hasInfoLink else { return nil }

            version = ApplicationVersion(
                shortVersion: enclosure?.sparkleAttribute("shortVersionString")
                    ?? item.sparkleText("shortVersionString"),
                buildVersion: build)
            buildNumber = NumericApplicationVersion(build)
            let platform = enclosure?.sparkleAttribute("os") ?? item.sparkleText("os")
            isDefaultMacRelease = item.sparkleText("channel") == nil && (platform == nil || platform == "macos")
            minimumSystemVersion = item.sparkleText("minimumSystemVersion")
            maximumSystemVersion = item.sparkleText("maximumSystemVersion")
            minimumUpdateVersion = item.sparkleText("minimumUpdateVersion")
            requiresAppleSilicon =
                item.sparkleText("hardwareRequirements")?.lowercased()
                .split { $0 == "," || $0.isWhitespace }.contains("arm64") == true
            informationOnlyRule =
                hasInfoLink ? item.sparkleElements("informationalUpdate").first.map(InformationOnlyRule.init) : nil
        }

        func evaluate(
            installedBuild: String, buildNumber: NumericApplicationVersion, systemVersion: NumericApplicationVersion,
            isAppleSilicon: Bool
        ) -> ApplicationUpdateResult.Outcome {
            if let minimumSystemVersion {
                guard let minimum = NumericApplicationVersion(minimumSystemVersion) else { return .uncomparableVersion }
                if systemVersion < minimum { return .incompatible(version, .minimumMacOS(minimumSystemVersion)) }
            }
            if let maximumSystemVersion {
                guard let maximum = NumericApplicationVersion(maximumSystemVersion) else { return .uncomparableVersion }
                if systemVersion > maximum { return .incompatible(version, .maximumMacOS(maximumSystemVersion)) }
            }
            if requiresAppleSilicon && !isAppleSilicon { return .incompatible(version, .appleSilicon) }
            if let minimumUpdateVersion {
                guard let minimum = NumericApplicationVersion(minimumUpdateVersion) else { return .uncomparableVersion }
                if buildNumber < minimum { return .incompatible(version, .minimumBuild(minimumUpdateVersion)) }
            }
            if !hasFullUpdate || informationOnlyRule?.matches(installedBuild, number: buildNumber) == true {
                return .informational(version)
            }
            return .available(version)
        }

        private static func hasWebURL(_ value: String?, relativeTo base: URL) -> Bool {
            guard let value = nonemptyText(value), let url = URL(string: value, relativeTo: base),
                let scheme = url.scheme?.lowercased()
            else { return false }
            return (scheme == "https" || scheme == "http") && url.host()?.isEmpty == false
        }
    }

    private struct InformationOnlyRule {
        let exactBuilds: [String]
        let upperBounds: [String]

        init(_ element: XMLElement) {
            exactBuilds = element.sparkleElements("version").compactMap { nonemptyText($0.stringValue) }
            upperBounds = element.sparkleElements("belowVersion").compactMap { nonemptyText($0.stringValue) }
        }

        func matches(_ installedBuild: String, number: NumericApplicationVersion) -> Bool {
            if exactBuilds.isEmpty && upperBounds.isEmpty { return true }
            return exactBuilds.contains(installedBuild)
                || upperBounds.contains { bound in NumericApplicationVersion(bound).map { number < $0 } ?? true }
        }
    }
}

extension XMLElement {
    fileprivate static var sparkleNamespace: String { "http://www.andymatuschak.org/xml-namespaces/sparkle" }

    fileprivate func sparkleElements(_ name: String) -> [XMLElement] {
        elements(forLocalName: name, uri: Self.sparkleNamespace)
    }

    fileprivate func sparkleText(_ name: String) -> String? {
        nonemptyText(sparkleElements(name).first?.stringValue)
    }

    fileprivate func sparkleAttribute(_ name: String) -> String? {
        nonemptyText(attribute(forLocalName: name, uri: Self.sparkleNamespace)?.stringValue)
    }
}

private func nonemptyText(_ rawValue: String?) -> String? {
    guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}

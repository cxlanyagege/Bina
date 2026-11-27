import Foundation

struct ApplicationUpdateResult: Sendable {
    enum Source: Equatable, Sendable {
        case sparkle(host: String?)
        case homebrew(token: String)
        case appStore(id: UInt64?, country: String?)
        case github(repository: String, releasesURL: URL)
        case website(downloadPage: URL)
    }

    enum Requirement: Equatable, Sendable {
        case minimumMacOS(String)
        case maximumMacOS(String)
        case appleSilicon
        case minimumBuild(String)
    }

    enum Outcome: Equatable, Sendable {
        case available(ApplicationVersion)
        case noUpdate(ApplicationVersion?)
        case incompatible(ApplicationVersion, Requirement)
        case informational(ApplicationVersion)
        case noSource
        case invalidFeedURL
        case unreadableApplication
        case uncomparableVersion
        case requestFailed
        case invalidAppcast
        case homebrewUnavailable
        case noStoreListing
        case noMatchingRelease
        case manualCheck

        var publishedVersion: ApplicationVersion? {
            switch self {
            case .available(let version), .incompatible(let version, _), .informational(let version): version
            case .noUpdate(let version): version
            default: nil
            }
        }
    }

    let installedVersion: ApplicationVersion?
    let source: Source?
    let outcome: Outcome
}

enum ApplicationUpdatePlatform {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
            return true
        #else
            // A translated Intel process can still use an Apple silicon release.
            var translated: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        #endif
    }
}

/// Orders dotted numeric versions with trailing zero components treated as equivalent.
struct NumericApplicationVersion: Comparable, Sendable {
    private let components: [UInt64]

    init?(_ value: String) {
        var components: [UInt64] = []
        for part in value.split(separator: ".", omittingEmptySubsequences: false) {
            guard part.first?.isNumber == true, let number = UInt64(part) else { return nil }
            components.append(number)
        }
        guard !components.isEmpty else { return nil }
        self.init(components: components)
    }

    init(_ version: OperatingSystemVersion) {
        self.init(components: [version.majorVersion, version.minorVersion, version.patchVersion].map(UInt64.init))
    }

    private init(components: [UInt64]) {
        var components = components
        while components.last == 0 { components.removeLast() }
        self.components = components
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

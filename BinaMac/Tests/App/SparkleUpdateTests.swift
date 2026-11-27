import Foundation
import Testing

@testable import BinaMac

@Suite("Sparkle update checks")
struct SparkleUpdateTests {
    @Test func readsTheCurrentBuildAndFeedFromTheSelectedCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeInfo(shortVersion: "1.0", build: "9", feed: "https://previous.example.com/feed.xml")
        let catalog = await InstalledApplicationCatalog.scan(directories: [fixture.root], indexedURLs: [])
        let application = try #require(catalog.applications.first)
        #expect(application.version == ApplicationVersion(shortVersion: "1.0", buildVersion: "9"))

        let version = ApplicationVersion(shortVersion: "2.0", buildVersion: "11")
        let checker = makeChecker { url in
            #expect(url.absoluteString == Fixture.feed)
            return Self.feed(
                """
                <item><sp:version>11</sp:version><sp:shortVersionString>2.0</sp:shortVersionString>
                  <enclosure url="updates/demo.zip"/>
                </item>
                """)
        }

        try fixture.writeInfo(shortVersion: "2.0", build: "10")
        let available = await checker.check(application)
        #expect(available.installedVersion == ApplicationVersion(shortVersion: "2.0", buildVersion: "10"))
        #expect(available.source == .sparkle(host: "updates.example.com"))
        #expect(available.outcome == .available(version))

        try fixture.writeInfo(shortVersion: "2.0", build: "11.0")
        let current = await checker.check(application)
        #expect(current.installedVersion == ApplicationVersion(shortVersion: "2.0", buildVersion: "11.0"))
        #expect(current.outcome == .noUpdate(version))
    }

    @Test func picksTheHighestCompatibleDefaultChannelReleaseFromAnUnsortedFeed() throws {
        let appcast = try parse(
            """
            <item><sp:version>1.99</sp:version><sp:channel>beta</sp:channel><enclosure url="beta.zip"/></item>
            <item><sp:version>2.0</sp:version><enclosure url="windows.zip" sp:os="windows"/></item>
            <item>
              <sp:version>1.13</sp:version><sp:minimumSystemVersion>27.0</sp:minimumSystemVersion>
              <enclosure url="new-system.zip"/>
            </item>
            <item>
              <enclosure url="mac.zip" sp:version="1.10" sp:shortVersionString="2.0" sp:os="macos"/>
            </item>
            <item>
              <sp:version>1.12</sp:version><sp:hardwareRequirements>arm64</sp:hardwareRequirements>
              <enclosure url="apple-silicon.zip"/>
            </item>
            <item><sp:version>1.9</sp:version><enclosure url="old.zip"/></item>
            """)

        #expect(
            try evaluate(appcast, installedBuild: "1.9", isAppleSilicon: false)
                == .available(ApplicationVersion(shortVersion: "2.0", buildVersion: "1.10")))
        #expect(
            try evaluate(appcast, installedBuild: "1.9", isAppleSilicon: true)
                == .available(ApplicationVersion(shortVersion: nil, buildVersion: "1.12")))
    }

    @Test(arguments: [
        ("minimumSystemVersion", "26.1", ApplicationUpdateResult.Requirement.minimumMacOS("26.1")),
        ("maximumSystemVersion", "25.9.9", .maximumMacOS("25.9.9")),
        ("hardwareRequirements", "arm64", .appleSilicon),
        ("minimumUpdateVersion", "11", .minimumBuild("11")),
    ])
    func canReportWhyANewerVersionIsUnavailable(
        element: String, value: String, reason: ApplicationUpdateResult.Requirement
    ) throws {
        let appcast = try parse(
            """
            <item><sp:version>12</sp:version><sp:\(element)>\(value)</sp:\(element)>
              <enclosure url="update.zip"/>
            </item>
            """)

        #expect(
            try evaluate(appcast, installedBuild: "10", isAppleSilicon: false)
                == .incompatible(ApplicationVersion(shortVersion: nil, buildVersion: "12"), reason))
    }

    @Test func distinguishesANewVersionAnnouncementFromAnAvailableUpdate() throws {
        let appcast = try parse(
            """
            <item><sp:version>12</sp:version><link>https://updates.example.com/12</link></item>
            <item>
              <sp:version>13</sp:version><link>https://updates.example.com/13</link>
              <sp:informationalUpdate><sp:belowVersion>11.0</sp:belowVersion></sp:informationalUpdate>
              <enclosure url="update.zip"/>
            </item>
            """)

        let version = ApplicationVersion(shortVersion: nil, buildVersion: "13")
        #expect(try evaluate(appcast, installedBuild: "10") == .informational(version))
        #expect(try evaluate(appcast, installedBuild: "11") == .available(version))
    }

    @Test func skipsNetworkRequestsForMissingOrInvalidSourcesAndUnsupportedLocalBuilds() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let checker = makeChecker { _ in
            Issue.record("A check without a usable source and build should not request an appcast.")
            throw URLError(.unsupportedURL)
        }

        try fixture.writeInfo(shortVersion: "1.0", build: "10", feed: nil)
        #expect(await checker.check(fixture.application).outcome == .noSource)
        try fixture.writeInfo(shortVersion: "1.0", build: "10", feed: "file:///tmp/appcast.xml")
        #expect(await checker.check(fixture.application).outcome == .invalidFeedURL)
        try fixture.writeInfo(shortVersion: "1.0", build: "custom-build")
        #expect(await checker.check(fixture.application).outcome == .uncomparableVersion)
        try fixture.writeInfo(shortVersion: "1.0", build: "10", bundleIdentifier: "com.example.Replacement")
        #expect(await checker.check(fixture.application).outcome == .unreadableApplication)
    }

    @Test func distinguishesLookupErrorsFromNoUpdate() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeInfo(shortVersion: "1.0", build: "10")

        let timedOut = makeChecker { _ in throw URLError(.timedOut) }
        let invalidFeed = makeChecker { _ in Data("<html></html>".utf8) }
        let wrongBundle = makeChecker { _ in
            Self.feed("<sp:bundleIdentifier>com.example.Other</sp:bundleIdentifier>")
        }
        let unsupportedVersion = makeChecker { _ in
            Self.feed("<item><sp:version>build-x</sp:version><enclosure url=\"update.zip\"/></item>")
        }

        #expect(await timedOut.check(fixture.application).outcome == .requestFailed)
        #expect(await invalidFeed.check(fixture.application).outcome == .invalidAppcast)
        #expect(await wrongBundle.check(fixture.application).outcome == .invalidAppcast)
        #expect(await unsupportedVersion.check(fixture.application).outcome == .uncomparableVersion)
    }

    private func makeChecker(fetch: @escaping @Sendable (URL) async throws -> Data) -> ApplicationUpdateChecker {
        ApplicationUpdateChecker(
            homebrew: HomebrewUpdateCatalog { .init() }, sparkle: SparkleUpdateChecker(fetch: fetch))
    }

    private static func feed(_ channelContents: String) -> Data {
        Data(
            """
            <rss version="2.0" xmlns:sp="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>\(channelContents)</channel>
            </rss>
            """.utf8)
    }

    private func parse(_ channelContents: String) throws -> SparkleAppcast {
        try SparkleAppcast(
            data: Self.feed(channelContents), url: #require(URL(string: Fixture.feed)),
            bundleIdentifier: Fixture.bundleIdentifier)
    }

    private func evaluate(_ appcast: SparkleAppcast, installedBuild: String, isAppleSilicon: Bool = true) throws
        -> ApplicationUpdateResult.Outcome
    {
        appcast.evaluate(
            installedBuild: installedBuild, buildNumber: try #require(NumericApplicationVersion(installedBuild)),
            macOS: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: isAppleSilicon)
    }

    private struct Fixture {
        static let feed = "https://updates.example.com/appcast.xml"
        static let bundleIdentifier = "com.example.SparkleUpdateTests"

        let root: URL
        let application: InstalledApplication

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let url = root.appending(path: "Demo.app", directoryHint: .isDirectory)
            application = InstalledApplication(
                url: url, name: "Demo", version: ApplicationVersion(shortVersion: nil, buildVersion: nil),
                bundleIdentifier: Self.bundleIdentifier)
            try FileManager.default.createDirectory(
                at: url.appending(path: "Contents", directoryHint: .isDirectory), withIntermediateDirectories: true)
        }

        func writeInfo(
            shortVersion: String, build: String, feed: String? = Self.feed,
            bundleIdentifier: String = Self.bundleIdentifier
        ) throws {
            var info = [
                "CFBundlePackageType": "APPL", "CFBundleName": "Demo", "CFBundleIdentifier": bundleIdentifier,
                "CFBundleShortVersionString": shortVersion, "CFBundleVersion": build,
            ]
            info["SUFeedURL"] = feed
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            try data.write(to: application.url.appending(path: "Contents/Info.plist"), options: .atomic)
        }

        func cleanUp() {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record(error)
            }
        }
    }
}

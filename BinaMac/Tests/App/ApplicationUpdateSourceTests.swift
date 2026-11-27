import Foundation
import Synchronization
import Testing

@testable import BinaMac

@Suite("Application update sources")
struct ApplicationUpdateSourceTests {
    @Test func checksTheCaskCopyByInstalledPathAndSharesTheInventory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let managed = try fixture.application(in: "Custom Applications", name: "Renamed", sparkle: true)
        let unmanaged = try fixture.application(in: "Other Applications", name: "Renamed", sparkle: true)
        let stage = fixture.caskroom.appending(path: "demo/1.0", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: stage.appending(path: "Demo.app"), withDestinationURL: managed.url)

        let snapshot = try fixture.inventory([
            fixture.cask(
                "demo",
                artifacts: [
                    [
                        "app": ["Demo.app", ["target": "Renamed.app"]],
                        "target": unmanaged.url.path,
                    ]
                ])
        ])
        let calls = Mutex(0)
        let homebrew = HomebrewUpdateCatalog {
            calls.withLock { $0 += 1 }
            return snapshot
        }
        let checker = ApplicationUpdateChecker(homebrew: homebrew, sparkle: Fixture.sparkleChecker)
        async let managedCheck = checker.check(managed)
        async let unmanagedCheck = checker.check(unmanaged)
        let (cask, sparkle) = await (managedCheck, unmanagedCheck)

        #expect(calls.withLock { $0 } == 1)
        #expect(cask.source == .homebrew(token: "homebrew/cask/demo"))
        #expect(cask.outcome == .available(ApplicationVersion(shortVersion: "1.1", buildVersion: nil)))
        #expect(sparkle.source == .sparkle(host: "updates.example.com"))
        #expect(sparkle.outcome == .available(ApplicationVersion(shortVersion: "1.2", buildVersion: "12")))
    }

    @Test func usesSparkleForSelfUpdatingCasksAndDoesNotOfferOlderCaskVersions() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let selfUpdating = try fixture.application(name: "Self Updating", sparkle: true)
        let onNewerVersion = try fixture.application(name: "Upgraded", version: "1.2")
        let unversioned = try fixture.application(name: "Unversioned")
        let packageOnly = try fixture.application(name: "Package Only")
        let snapshot = try fixture.inventory([
            fixture.cask("self-update", application: selfUpdating, autoUpdates: true),
            fixture.cask("upgraded", application: onNewerVersion),
            fixture.cask("unversioned", application: unversioned, version: "latest"),
            fixture.cask("package", artifacts: [["pkg": ["Demo.pkg"], "target": packageOnly.url.path]]),
        ])
        let checker = ApplicationUpdateChecker(
            homebrew: HomebrewUpdateCatalog { snapshot }, sparkle: Fixture.sparkleChecker)

        #expect(await checker.check(selfUpdating).source == .sparkle(host: "updates.example.com"))
        let upgraded = await checker.check(onNewerVersion)
        #expect(upgraded.source == .homebrew(token: "homebrew/cask/upgraded"))
        #expect(upgraded.outcome == .noUpdate(ApplicationVersion(shortVersion: "1.1", buildVersion: nil)))
        let latest = await checker.check(unversioned)
        #expect(latest.source == .homebrew(token: "homebrew/cask/unversioned"))
        #expect(latest.outcome == .uncomparableVersion)
        #expect(await checker.check(packageOnly).outcome == .noSource)
    }

    @Test func readsTheMatchingMacStoreListingForTheSelectedStorefront() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let application = try fixture.application(sparkle: true)
        try fixture.writeReceipt(in: application)
        let store = AppStoreUpdateChecker(
            spotlightID: { _ in 123 }, currentCountry: { "CN" },
            fetch: { url in
                #expect(url.host() == "itunes.apple.com")
                let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(parameters.contains(URLQueryItem(name: "id", value: "123")))
                #expect(parameters.contains(URLQueryItem(name: "country", value: "cn")))
                #expect(parameters.contains(URLQueryItem(name: "entity", value: "macSoftware")))
                return Data(
                    """
                    {"results":[
                      {"trackId":123,"bundleId":"com.example.Updates","kind":"software","version":"99.0"},
                      {"trackId":123,"bundleId":"com.example.Updates","kind":"mac-software","version":"1.10"}
                    ]}
                    """.utf8)
            })
        let checker = ApplicationUpdateChecker(
            homebrew: HomebrewUpdateCatalog {
                Issue.record("An App Store copy should use its store listing before querying Homebrew.")
                return .init()
            }, appStore: store, sparkle: Fixture.sparkleChecker)

        let result = await checker.check(application)
        #expect(result.source == .appStore(id: 123, country: "CN"))
        #expect(result.outcome == .available(ApplicationVersion(shortVersion: "1.10", buildVersion: nil)))
    }

    @Test func preservesTheStoreSourceWhenTheCatalogCannotIdentifyTheCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let application = try fixture.application(sparkle: true)
        try fixture.writeReceipt(in: application)
        let homebrew = HomebrewUpdateCatalog { .init() }
        let unindexed = AppStoreUpdateChecker(
            spotlightID: { _ in nil },
            fetch: { _ in
                Issue.record("An unindexed receipt must not cause a lookup by app name.")
                throw URLError(.unsupportedURL)
            })
        let result = await ApplicationUpdateChecker(homebrew: homebrew, appStore: unindexed).check(application)
        #expect(result.source == .appStore(id: nil, country: nil))
        #expect(result.outcome == .noStoreListing)

        let wrongListing = AppStoreUpdateChecker(
            spotlightID: { _ in 123 }, currentCountry: { "US" },
            fetch: { _ in
                Data(
                    """
                    {"results":[{"trackId":123,"bundleId":"com.example.Other","kind":"mac-software","version":"1.1"}]}
                    """.utf8)
            })
        let mismatched = await ApplicationUpdateChecker(homebrew: homebrew, appStore: wrongListing).check(application)
        #expect(mismatched.source == .appStore(id: 123, country: "US"))
        #expect(mismatched.outcome == .noStoreListing)
    }

    @Test func ignoresEmptyReceiptsAndRespectsTheStoreListingMinimumMacOS() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let application = try fixture.application()
        let fetches = Mutex(0)
        let store = AppStoreUpdateChecker(
            spotlightID: { _ in 123 }, currentCountry: { "US" },
            fetch: { _ in
                fetches.withLock { $0 += 1 }
                return Data(
                    """
                    {"results":[{"trackId":123,"bundleId":"com.example.Updates","kind":"mac-software",
                      "version":"1.1","minimumOsVersion":"999.0"}]}
                    """.utf8)
            })
        let checker = ApplicationUpdateChecker(homebrew: HomebrewUpdateCatalog { .init() }, appStore: store)
        try fixture.writeReceipt(in: application, contents: Data())
        #expect(await checker.check(application).outcome == .noSource)
        #expect(fetches.withLock { $0 } == 0)
        try fixture.writeReceipt(in: application)
        #expect(
            await checker.check(application).outcome
                == .incompatible(
                    ApplicationVersion(shortVersion: "1.1", buildVersion: nil), .minimumMacOS("999.0")))
    }

    @Test func mapsStorefrontCountryCodesBeforeUsingTheSystemRegion() {
        #expect(AppStoreUpdateChecker.country(storefront: "CHN", fallback: Locale.Region("US")) == "CN")
        #expect(AppStoreUpdateChecker.country(storefront: "GBR", fallback: Locale.Region("US")) == "GB")
        #expect(AppStoreUpdateChecker.country(storefront: "ZZZ", fallback: Locale.Region("JP")) == "JP")
    }

    @Test func usesTheBundledSparkleFeedBeforeTheCuratedReleaseSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let application = try fixture.application(sparkle: true, bundleIdentifier: "com.electron.ollama")
        let published = PublishedApplicationUpdateChecker { _ in
            Issue.record("The curated release should be a fallback for apps without an installed update source.")
            throw URLError(.unsupportedURL)
        }
        let checker = ApplicationUpdateChecker(
            homebrew: HomebrewUpdateCatalog { .init() }, sparkle: Fixture.sparkleChecker, published: published)

        let result = await checker.check(application)
        #expect(result.source == .sparkle(host: "updates.example.com"))
    }

    private struct Fixture {
        static let bundleIdentifier = "com.example.Updates"
        static let sparkleChecker = SparkleUpdateChecker { _ in
            Data(
                """
                <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
                  <item><sparkle:version>12</sparkle:version><sparkle:shortVersionString>1.2</sparkle:shortVersionString>
                    <enclosure url="release.zip"/>
                  </item>
                </channel></rss>
                """.utf8)
        }

        let root: URL
        var caskroom: URL { root.appending(path: "Caskroom", directoryHint: .isDirectory) }

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        }

        func application(
            in directory: String = "Applications", name: String = "Demo", version: String = "1.0",
            sparkle: Bool = false, bundleIdentifier: String = Self.bundleIdentifier
        ) throws -> InstalledApplication {
            let bundle = root.appending(path: directory).appending(path: "\(name).app", directoryHint: .isDirectory)
            let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info = [
                "CFBundlePackageType": "APPL", "CFBundleIdentifier": bundleIdentifier,
                "CFBundleShortVersionString": version, "CFBundleVersion": "10",
            ]
            if sparkle { info["SUFeedURL"] = "https://updates.example.com/appcast.xml" }
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            try plist.write(to: contents.appending(path: "Info.plist"))
            return InstalledApplication(
                url: bundle, name: name, version: ApplicationVersion(shortVersion: version, buildVersion: "10"),
                bundleIdentifier: bundleIdentifier)
        }

        func writeReceipt(in application: InstalledApplication, contents: Data = Data([1])) throws {
            let receipts = application.url.appending(path: "Contents/_MASReceipt", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
            try contents.write(to: receipts.appending(path: "receipt"), options: .atomic)
        }

        func cask(
            _ token: String, application: InstalledApplication, version: String = "1.1",
            autoUpdates: Bool = false
        ) -> [String: Any] {
            cask(
                token, version: version, autoUpdates: autoUpdates,
                artifacts: [
                    ["app": ["\(application.name).app"], "target": application.url.path]
                ])
        }

        func cask(
            _ token: String, version: String = "1.1", autoUpdates: Bool = false,
            artifacts: [[String: Any]]
        ) -> [String: Any] {
            [
                "token": token, "full_token": "homebrew/cask/\(token)", "installed": "1.0",
                "version": version, "outdated": true, "auto_updates": autoUpdates, "artifacts": artifacts,
            ]
        }

        func inventory(_ casks: [[String: Any]]) throws -> HomebrewUpdateCatalog.Snapshot {
            let data = try JSONSerialization.data(withJSONObject: ["casks": casks])
            return try HomebrewUpdateCatalog.snapshot(from: data, caskroom: caskroom)
        }

        func cleanUp() {
            do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
    }
}

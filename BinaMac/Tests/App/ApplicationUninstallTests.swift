import Foundation
import Synchronization
import Testing

@testable import BinaMac

@Suite("Application uninstall")
struct ApplicationUninstallTests {
    @Test func findsEvidenceInScanDirectoriesAndPreservesUserDataByDefault() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cache = try fixture.write("Library/Caches/com.example.Demo")
        let preferences = try fixture.write("Library/Preferences/com.example.Demo.plist")
        let hostPreferences = try fixture.write(
            "Library/Preferences/ByHost/com.example.Demo.004602DD-EA77-467C-8351-AC390EA705C1.plist")
        let support = try fixture.write("Library/Application Support/Vendor/Demo/config")
            .deletingLastPathComponent()
        let group = try fixture.write("Library/Group Containers/com.example.Demo/data")
            .deletingLastPathComponent()
        let service = try fixture.write(
            "Library/LaunchAgents/arbitrary-job.plist",
            data: PropertyListSerialization.data(
                fromPropertyList: ["ProgramArguments": [fixture.application.url.path + "/Contents/MacOS/demo"]],
                format: .xml, options: 0))
        let external = try fixture.write("Unselected/Library/Caches/com.example.Demo")
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appending(path: "Library/Caches/Demo"), withDestinationURL: external)
        _ = try fixture.write("Library/Caches/com.example.DemoOther")

        let scan = try await fixture.scan()
        let items = Dictionary(uniqueKeysWithValues: scan.candidates.map { ($0.file.url.path, $0) })
        #expect(Set(items.keys) == Set([cache, preferences, hostPreferences, support, group, service].map(\.path)))
        #expect(items[cache.path]?.disposition == .optional)
        #expect(items[cache.path]?.size == 4)
        #expect(items[preferences.path]?.disposition == .optional)
        #expect(items[support.path]?.evidence == .applicationName)
        #expect(items[group.path]?.disposition == .reviewOnly)
        #expect(items[group.path]?.size == nil)
        #expect(items[service.path]?.evidence == .launchProgram)
        #expect(items[service.path]?.disposition == .reviewOnly)
        #expect(scan.unreadableLocations.isEmpty)
    }

    @Test func doesNotRequestFullDiskAccessForPOSIXDirectoryPermissions() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let missing = await AppManagementDiskAccess.hasRestrictedScanAccess(in: fixture.library)
        let cookies = fixture.library.appending(component: "Cookies", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cookies, withIntermediateDirectories: false)
        let readable = await AppManagementDiskAccess.hasRestrictedScanAccess(in: fixture.library)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: cookies.path)
        let restricted = await AppManagementDiskAccess.hasRestrictedScanAccess(in: fixture.library)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cookies.path)

        #expect(!missing)
        #expect(!readable)
        #expect(!restricted)
    }

    @Test @MainActor func selectsAllRemovableItemsInitiallyAndKeepsManualChangesOnRescan() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let exact = try fixture.write("Library/Caches/com.example.Demo")
        let variant = try fixture.write("Library/prefix-com.example.Demo-metadata")
        let receipt = try fixture.write("Library/Receipts/com.example.Demo.bom")
        let review = ApplicationUninstallReview(
            application: fixture.application, catalogHasOtherCopies: false, scanDirectories: [fixture.library])

        await review.rescan()
        let scan = try #require(review.scan)
        let applicationSize = try #require(scan.applicationSize)
        let items = Dictionary(uniqueKeysWithValues: scan.candidates.map { ($0.file.url.path, $0) })
        let exactItem = try #require(items[exact.path])
        let variantItem = try #require(items[variant.path])
        #expect(exactItem.evidence == .bundleIdentifier)
        #expect(variantItem.evidence == .bundleIdentifierVariant)
        #expect(exactItem.disposition == .optional)
        #expect(variantItem.disposition == .optional)
        #expect(items[receipt.path]?.disposition == .reviewOnly)
        #expect(review.selection == [exactItem.id, variantItem.id])
        #expect(review.itemCount == 4)
        #expect(review.selectedItemCount == 3)
        #expect(review.selectedSize.knownBytes == applicationSize + 8)
        #expect(review.selectedSize.isComplete)

        review.selection.remove(exactItem.id)
        await review.rescan()
        #expect(review.selection == [variantItem.id])
        #expect(review.itemCount == 4)
        #expect(review.selectedItemCount == 2)
        #expect(review.selectedSize.knownBytes == applicationSize + 4)
        #expect(review.selectedSize.isComplete)
    }

    @Test @MainActor func countsNestedFilesOnceAndReportsAnUnmeasuredSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let nested = try fixture.write("Library/Caches/com.example.Demo/com.example.Demo.log")
        let parent = nested.deletingLastPathComponent()
        let container = try fixture.write("Library/Containers/com.example.Demo/settings").deletingLastPathComponent()
        let review = ApplicationUninstallReview(
            application: fixture.application, catalogHasOtherCopies: false, scanDirectories: [fixture.library, parent])
        await review.rescan()
        let scan = try #require(review.scan)
        let applicationSize = try #require(scan.applicationSize)
        let items = Dictionary(uniqueKeysWithValues: scan.candidates.map { ($0.file.url.path, $0) })
        let parentItem = try #require(items[parent.path])
        let nestedItem = try #require(items[nested.path])
        let containerItem = try #require(items[container.path])

        review.selection = [parentItem.id, nestedItem.id]
        #expect(review.selectedSize.knownBytes == applicationSize + 4)
        #expect(review.selectedSize.isComplete)

        review.selection.insert(containerItem.id)
        #expect(review.selectedSize.knownBytes == applicationSize + 4)
        #expect(!review.selectedSize.isComplete)
    }

    @Test @MainActor func startsTheReviewWithStandardSearchDirectories() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let review = ApplicationUninstallReview(application: fixture.application, catalogHasOtherCopies: false)
        let home = try #require(FileManager.default.homeDirectory(forUser: NSUserName()))
        let userLibrary = home.appending(path: "Library", directoryHint: .isDirectory).resolvingSymlinksInPath()
        let receipts = URL(filePath: "/private/var/db/receipts", directoryHint: .isDirectory).resolvingSymlinksInPath()

        #expect(Set(review.scanDirectories.map(\.path)) == [userLibrary.path, "/Library", receipts.path])
    }

    @Test func keepsRelatedItemsForAnotherInstalledCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        _ = try fixture.write("Library/Caches/com.example.Demo")

        let scan = try await fixture.scan(otherCopy: true)
        #expect(scan.candidates.count == 1)
        #expect(scan.candidates.first?.disposition == .reviewOnly)
    }

    @Test @MainActor func findsPreviouslyMissedFilesInBothLibraryScopes() async throws {
        let fixture = try Fixture(info: ["CFBundleName": "Démon Tool", "CFBundleExecutable": "DemoUI"])
        defer { fixture.cleanUp() }
        let additionalLibrary = fixture.root.appending(path: "Shared/Library", directoryHint: .isDirectory)

        let updater = try fixture.write("Library/Caches/com.example.Demo.ShipIt/info").deletingLastPathComponent()
        let diagnostic = try fixture.write("Library/Logs/DiagnosticReports/DemoUI-2026-11-23-152603.ips")
        let cookies = try fixture.write("Library/Cookies/com.example.Demo.binarycookies")
        let synced = try fixture.write("Library/SyncedPreferences/com.example.Demo.plist")
        let support = try fixture.write("Library/Application Support/Vendor/Profile/com.example.Demo/data")
            .deletingLastPathComponent()
        let alternateName = try fixture.write("Library/Application Support/Demon-Tool 4/data")
            .deletingLastPathComponent()
        let history = try fixture.write(
            "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.example.Demo.sfl3"
        )
        let helpCache = try fixture.write("Library/Caches/com.apple.helpd/Generated/com.example.Demo/index")
            .deletingLastPathComponent()
        let receipt = try fixture.write("Shared/Library/Receipts/com.example.Demo.bom")
        let rootItem = try fixture.write("Shared/Library/com.example.Demo.plist")
        let shared = try fixture.write("Library/Group Containers/ABCDEFG123.com.example.Demo/data")
            .deletingLastPathComponent()
        _ = try fixture.write("Library/Logs/DiagnosticReports/DemoUIOther-2026-11-23-152603.ips")
        _ = try fixture.write("Unselected/Library/SyncedPreferences/com.example.Demo.plist")

        let review = ApplicationUninstallReview(
            application: fixture.application, catalogHasOtherCopies: false,
            scanDirectories: [fixture.library, additionalLibrary])
        await review.rescan()
        let scan = try #require(review.scan)
        let items = Dictionary(uniqueKeysWithValues: scan.candidates.map { ($0.file.url.path, $0) })
        #expect(
            Set(items.keys)
                == Set(
                    [
                        updater, diagnostic, cookies, synced, support, alternateName, history, helpCache, receipt,
                        rootItem, shared,
                    ].map(\.path)))
        #expect(items[updater.path]?.evidence == .bundleIdentifierVariant)
        #expect(items[updater.path]?.disposition == .optional)
        #expect(items[diagnostic.path]?.evidence == .diagnosticName)
        #expect(items[diagnostic.path]?.disposition == .optional)
        #expect(items[alternateName.path]?.evidence == .applicationName)
        #expect(items[history.path]?.kind == .preference)
        #expect(items[receipt.path]?.disposition == .reviewOnly)
        #expect(items[shared.path]?.disposition == .reviewOnly)
    }

    @Test func usesEmbeddedComponentIdentifiersAndLaunchArguments() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        _ = try fixture.write(
            "Demo.app/Contents/Library/LoginItems/Sidekick.app/Contents/Info.plist",
            data: PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "com.example.Sidekick", "CFBundlePackageType": "APPL"],
                format: .xml, options: 0))
        let cache = try fixture.write("Library/Caches/com.example.Sidekick")
        let job = try fixture.write(
            "Library/LaunchAgents/launch-wrapper.plist",
            data: PropertyListSerialization.data(
                fromPropertyList: ["ProgramArguments": ["/usr/bin/open", fixture.application.url.path]],
                format: .xml, options: 0))

        let scan = try await fixture.scan()
        let items = Dictionary(uniqueKeysWithValues: scan.candidates.map { ($0.file.url.path, $0) })
        #expect(Set(items.keys) == Set([cache.path, job.path]))
        #expect(items[cache.path]?.evidence == .componentBundleIdentifier)
        #expect(items[cache.path]?.disposition == .optional)
        #expect(items[job.path]?.evidence == .launchProgram)
        #expect(items[job.path]?.disposition == .reviewOnly)
    }

    @Test func skipsLinksInTheMiddleOfKnownSearchPaths() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let outside = try fixture.write("Unselected/Generated/com.example.Demo")
            .deletingLastPathComponent().deletingLastPathComponent()
        let cache = fixture.library.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: cache.appending(path: "com.apple.helpd"), withDestinationURL: outside)

        let scan = try await fixture.scan()
        #expect(scan.candidates.isEmpty)
        #expect(scan.unreadableLocations.map(\.path) == [cache.appending(path: "com.apple.helpd/Generated").path])
    }

    @Test func reportsAnUnavailableScanDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let missing = fixture.root.appending(path: "Unavailable", directoryHint: .isDirectory)

        let result = try await ApplicationResidueScanner.scan(
            application: fixture.application, directories: [missing], hasOtherCopies: false)
        #expect(result.unreadableLocations == [missing])
    }

    @Test func reportsDeniedDirectoriesAndContinuesScanning() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let denied = try fixture.write("Library/Application Support/LockedService/com.example.Demo.plist")
            .deletingLastPathComponent()
        let readable = try fixture.write("Library/Caches/com.example.Demo")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer {
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
            } catch {
                Issue.record(error)
            }
        }

        let result = try await fixture.scan()
        #expect(result.unreadableLocations.map(\.path) == [denied.path])
        #expect(result.candidates.map(\.file.url.path) == [readable.path])
    }

    @Test func letsTheUserChooseAnExactMatchInACustomFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let exact = try fixture.write("Additional/com.example.Demo.plist")
        let byName = try fixture.write("Additional/Demo.txt")

        let result = try await ApplicationResidueScanner.scan(
            application: fixture.application, directories: [exact.deletingLastPathComponent()],
            hasOtherCopies: false)
        let items = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.file.url.path, $0.disposition) })
        #expect(items[exact.path] == .optional)
        #expect(items[byName.path] == .reviewOnly)
    }

    @Test func stopsBeforeRelatedFilesWhenTheApplicationMoveFails() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cache = try fixture.write("Library/Caches/com.example.Demo")
        let scan = try await fixture.scan()
        let plan = ApplicationTrashPlan(
            application: scan.application, relatedItems: scan.candidates, scanDirectories: [fixture.library])
        let calls = Mutex<[String]>([])

        let outcomes = await plan.execute { url in
            calls.withLock { $0.append(url.path) }
            throw CocoaError(.fileWriteNoPermission)
        }

        #expect(calls.withLock { $0 } == [fixture.application.url.path])
        #expect(outcomes.count == 2)
        if case .failed(let reason) = outcomes.first?.status {
            #expect(reason.contains("App 管理"))
        } else {
            Issue.record("The app move failure should include the macOS permission setting.")
        }
        #expect(outcomes.last?.originalURL.path == cache.path)
        if case .skipped = outcomes.last?.status {
        } else {
            Issue.record("The related item should remain when moving the app fails.")
        }
    }

    @Test func revalidatesEachSelectedFileAndReportsPartialResults() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cache = try fixture.write("Library/Caches/com.example.Demo")
        let log = try fixture.write("Library/Logs/com.example.Demo.log")
        let scan = try await fixture.scan()
        try FileManager.default.moveItem(at: cache, to: fixture.root.appending(path: "original-cache"))
        _ = try fixture.write("Library/Caches/com.example.Demo")
        let plan = ApplicationTrashPlan(
            application: scan.application, relatedItems: scan.candidates, scanDirectories: [fixture.library])
        let calls = Mutex<[String]>([])

        let result = await plan.execute { url in
            calls.withLock { $0.append(url.path) }
            return url
        }

        #expect(calls.withLock { $0 } == [fixture.application.url.path, log.path])
        #expect(result.first?.succeeded == true)
        if case .failed = result.first(where: { $0.originalURL.path == cache.path })?.status {
        } else {
            Issue.record("The file that changed after review should be reported.")
        }
        #expect(result.first(where: { $0.originalURL.path == log.path })?.succeeded == true)
    }

    @Test func rejectsRelatedItemsOutsideTheScanDirectories() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        _ = try fixture.write("Library/Caches/com.example.Demo")
        let scan = try await fixture.scan()
        let plan = ApplicationTrashPlan(
            application: scan.application, relatedItems: scan.candidates, scanDirectories: [])
        let calls = Mutex<[String]>([])

        let outcomes = await plan.execute { url in
            calls.withLock { $0.append(url.path) }
            return nil
        }
        #expect(calls.withLock { $0 } == [fixture.application.url.path])
        #expect(outcomes.map(\.succeeded) == [true, false])
    }

    @Test func rejectsMovingTheRunningBinaBundle() async throws {
        let app = try UninstallFile(at: Bundle.main.bundleURL.resolvingSymlinksInPath())
        let plan = ApplicationTrashPlan(application: app, relatedItems: [], scanDirectories: [])

        let outcomes = await plan.execute { _ in
            Issue.record("The running Bina bundle should never be moved.")
            return nil
        }
        #expect(outcomes.map(\.succeeded) == [false])
    }

    private struct Fixture {
        let root: URL
        let application: InstalledApplication
        var library: URL { root.appending(path: "Library", directoryHint: .isDirectory) }

        init(info overrides: [String: String] = [:]) throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            application = InstalledApplication(
                url: root.appending(path: "Demo.app", directoryHint: .isDirectory),
                name: "Demo", version: "1.0", bundleIdentifier: "com.example.Demo")
            let info = [
                "CFBundlePackageType": "APPL", "CFBundleIdentifier": "com.example.Demo", "CFBundleName": "Demo",
            ].merging(overrides) { _, value in value }
            _ = try write(
                "Demo.app/Contents/Info.plist",
                data: PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0))
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        }

        func scan(otherCopy: Bool = false) async throws -> ApplicationUninstallScan {
            try await ApplicationResidueScanner.scan(
                application: application, directories: [library], hasOtherCopies: otherCopy)
        }

        func write(_ path: String, data: Data = Data("test".utf8)) throws -> URL {
            let file = root.appending(path: path, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
            return file
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

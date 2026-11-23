import Foundation
import Testing

@testable import BinaMac

@Suite("Installed application catalog")
struct InstalledApplicationCatalogTests {
    @Test func excludesSystemBundlesAndKeepsSeparatelyInstalledAppleApps() async throws {
        let workspace = try makeWorkspace()
        defer { deleteWorkspace(workspace) }
        let preview = URL(filePath: "/System/Applications/Preview.app", directoryHint: .isDirectory)
        try #require(FileManager.default.fileExists(atPath: preview.path))
        let systemLink = workspace.appending(path: "System App Link.app")
        try FileManager.default.createSymbolicLink(at: systemLink, withDestinationURL: preview)
        let separateApp = try makeApplication(
            "Separate App", in: workspace, metadata: ["CFBundleIdentifier": "com.apple.example.SeparateApp"])

        let catalog = await InstalledApplicationCatalog.scan(
            directories: [workspace],
            indexedURLs: [preview, URL(filePath: "/Applications/Safari.app")])

        #expect(catalog.applications.map(\.url.path) == [separateApp.path])
        #expect(!catalog.hasUnreadableLocations)
    }

    @Test func mergesFoldersAndIndexResultsWithoutHidingSeparateCopies() async throws {
        let workspace = try makeWorkspace()
        defer { deleteWorkspace(workspace) }
        let standardFolder = workspace.appending(path: "Applications")
        let indexedFolder = workspace.appending(path: "Other")
        let first = try makeApplication(
            "Utility 2", in: standardFolder.appending(path: "Utilities"),
            metadata: ["CFBundleShortVersionString": "2.1", "CFBundleVersion": "42"])
        let second = try makeApplication("Utility 10", in: standardFolder, metadata: ["CFBundleVersion": "10"])
        let separateCopy = try makeApplication("Utility 10", in: indexedFolder)
        let embeddedHelper = try makeApplication("Helper", in: first.appending(path: "Contents/Helpers"))
        let link = standardFolder.appending(path: "Alias.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)

        let catalog = await InstalledApplicationCatalog.scan(
            directories: [standardFolder, workspace.appending(path: "Missing")],
            indexedURLs: [first, second, separateCopy, embeddedHelper, link])

        #expect(catalog.applications.map(\.name) == ["Utility 2", "Utility 10", "Utility 10"])
        #expect(Set(catalog.applications.map(\.url.path)) == Set([first.path, second.path, separateCopy.path]))
        #expect(catalog.applications.map(\.version) == ["2.1", "10", nil])
        #expect(catalog.applications.allSatisfy { $0.bundleIdentifier == "test.Bina.ApplicationCatalog" })
        #expect(!catalog.hasUnreadableLocations)
    }

    @Test func skipsStaleIndexEntriesAndDirectoriesThatAreOnlyNamedLikeApps() async throws {
        let workspace = try makeWorkspace()
        defer { deleteWorkspace(workspace) }
        let emptyDirectory = workspace.appending(path: "Empty.app")
        let regularFile = workspace.appending(path: "Document.app")
        try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
        try Data().write(to: regularFile)

        let catalog = await InstalledApplicationCatalog.scan(
            directories: [workspace], indexedURLs: [workspace.appending(path: "Removed.app")])

        #expect(catalog.applications.isEmpty)
        #expect(!catalog.hasUnreadableLocations)
    }

    @Test func searchFiltersByDisplayNameWithoutChangingTheOriginalOrder() {
        let names = ["Alphabét", "Archive", "Café Alphabet"]
        let applications = names.map {
            InstalledApplication(
                url: URL(filePath: "/Applications/\($0).app"), name: $0, version: nil, bundleIdentifier: nil)
        }
        let catalog = InstalledApplicationCatalog(applications: applications, hasUnreadableLocations: false)

        #expect(catalog.matching("  ALPHABET\n").map(\.name) == ["Alphabét", "Café Alphabet"])
        #expect(catalog.matching("  ") == applications)
        #expect(catalog.matching("missing").isEmpty)
    }

    private func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        return workspace
    }

    private func deleteWorkspace(_ workspace: URL) {
        do {
            try FileManager.default.removeItem(at: workspace)
        } catch {
            Issue.record(error)
        }
    }

    private func makeApplication(_ name: String, in directory: URL, metadata: [String: String] = [:]) throws -> URL {
        let url = directory.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = metadata.merging(
            [
                "CFBundlePackageType": "APPL",
                "CFBundleIdentifier": "test.Bina.ApplicationCatalog",
                "CFBundleName": name,
            ]
        ) { supplied, _ in supplied }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return url
    }
}

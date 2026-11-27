import CoreFoundation
import Foundation
import OSLog
import UniformTypeIdentifiers

struct InstalledApplication: Hashable, Identifiable, Sendable {
    let url: URL
    let name: String
    let version: ApplicationVersion
    let bundleIdentifier: String?

    var id: URL { url }
}

/// A read-only snapshot of separately installed app bundles found in application folders and the local Spotlight index.
struct InstalledApplicationCatalog: Sendable {
    let applications: [InstalledApplication]
    let hasUnreadableLocations: Bool

    private static let logger = Logger(subsystem: "BinaMac", category: "ApplicationCatalog")
    static let packageExtensions: Set<String> = ["app", "appex", "bundle", "framework", "plugin", "xpc"]

    static var applicationDirectories: [URL] {
        let fileManager = FileManager.default
        var directories = fileManager.urls(for: .applicationDirectory, in: .localDomainMask)
        if let home = fileManager.homeDirectory(forUser: NSUserName()) {
            directories.append(home.appending(path: "Applications", directoryHint: .isDirectory))
        }
        return directories
    }

    @MainActor
    static func load() async -> Self {
        let indexedURLs = await indexedApplicationURLs()
        return await scan(directories: applicationDirectories, indexedURLs: indexedURLs)
    }

    func matching(_ searchText: String) -> [InstalledApplication] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? applications : applications.filter { $0.name.localizedStandardContains(term) }
    }

    @concurrent
    static func scan(directories: [URL], indexedURLs: [URL]) async -> Self {
        var candidates: [URL] = []
        var hasUnreadableLocations = false

        // Enumerate the standard directories first to keep their paths when Spotlight also finds the same bundle.
        for directory in directories {
            guard !Task.isCancelled else { break }
            let entries = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) { _, error in
                if !isMissingFile(error) {
                    hasUnreadableLocations = true
                    logger.error("Could not enumerate applications: \(error.localizedDescription, privacy: .private)")
                }
                return true
            }
            guard let entries else { continue }
            while let url = entries.nextObject() as? URL {
                guard !Task.isCancelled else { break }
                if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                    candidates.append(url)
                    entries.skipDescendants()
                }
            }
        }

        var applications: [InstalledApplication] = []
        var visitedURLs: Set<URL> = []
        var fileIdentifiers: Set<NSObject> = []
        for candidate in candidates + indexedURLs {
            guard !Task.isCancelled else { break }
            guard isListableApplicationURL(candidate) else { continue }
            let url = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isListableApplicationURL(url), visitedURLs.insert(url).inserted else { continue }
            do {
                let values = try url.resourceValues(
                    forKeys: [.isDirectoryKey, .isApplicationKey, .localizedNameKey, .fileResourceIdentifierKey]
                )
                // Read the current plist even if a previous version of this bundle is cached at the same URL.
                guard values.isDirectory == true,
                    let info = CFBundleCopyInfoDictionaryInDirectory(url as CFURL) as? [String: Any],
                    info["CFBundlePackageType"] as? String == "APPL"
                        || (values.isApplication == true && Bundle(url: url)?.executableURL != nil)
                else { continue }
                if let identifier = values.fileResourceIdentifier as? NSObject,
                    !fileIdentifiers.insert(identifier).inserted
                {
                    continue
                }

                let displayName = values.localizedName ?? url.lastPathComponent
                let name = displayName.lowercased().hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
                let metadata = ApplicationBundleMetadata(info: info)
                applications.append(
                    InstalledApplication(
                        url: url, name: name, version: metadata.version, bundleIdentifier: metadata.bundleIdentifier
                    ))
            } catch {
                if !isMissingFile(error) {
                    hasUnreadableLocations = true
                    logger.error("Could not read an app bundle: \(error.localizedDescription, privacy: .private)")
                }
            }
        }

        applications.sort { left, right in
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.url.path < right.url.path : order == .orderedAscending
        }
        return Self(applications: applications, hasUnreadableLocations: hasUnreadableLocations)
    }

    static func isListableApplicationURL(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
            !isSystemApplicationURL(url)
        else { return false }
        // An enclosing package marks the candidate as an embedded helper.
        return url.pathComponents.allSatisfy { !$0.hasPrefix(".") }
            && url.pathComponents.dropLast().allSatisfy {
                !packageExtensions.contains(($0 as NSString).pathExtension.lowercased())
            }
    }

    static func logicalPath(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        let dataVolume = "/System/Volumes/Data"
        // Use the logical path when Spotlight returns a location on the startup data volume.
        return path.hasPrefix(dataVolume + "/") ? String(path.dropFirst(dataVolume.count)) : path
    }

    static func isSystemApplicationURL(_ url: URL) -> Bool {
        let path = logicalPath(of: url)
        return path == "/System" || path.hasPrefix("/System/")
            || path == "/Library/Apple/System" || path.hasPrefix("/Library/Apple/System/")
    }

    static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return
            (error.domain == NSCocoaErrorDomain
            && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code))
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
    }

    @MainActor
    static func makeIndexQuery() -> NSMetadataQuery {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.predicate = NSPredicate(
            format: "%K == %@", NSMetadataItemContentTypeTreeKey, UTType.applicationBundle.identifier)
        return query
    }

    @MainActor
    private static func indexedApplicationURLs() async -> [URL] {
        let query = makeIndexQuery()
        let (completion, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil
        ) { _ in
            signal.yield(())
            signal.finish()
        }
        defer {
            query.stop()
            NotificationCenter.default.removeObserver(observer)
        }

        guard query.start() else {
            logger.notice("Spotlight couldn't start an application query")
            return []
        }

        // Spotlight may be unavailable during indexing. Keep any results it has gathered and scan the usual folders.
        let deadline = Task {
            try await Task.sleep(for: .seconds(2))
            signal.finish()
        }
        defer { deadline.cancel() }
        var iterator = completion.makeAsyncIterator()
        let finished = await iterator.next() != nil
        guard !Task.isCancelled else { return [] }
        if !finished {
            logger.notice("Spotlight application discovery reached its deadline")
        }
        query.disableUpdates()
        return query.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL }
    }
}

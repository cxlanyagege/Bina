import Foundation

struct UninstallCandidate: Identifiable, Sendable {
    enum Kind: Sendable {
        case cache, preference, log, savedState, support, container, sharedContainer, service, plugIn, receipt, other
    }

    enum Evidence: Sendable {
        case bundleIdentifier, componentBundleIdentifier, bundleIdentifierVariant, applicationName, diagnosticName,
            applicationGroup, launchProgram
    }

    enum Disposition: Sendable {
        case optional, reviewOnly
    }

    let file: UninstallFile
    let kind: Kind
    let evidence: Evidence
    let disposition: Disposition
    let size: Int64?

    var id: URL { file.url }
}

struct ApplicationUninstallScan: Sendable {
    let application: UninstallFile
    let applicationSize: Int64?
    let candidates: [UninstallCandidate]
    let unreadableLocations: [URL]
    let uninstaller: URL?
}

/// Looks for related items within the current review's search directories.
struct ApplicationResidueScanner {
    private struct SearchLocation {
        let path: String
        let kind: UninstallCandidate.Kind
        var depth = 0
    }

    // Specific subdirectories are scanned first so an overlapping parent can reuse their candidates.
    private static let standardLocations = [
        SearchLocation(path: "Caches/com.apple.helpd/Generated", kind: .cache),
        SearchLocation(path: "Preferences/ByHost", kind: .preference),
        SearchLocation(path: "Logs/DiagnosticReports", kind: .log),
        SearchLocation(path: "Application Support/CrashReporter", kind: .log),
        SearchLocation(
            path: "Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",
            kind: .preference),
        SearchLocation(path: "Caches", kind: .cache, depth: 1),
        SearchLocation(path: "Preferences", kind: .preference),
        SearchLocation(path: "SyncedPreferences", kind: .preference),
        SearchLocation(path: "Logs", kind: .log, depth: 1),
        SearchLocation(path: "Saved Application State", kind: .savedState),
        SearchLocation(path: "Application Support", kind: .support, depth: 2),
        SearchLocation(path: "Containers", kind: .container),
        SearchLocation(path: "Group Containers", kind: .sharedContainer),
        SearchLocation(path: "Cookies", kind: .container),
        SearchLocation(path: "Application Scripts", kind: .support),
        SearchLocation(path: "HTTPStorages", kind: .container),
        SearchLocation(path: "WebKit", kind: .container),
        SearchLocation(path: "LaunchAgents", kind: .service),
        SearchLocation(path: "LaunchDaemons", kind: .service),
        SearchLocation(path: "PrivilegedHelperTools", kind: .service),
        SearchLocation(path: "Internet Plug-Ins", kind: .plugIn),
        SearchLocation(path: "PreferencePanes", kind: .plugIn),
        SearchLocation(path: "QuickLook", kind: .plugIn),
        SearchLocation(path: "Services", kind: .plugIn),
        SearchLocation(path: "Receipts", kind: .receipt),
    ]
    private static let standardRoots = Set(
        standardLocations.compactMap {
            $0.path.split(separator: "/").first.map(String.init)
        })
    private static let entryKeys: Set<URLResourceKey> = [
        .isSymbolicLinkKey, .isDirectoryKey, .isPackageKey, .isHiddenKey,
    ]

    private let application: InstalledApplication
    private let hasOtherCopies: Bool
    private let identity: ApplicationResidueIdentity
    private var candidates: [URL: UninstallCandidate] = [:]
    private var unreadable: Set<URL> = []

    static var defaultDirectories: [URL] {
        let fileManager = FileManager.default
        return fileManager.urls(for: .libraryDirectory, in: .userDomainMask)
            + fileManager.urls(for: .libraryDirectory, in: .localDomainMask)
            + [URL(filePath: "/private/var/db/receipts", directoryHint: .isDirectory)]
    }

    private init(application: InstalledApplication, hasOtherCopies: Bool, identity: ApplicationResidueIdentity) {
        self.application = application
        self.hasOtherCopies = hasOtherCopies
        self.identity = identity
        unreadable = Set(identity.unreadableLocations)
    }

    @concurrent
    static func scan(
        application: InstalledApplication,
        directories: [URL],
        hasOtherCopies: Bool
    ) async throws -> ApplicationUninstallScan {
        let appFile = try UninstallFile(at: application.url)
        guard appFile.isDirectory, appFile.url.pathExtension.lowercased() == "app",
            let bundle = Bundle(url: appFile.url), let info = bundle.infoDictionary,
            info["CFBundleIdentifier"] as? String == application.bundleIdentifier,
            info["CFBundlePackageType"] as? String == "APPL" || bundle.executableURL != nil
        else { throw UninstallFileError.changed }

        let identity = ApplicationResidueIdentity(
            application: application, info: info, localizedInfo: bundle.localizedInfoDictionary)
        var scanner = Self(application: application, hasOtherCopies: hasOtherCopies, identity: identity)
        for directory in directories {
            try Task.checkCancellation()
            if directory.lastPathComponent == "Library" {
                for location in standardLocations {
                    let url: URL
                    do {
                        url = try UninstallFile.directory(at: location.path, in: directory)
                    } catch {
                        if !InstalledApplicationCatalog.isMissingFile(error) {
                            scanner.unreadable.insert(directory.appending(path: location.path))
                        }
                        continue
                    }
                    try scanner.scanDirectory(url, kind: location.kind, depth: location.depth)
                }
                try scanner.scanDirectory(directory, kind: .other, depth: 0, isLibraryRoot: true, required: true)
            } else {
                let location = searchLocation(for: directory)
                try scanner.scanDirectory(directory, kind: location.kind, depth: location.depth, required: true)
            }
        }
        let items = scanner.candidates.values.sorted {
            $0.file.url.path.localizedStandardCompare($1.file.url.path) == .orderedAscending
        }
        return ApplicationUninstallScan(
            application: appFile,
            applicationSize: size(of: appFile),
            candidates: items,
            unreadableLocations: scanner.unreadable.sorted { $0.path < $1.path },
            uninstaller: findUninstaller(for: application.url)
        )
    }

    private static func searchLocation(for directory: URL) -> SearchLocation {
        if directory.path == "/private/var/db/receipts" || directory.path == "/var/db/receipts" {
            return SearchLocation(path: "", kind: .receipt)
        }
        let components = directory.pathComponents
        let custom = SearchLocation(path: "", kind: .other)
        guard let index = components.lastIndex(of: "Library"), index + 1 < components.count else { return custom }
        let relativePath = components.dropFirst(index + 1).joined(separator: "/")
        if let location = standardLocations.first(where: { $0.path == relativePath }) {
            return location
        }
        // Selection of a subfolder preserves the policy of its shared or system-managed ancestor.
        return standardLocations.first {
            $0.path == components[index + 1] && isReviewOnly($0.kind)
        } ?? custom
    }

    private mutating func scanDirectory(
        _ directory: URL, kind: UninstallCandidate.Kind, depth: Int, isLibraryRoot: Bool = false,
        required: Bool = false
    ) throws {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(Self.entryKeys))
        } catch {
            if required || !InstalledApplicationCatalog.isMissingFile(error) {
                unreadable.insert(directory)
            }
            return
        }

        for url in entries {
            try Task.checkCancellation()
            if isLibraryRoot && Self.standardRoots.contains(url.lastPathComponent) { continue }
            do {
                let values = try url.resourceValues(forKeys: Self.entryKeys)
                guard values.isSymbolicLink != true, url.pathExtension.lowercased() != "app" else { continue }
                if let evidence = try evidence(for: url, kind: kind, isDirectory: values.isDirectory == true) {
                    let file = try UninstallFile(at: url)
                    if candidates[file.url] == nil {
                        // Listing a container by name avoids opening protected data just to compute its size.
                        let canMeasure = !file.isDirectory || (kind != .container && kind != .sharedContainer)
                        candidates[file.url] = UninstallCandidate(
                            file: file, kind: kind, evidence: evidence,
                            disposition: disposition(for: kind, evidence: evidence),
                            size: canMeasure ? Self.size(of: file) : nil)
                    }
                } else if depth > 0 && values.isDirectory == true && values.isPackage != true && values.isHidden != true
                    && !url.lastPathComponent.hasPrefix(".")
                {
                    let child = try UninstallFile.directory(at: url.lastPathComponent, in: directory)
                    try scanDirectory(child, kind: kind, depth: depth - 1)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !InstalledApplicationCatalog.isMissingFile(error) {
                    unreadable.insert(url)
                }
            }
        }
    }

    private func evidence(
        for url: URL, kind: UninstallCandidate.Kind, isDirectory: Bool
    ) throws -> UninstallCandidate.Evidence? {
        let filename = url.lastPathComponent.lowercased()
        let name = filename.hasPrefix(".") ? String(filename.dropFirst()) : filename
        let parent = url.deletingLastPathComponent().lastPathComponent
        if kind == .sharedContainer && identity.groupIDs.contains(name) { return .applicationGroup }
        if let match = identity.exactIdentifierEvidence(
            for: name, isHostPreference: kind == .preference && parent == "ByHost")
        {
            return match
        }

        if kind == .service && !isDirectory && url.pathExtension.lowercased() == "plist" {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { return nil }
            let data = try Data(contentsOf: url)
            if let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let job = propertyList as? [String: Any]
            {
                var paths = job["ProgramArguments"] as? [String] ?? []
                if let program = job["Program"] as? String { paths.append(program) }
                if paths.contains(where: {
                    $0.hasPrefix("/")
                        && URL(filePath: $0).standardizedFileURL.pathComponents.starts(
                            with: application.url.pathComponents)
                }) {
                    return .launchProgram
                }
                if let label = (job["Label"] as? String)?.lowercased() {
                    if let match = identity.exactIdentifierEvidence(for: label) { return match }
                    if identity.matchesIdentifierVariant(label) { return .bundleIdentifierVariant }
                }
            }
        }
        if identity.matchesIdentifierVariant(name) { return .bundleIdentifierVariant }
        if !isDirectory, kind == .log, identity.matchesDiagnosticName(of: url) {
            return .diagnosticName
        }
        return identity.matchesName(of: url, isDirectory: isDirectory) ? .applicationName : nil
    }

    private func disposition(
        for kind: UninstallCandidate.Kind, evidence: UninstallCandidate.Evidence
    ) -> UninstallCandidate.Disposition {
        guard !hasOtherCopies, !Self.isReviewOnly(kind) else { return .reviewOnly }
        guard kind == .other else { return .optional }
        switch evidence {
        case .bundleIdentifier, .componentBundleIdentifier, .bundleIdentifierVariant: return .optional
        default: return .reviewOnly
        }
    }

    private static func isReviewOnly(_ kind: UninstallCandidate.Kind) -> Bool {
        kind == .sharedContainer || kind == .service || kind == .plugIn || kind == .receipt
    }

    private static func findUninstaller(for application: URL) -> URL? {
        let name = application.deletingPathExtension().lastPathComponent
        let parent = application.deletingLastPathComponent()
        let locations = [
            application.appending(path: "Contents/Resources/Uninstall.app"),
            parent.appending(path: "Uninstall \(name).app"),
            parent.appending(path: "\(name) Uninstaller.app"),
        ]
        return locations.first { Bundle(url: $0)?.executableURL != nil }
    }

    private static func size(of file: UninstallFile) -> Int64? {
        if !file.isDirectory {
            return (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        var complete = true
        let enumerator = FileManager.default.enumerator(at: file.url, includingPropertiesForKeys: Array(keys)) {
            _, _ in
            complete = false
            return false
        }
        guard let enumerator else { return nil }

        var total: Int64 = 0
        var entries = 0
        while let url = enumerator.nextObject() as? URL {
            entries += 1
            // Large app bundles can be reviewed before a full recursive size calculation would finish.
            guard !Task.isCancelled, entries <= 12_000, let values = try? url.resourceValues(forKeys: keys)
            else { return nil }
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return complete ? total : nil
    }
}

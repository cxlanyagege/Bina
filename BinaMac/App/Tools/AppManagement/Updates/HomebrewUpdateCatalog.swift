import Foundation
import OSLog

struct HomebrewCask: Decodable, Sendable {
    private struct Artifact: Decodable, Sendable {
        let source: String?
        let target: String?

        private enum CodingKeys: String, CodingKey { case app, target }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if var arguments = try? container.nestedUnkeyedContainer(forKey: .app) {
                source = try arguments.decode(String.self)
            } else {
                source = nil
            }
            target = try container.decodeIfPresent(String.self, forKey: .target)
        }
    }

    private let token: String
    private let fullToken: String?
    private let oldTokens: [String]?
    private let installed: String?
    private let version: String?
    private let autoUpdates: Bool?
    private let outdated: Bool?
    private let artifacts: [Artifact]

    private enum CodingKeys: String, CodingKey {
        case token, installed, version, outdated, artifacts
        case fullToken = "full_token"
        case oldTokens = "old_tokens"
        case autoUpdates = "auto_updates"
    }

    var publishedVersion: String? {
        guard let version, !version.isEmpty, version != "latest", version != ":latest" else { return nil }
        return version
    }

    var prefersSparkle: Bool { autoUpdates == true || publishedVersion == nil }

    func check(installedVersion: ApplicationVersion) -> ApplicationUpdateResult {
        let source = ApplicationUpdateResult.Source.homebrew(token: fullToken ?? token)
        let outcome: ApplicationUpdateResult.Outcome
        if let publishedVersion, let outdated {
            let release = ApplicationVersion(shortVersion: publishedVersion, buildVersion: nil)
            let isInstalled = matchesOrPrecedesInstalledVersion(publishedVersion, installedVersion: installedVersion)
            outcome = outdated && !isInstalled ? .available(release) : .noUpdate(release)
        } else {
            outcome = publishedVersion == nil ? .uncomparableVersion : .homebrewUnavailable
        }
        let localVersion =
            installedVersion.displayVersion == nil
            ? ApplicationVersion(shortVersion: installed, buildVersion: nil) : installedVersion
        return ApplicationUpdateResult(installedVersion: localVersion, source: source, outcome: outcome)
    }

    fileprivate func applicationPaths(in caskroom: URL) -> Set<String> {
        guard let installed, Self.isPathComponent(installed) else { return [] }
        let tokens = [token] + (oldTokens ?? []).compactMap { $0.split(separator: "/").last.map(String.init) }
        return Set(
            artifacts.compactMap { artifact in
                guard let source = artifact.source, URL(filePath: source).pathExtension.lowercased() == "app",
                    source.components(separatedBy: "/").allSatisfy(Self.isPathComponent)
                else { return nil }

                // The staged symlink records where Homebrew moved this installed version of the app.
                for token in tokens where Self.isPathComponent(token) {
                    let staged = caskroom.appending(path: token).appending(path: installed).appending(path: source)
                    if (try? staged.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                        return Self.applicationPath(staged)
                    }
                }

                guard let target = artifact.target, target.hasPrefix("/") else { return nil }
                return Self.applicationPath(URL(filePath: target))
            })
    }

    private func matchesOrPrecedesInstalledVersion(_ release: String, installedVersion: ApplicationVersion) -> Bool {
        guard let shortVersion = installedVersion.shortVersion else { return false }
        let parts = release.split(separator: ",", maxSplits: 1)
        guard let version = parts.first else { return false }
        if parts.count == 2, let build = installedVersion.buildVersion, release == "\(shortVersion),\(build)" {
            return true
        }
        if parts.count == 1, release == shortVersion { return true }
        guard let current = NumericApplicationVersion(shortVersion),
            let offered = NumericApplicationVersion(String(version))
        else { return false }
        return current > offered || (parts.count == 1 && current == offered)
    }

    private static func applicationPath(_ url: URL) -> String? {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: canonical.path)
        else { return nil }
        return canonical.path
    }

    private static func isPathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\0")
    }
}

/// Shares one installed-cask snapshot across all apps in a check request.
actor HomebrewUpdateCatalog {
    struct Snapshot: Sendable {
        let casksByPath: [String: HomebrewCask]
        let hadFailure: Bool

        init(casksByPath: [String: HomebrewCask] = [:], hadFailure: Bool = false) {
            self.casksByPath = casksByPath
            self.hadFailure = hadFailure
        }
    }

    private struct Inventory: Decodable { let casks: [HomebrewCask] }
    private static let logger = Logger(subsystem: "BinaMac", category: "HomebrewUpdateCheck")
    private let load: @Sendable () async -> Snapshot
    private var loading: Task<Snapshot, Never>?

    init(load: @escaping @Sendable () async -> Snapshot = HomebrewUpdateCatalog.loadInstalledCasks) {
        self.load = load
    }

    func snapshot() async -> Snapshot {
        if let loading { return await loading.value }
        let task = Task { [load] in await load() }
        loading = task
        return await task.value
    }

    static func snapshot(from inventory: Data, caskroom: URL) throws -> Snapshot {
        let entries = try entries(from: inventory, caskroom: caskroom)
        return Snapshot(casksByPath: uniqueCasks(in: entries))
    }

    @concurrent
    private static func loadInstalledCasks() async -> Snapshot {
        var entries: [(path: String, cask: HomebrewCask)] = []
        var hadFailure = false
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let directory = URL(filePath: prefix, directoryHint: .isDirectory)
            let brew = directory.appending(path: "bin/brew")
            let caskroom = directory.appending(path: "Caskroom", directoryHint: .isDirectory)
            guard FileManager.default.isExecutableFile(atPath: brew.path),
                FileManager.default.fileExists(atPath: caskroom.path)
            else { continue }
            do {
                let staged = try FileManager.default.contentsOfDirectory(atPath: caskroom.path)
                guard !staged.isEmpty else { continue }
                let data = try await HomebrewInventoryCommand.run(brew)
                entries.append(contentsOf: try Self.entries(from: data, caskroom: caskroom))
            } catch {
                if !Task.isCancelled {
                    logger.error("Could not read installed casks: \(String(describing: error), privacy: .private)")
                }
                hadFailure = true
            }
        }
        return Snapshot(casksByPath: uniqueCasks(in: entries), hadFailure: hadFailure)
    }

    private static func entries(from data: Data, caskroom: URL) throws -> [(path: String, cask: HomebrewCask)] {
        try JSONDecoder().decode(Inventory.self, from: data).casks.flatMap { cask in
            cask.applicationPaths(in: caskroom).map { (path: $0, cask: cask) }
        }
    }

    private static func uniqueCasks(in entries: [(path: String, cask: HomebrewCask)]) -> [String: HomebrewCask] {
        Dictionary(grouping: entries, by: \.path).compactMapValues { candidates in
            candidates.count == 1 ? candidates.first?.cask : nil
        }
    }
}

private enum HomebrewInventoryCommand {
    private enum CommandError: Error {
        case timedOut
        case unsuccessful(exitCode: Int32)
        case outputTooLarge
    }

    @concurrent
    static func run(_ brew: URL) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch {
                let logger = Logger(subsystem: "BinaMac", category: "HomebrewUpdateCheck")
                logger.error("Could not remove command output: \(error.localizedDescription, privacy: .private)")
            }
        }

        // A file keeps a full output pipe from blocking Homebrew while we wait for its exit status.
        let output = directory.appending(path: "inventory.json")
        try Data().write(to: output)
        let outputHandle = try FileHandle(forWritingTo: output)
        defer { outputHandle.closeFile() }

        let process = Process()
        process.executableURL = brew
        process.arguments = ["info", "--json=v2", "--installed", "--cask"]
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        process.environment = environment
        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        let (termination, signal) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { finished in
            signal.yield(finished.terminationStatus)
            signal.finish()
        }
        try Task.checkCancellation()
        try process.run()
        let deadline = Task {
            try await Task.sleep(for: .seconds(20))
            signal.finish()
        }
        defer {
            deadline.cancel()
            if process.isRunning { process.terminate() }
        }
        var status = termination.makeAsyncIterator()
        guard let exitCode = await status.next() else {
            try Task.checkCancellation()
            throw CommandError.timedOut
        }
        guard exitCode == 0 else { throw CommandError.unsuccessful(exitCode: exitCode) }
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8 * 1024 * 1024 else { throw CommandError.outputTooLarge }
        return try Data(contentsOf: output)
    }
}

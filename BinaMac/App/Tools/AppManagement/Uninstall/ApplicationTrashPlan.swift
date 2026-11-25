import Darwin
import Foundation

/// Identifies an item at its reviewed path. A fresh snapshot catches replacements and symbolic links before moving it.
struct UninstallFile: Equatable, Sendable {
    let url: URL
    let isDirectory: Bool
    private let device: dev_t
    private let inode: ino_t
    private let birthSeconds: Int
    private let birthNanoseconds: Int

    init(at url: URL) throws {
        let path = url.standardizedFileURL.path
        let absoluteURL = URL(filePath: path)
        guard url.isFileURL, absoluteURL.resolvingSymlinksInPath().path == path,
            !InstalledApplicationCatalog.isSystemApplicationURL(absoluteURL)
        else { throw UninstallFileError.unsafeLocation }

        let info = try Self.fileInfo(at: path)
        let type = info.st_mode & S_IFMT
        guard type == S_IFDIR || type == S_IFREG else { throw UninstallFileError.unsafeLocation }

        self.url = absoluteURL
        isDirectory = type == S_IFDIR
        device = info.st_dev
        inode = info.st_ino
        birthSeconds = info.st_birthtimespec.tv_sec
        birthNanoseconds = info.st_birthtimespec.tv_nsec
    }

    func validate() throws {
        guard try UninstallFile(at: url) == self else { throw UninstallFileError.changed }
    }

    func isInside(_ directory: URL) -> Bool {
        let components = directory.pathComponents
        let item = url.pathComponents
        return item.count > components.count && item.starts(with: components)
    }

    /// Walks a known relative path from a search root without following link entries inside it.
    static func directory(at relativePath: String, in root: URL) throws -> URL {
        var directory = root
        for part in relativePath.split(separator: "/") {
            guard part != "." && part != ".." else { throw UninstallFileError.unsafeLocation }
            directory = directory.appending(component: String(part), directoryHint: .isDirectory)
            let info = try fileInfo(at: directory.path)
            guard info.st_mode & S_IFMT == S_IFDIR else { throw UninstallFileError.unsafeLocation }
        }
        return directory
    }

    private static func fileInfo(at path: String) throws -> stat {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return info
    }
}

enum UninstallFileError: LocalizedError {
    case unsafeLocation
    case changed
    case outsideScope

    var errorDescription: String? {
        switch self {
        case .unsafeLocation: String(localized: "此位置无法安全处理。")
        case .changed: String(localized: "项目已更改，请重新打开卸载预览。")
        case .outsideScope: String(localized: "该项目已超出本次扫描的目录。")
        }
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain:
            return [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code)
        case NSPOSIXErrorDomain:
            return [Int(EACCES), Int(EPERM)].contains(error.code)
        default:
            return false
        }
    }
}

struct ApplicationTrashPlan: Sendable {
    struct Outcome: Identifiable, Sendable {
        enum Status: Sendable {
            case moved(destination: URL?)
            case failed(String)
            case skipped
        }

        let originalURL: URL
        let status: Status

        var id: URL { originalURL }

        var succeeded: Bool {
            if case .moved = status { return true }
            return false
        }
    }

    let application: UninstallFile
    let relatedItems: [UninstallCandidate]
    let scanDirectories: [URL]

    /// Moving a selected directory includes any selected descendants in its result and size.
    static func outermostItems(in candidates: [UninstallCandidate]) -> [UninstallCandidate] {
        let items = candidates.filter { $0.disposition != .reviewOnly }
        let directories = items.filter(\.file.isDirectory)
        return items.filter { item in
            !directories.contains { item.file.isInside($0.file.url) }
        }
    }

    @concurrent
    func execute(
        trash: @Sendable (URL) throws -> URL? = moveToTrash
    ) async -> [Outcome] {
        let outermost = Self.outermostItems(in: relatedItems).map(\.file)
        let appOutcome = move(application, using: trash) {
            guard application.isDirectory, application.url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                application.url.path != Bundle.main.bundleURL.resolvingSymlinksInPath().path
            else { throw UninstallFileError.unsafeLocation }
        }
        guard appOutcome.succeeded else {
            return [appOutcome] + outermost.map { Outcome(originalURL: $0.url, status: .skipped) }
        }

        return [appOutcome]
            + outermost.map { item in
                move(item, using: trash) {
                    guard scanDirectories.contains(where: item.isInside),
                        item.url.pathExtension.caseInsensitiveCompare("app") != .orderedSame
                    else { throw UninstallFileError.outsideScope }
                }
            }
    }

    private func move(
        _ file: UninstallFile, using trash: (URL) throws -> URL?, validate: () throws -> Void
    ) -> Outcome {
        do {
            try validate()
            try file.validate()
            return Outcome(originalURL: file.url, status: .moved(destination: try trash(file.url)))
        } catch {
            var reason = error.localizedDescription
            if file == application && UninstallFileError.isPermissionDenied(error) {
                reason += "\n" + String(localized: "如果 macOS 限制了此操作，请在「系统设置 → 隐私与安全性 → App 管理」中检查 Bina 的权限。")
            }
            return Outcome(originalURL: file.url, status: .failed(reason))
        }
    }

    private static func moveToTrash(_ url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }
}

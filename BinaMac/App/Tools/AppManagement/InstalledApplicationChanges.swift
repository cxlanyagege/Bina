import CoreServices
import Foundation
import OSLog

/// Observes the catalog's standard folders directly and uses Spotlight for other indexed locations.
@MainActor
final class InstalledApplicationChanges {
    private let directoryChanges: ApplicationDirectoryChanges
    private let indexQuery: NSMetadataQuery
    private let indexObserver: NSObjectProtocol

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        let directories = InstalledApplicationCatalog.applicationDirectories
        directoryChanges = ApplicationDirectoryChanges(directories: directories, onChange: onChange)
        indexQuery = InstalledApplicationCatalog.makeIndexQuery()
        let watchedPrefixes = directories.map { InstalledApplicationCatalog.logicalPath(of: $0) + "/" }
        indexObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: indexQuery, queue: .main
        ) { notification in
            let keys = [
                NSMetadataQueryUpdateAddedItemsKey, NSMetadataQueryUpdateRemovedItemsKey,
                NSMetadataQueryUpdateChangedItemsKey,
            ]
            let containsOtherApplication = keys.contains { key in
                guard let items = notification.userInfo?[key] as? [NSMetadataItem] else { return false }
                return items.contains { item in
                    guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                        InstalledApplicationCatalog.isListableApplicationURL(url)
                    else { return false }
                    let path = InstalledApplicationCatalog.logicalPath(of: url)
                    return !watchedPrefixes.contains(where: path.hasPrefix)
                }
            }
            if containsOtherApplication { MainActor.assumeIsolated { onChange() } }
        }
        if !indexQuery.start() {
            Logger(subsystem: "BinaMac", category: "ApplicationChanges")
                .notice("Spotlight could not start monitoring application changes")
        }
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(indexObserver)
        indexQuery.stop()
    }
}

/// Watches recursive bundle and directory changes without waiting for Spotlight to index them.
@MainActor
final class ApplicationDirectoryChanges {
    private final class Callback: Sendable {
        let onChange: @MainActor @Sendable (Bool) -> Void

        init(_ onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
            self.onChange = onChange
        }
    }

    private nonisolated static let structuralFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)

    private let directories: [URL]
    private let onChange: @MainActor @Sendable () -> Void
    private var stream: FSEventStreamRef?

    init(directories: [URL], onChange: @escaping @MainActor @Sendable () -> Void) {
        self.directories = directories
        self.onChange = onChange
        startStream()
    }

    isolated deinit {
        Self.stopStream(stream)
    }

    private func startStream() {
        let callback = Callback { [weak self] rootChanged in
            guard let self else { return }
            if rootChanged {
                // Reopen the stream after the callback so a newly created or replaced root is watched recursively.
                Task { [weak self] in self?.startStream() }
            }
            onChange()
        }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<Callback>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<Callback>.fromOpaque(pointer).release()
            },
            copyDescription: nil)
        let paths = directories.map(\.path) as CFArray
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        let newStream = FSEventStreamCreate(
            nil,
            { _, info, count, eventPaths, eventFlags, _ in
                guard let info else { return }
                let rootChanged = UnsafeBufferPointer(start: eventFlags, count: count).contains {
                    $0 & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
                }
                let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                let affectsCatalog = (0..<count).contains { index in
                    ApplicationDirectoryChanges.affectsCatalog(
                        path: String(cString: paths[index]), flags: eventFlags[index])
                }
                guard rootChanged || affectsCatalog else { return }
                let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { callback.onChange(rootChanged) }
            },
            &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25, flags)
        if let newStream {
            FSEventStreamSetDispatchQueue(newStream, .main)
            if FSEventStreamStart(newStream) {
                Self.stopStream(stream)
                stream = newStream
                return
            }
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
        }
        Logger(subsystem: "BinaMac", category: "ApplicationChanges")
            .error("Could not start monitoring the application folders")
    }

    private static func stopStream(_ stream: FSEventStreamRef?) {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private nonisolated static func affectsCatalog(path: String, flags: FSEventStreamEventFlags) -> Bool {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 { return true }

        let structureChanged = flags & structuralFlags != 0
        guard structureChanged || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 else {
            return false
        }
        let url = URL(filePath: path)
        if InstalledApplicationCatalog.isListableApplicationURL(url) { return true }

        let parent = url.deletingLastPathComponent()
        if url.lastPathComponent == "Info.plist" {
            let bundle = parent.lastPathComponent == "Contents" ? parent.deletingLastPathComponent() : parent
            return InstalledApplicationCatalog.isListableApplicationURL(bundle)
        }
        if url.lastPathComponent == "Contents", InstalledApplicationCatalog.isListableApplicationURL(parent) {
            return structureChanged
        }

        // Moving a plain folder can move multiple apps without reporting individual bundle events.
        return structureChanged && flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
            && url.pathComponents.allSatisfy { component in
                let pathExtension = (component as NSString).pathExtension.lowercased()
                return !component.hasPrefix(".")
                    && !InstalledApplicationCatalog.packageExtensions.contains(pathExtension)
            }
    }
}

import Foundation

@MainActor
protocol MemoryPersisting {
    func load() throws -> MemoryDocument
    func save(_ document: MemoryDocument) throws
}

/// Uses an independent file so memory failures cannot overwrite spatial-placement metadata.
@MainActor
final class FileMemoryStore: MemoryPersisting {
    static let maximumBytes = 524_288
    private let explicitFileURL: URL?

    init(fileURL: URL? = nil) {
        explicitFileURL = fileURL
    }

    func load() throws -> MemoryDocument {
        let url = try fileURL()
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumBytes else { throw MemoryFailure.fileTooLarge }
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return MemoryDocument()
        }
        guard data.count <= Self.maximumBytes else { throw MemoryFailure.fileTooLarge }
        let document = try JSONDecoder().decode(MemoryDocument.self, from: data)
        try document.validate()
        return document
    }

    func save(_ document: MemoryDocument) throws {
        try document.validate()
        let data = try JSONEncoder().encode(document)
        guard data.count <= Self.maximumBytes else { throw MemoryFailure.fileTooLarge }
        let destination = try fileURL()
        var directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Exclude the containing directory before committing any private content.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
    }

    private func fileURL() throws -> URL {
        if let explicitFileURL { return explicitFileURL }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MemoryFailure.unavailable
        }
        return support.appendingPathComponent("Bina/Conversation", isDirectory: true)
            .appendingPathComponent("confirmed-memories.json")
    }
}

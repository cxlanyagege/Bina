import Foundation

struct SavedPlacement: Codable, Equatable {
    let schemaVersion: Int
    let anchorID: UUID
    let createdAt: Date

    init(anchorID: UUID, createdAt: Date = Date()) {
        schemaVersion = 1
        self.anchorID = anchorID
        self.createdAt = createdAt
    }
}

@MainActor
protocol PlacementPersisting {
    func load() throws -> SavedPlacement?
    func save(_ placement: SavedPlacement) throws
    func clear() throws
}

enum PlacementStorageError: LocalizedError, Equatable {
    case applicationSupportUnavailable
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The application support directory is unavailable."
        case .unsupportedSchema(let version):
            return "Saved placement uses unsupported format version \(version)."
        }
    }
}

/// Stores the meaning of an ARKit anchor, never a cached world-space transform.
@MainActor
final class FilePlacementStore: PlacementPersisting {
    private let explicitFileURL: URL?

    init(fileURL: URL) {
        explicitFileURL = fileURL
    }

    init() {
        explicitFileURL = nil
    }

    func load() throws -> SavedPlacement? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL())
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }

        let placement = try JSONDecoder().decode(SavedPlacement.self, from: data)
        try validate(placement)
        return placement
    }

    func save(_ placement: SavedPlacement) throws {
        try validate(placement)
        let destination = try fileURL()
        let data = try JSONEncoder().encode(placement)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    func clear() throws {
        do {
            try FileManager.default.removeItem(at: fileURL())
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func fileURL() throws -> URL {
        if let explicitFileURL {
            return explicitFileURL
        }
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PlacementStorageError.applicationSupportUnavailable
        }
        return directory.appendingPathComponent("Bina", isDirectory: true)
            .appendingPathComponent("spatial-placement.json")
    }

    private func validate(_ placement: SavedPlacement) throws {
        guard placement.schemaVersion == 1 else {
            throw PlacementStorageError.unsupportedSchema(placement.schemaVersion)
        }
    }
}

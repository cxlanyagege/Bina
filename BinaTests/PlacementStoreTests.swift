import Foundation
import Testing
@testable import Bina

@MainActor
struct PlacementStoreTests {
    @Test func missingFileHasNoSavedPlacement() throws {
        try withTemporaryDirectory { directory in
            let store = FilePlacementStore(fileURL: directory.appendingPathComponent("missing.json"))
            let restored = try store.load()
            #expect(restored == nil)
        }
    }

    @Test func savesAndRestoresAnchorMetadata() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("nested/placement.json")
            let placement = SavedPlacement(
                anchorID: UUID(),
                createdAt: Date(timeIntervalSince1970: 1_750_000_000)
            )
            try FilePlacementStore(fileURL: url).save(placement)

            let restored = try FilePlacementStore(fileURL: url).load()
            #expect(restored == placement)
            #expect(restored?.schemaVersion == 1)
            let data = try Data(contentsOf: url)
            let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let object = try #require(decoded)
            #expect(Set(object.keys) == Set(["schemaVersion", "anchorID", "createdAt"]))
        }
    }

    @Test func replacesExistingMetadata() throws {
        try withTemporaryDirectory { directory in
            let store = FilePlacementStore(fileURL: directory.appendingPathComponent("placement.json"))
            try store.save(SavedPlacement(anchorID: UUID()))
            let replacement = SavedPlacement(anchorID: UUID())
            try store.save(replacement)
            let restored = try store.load()
            #expect(restored == replacement)
        }
    }

    @Test func legacyPlacementKeepsItsOriginalOriginSemantics() throws {
        let id = UUID()
        let data = Data("{\"schemaVersion\":1,\"anchorID\":\"\(id)\",\"createdAt\":0}".utf8)
        let placement = try JSONDecoder().decode(SavedPlacement.self, from: data)
        #expect(placement.anchorID == id)
        #expect(placement.alignment == nil)
    }

    @Test func groundedPlacementPersistsOnlyItsAnchorAndSoleAlignment() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("grounded.json")
            let placement = SavedPlacement(anchorID: UUID(), alignment: .soleContact)
            let store = FilePlacementStore(fileURL: url)
            try store.save(placement)
            let restored = try store.load()
            #expect(restored == placement)
            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String:Any])
            #expect(Set(object.keys) == Set(["schemaVersion","anchorID","createdAt","alignment"]))
            #expect(object["alignment"] as? String == "soleContact")
        }
    }

    @Test func unknownAlignmentIsReportedWithoutDeletingTheRecord() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("unknown-alignment.json")
            let data = Data("{\"schemaVersion\":1,\"anchorID\":\"\(UUID())\",\"createdAt\":0,\"alignment\":\"future\"}".utf8)
            try data.write(to: url)
            #expect(throws: DecodingError.self) { try FilePlacementStore(fileURL: url).load() }
            let retained = try Data(contentsOf: url)
            #expect(retained == data)
        }
    }

    @Test func corruptedFileIsReportedAndPreserved() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("placement.json")
            let corruptData = Data("not valid JSON".utf8)
            try corruptData.write(to: url)
            let store = FilePlacementStore(fileURL: url)

            #expect(throws: DecodingError.self) { try store.load() }
            let retainedData = try Data(contentsOf: url)
            #expect(retainedData == corruptData)
        }
    }

    @Test func unsupportedSchemaIsReportedAndPreserved() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("placement.json")
            let source = "{\"schemaVersion\":2,\"anchorID\":\"\(UUID().uuidString)\",\"createdAt\":0}"
            let data = Data(source.utf8)
            try data.write(to: url)
            let store = FilePlacementStore(fileURL: url)

            #expect(throws: PlacementStorageError.unsupportedSchema(2)) { try store.load() }
            let retainedData = try Data(contentsOf: url)
            #expect(retainedData == data)
        }
    }

    @Test func writeFailureDoesNotReplaceBlockingFile() throws {
        try withTemporaryDirectory { directory in
            let blocker = directory.appendingPathComponent("blocking-file")
            let original = Data("keep this data".utf8)
            try original.write(to: blocker)
            let store = FilePlacementStore(fileURL: blocker.appendingPathComponent("placement.json"))

            #expect(throws: (any Error).self) { try store.save(SavedPlacement(anchorID: UUID())) }
            let retainedData = try Data(contentsOf: blocker)
            #expect(retainedData == original)
        }
    }

    @Test func clearRemovesSavedPlacementAndIsIdempotent() throws {
        try withTemporaryDirectory { directory in
            let store = FilePlacementStore(fileURL: directory.appendingPathComponent("placement.json"))
            try store.save(SavedPlacement(anchorID: UUID()))
            try store.clear()
            let afterClear = try store.load()
            #expect(afterClear == nil)
            try store.clear()
            let afterRepeatedClear = try store.load()
            #expect(afterRepeatedClear == nil)
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BinaPlacementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

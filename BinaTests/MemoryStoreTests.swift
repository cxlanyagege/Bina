import Foundation
import Testing
@testable import Bina

@MainActor
struct MemoryStoreTests {
    @Test func missingFileLoadsAnEmptyVersionedStore() throws {
        try withDirectory { directory in
            let store = FileMemoryStore(fileURL: directory.appendingPathComponent("missing.json"))
            let document = try store.load()
            #expect(document == MemoryDocument())
        }
    }

    @Test func confirmedMemorySurvivesAStoreAndLibraryRestart() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("nested/memory.json")
            let first = MemoryLibrary(store: FileMemoryStore(fileURL: url))
            let candidate = try ConversationFixture.candidate()
            try first.confirm(candidate, topic: candidate.topic, content: candidate.content)
            let restored = MemoryLibrary(store: FileMemoryStore(fileURL: url))
            #expect(restored.isAvailable)
            #expect(restored.records == first.records)
            #expect(restored.retrieve(for: "我平时爱喝什么？").first?.content == candidate.content)
            let excluded = try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(excluded.isExcludedFromBackup == true)
        }
    }

    @Test func deletionAndClearPersistAcrossRestart() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("memory.json")
            let store = FileMemoryStore(fileURL: url)
            try store.save(MemoryDocument(records: [ConversationFixture.record()]))
            let library = MemoryLibrary(store: store)
            try library.delete(try #require(library.records.first?.id))
            let deleted = try FileMemoryStore(fileURL: url).load()
            #expect(deleted.records.isEmpty)
            try store.save(MemoryDocument(records: [ConversationFixture.record()]))
            library.reload()
            try library.clearAndRebuild()
            let cleared = try FileMemoryStore(fileURL: url).load()
            #expect(cleared.records.isEmpty)
        }
    }

    @Test func damagedOrFutureDataIsPreservedUntilExplicitRebuild() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("memory.json")
            for data in [Data("broken".utf8), Data(#"{"schemaVersion":2,"records":[]}"#.utf8)] {
                try data.write(to: url)
                let library = MemoryLibrary(store: FileMemoryStore(fileURL: url))
                #expect(!library.isAvailable)
                let candidate = try ConversationFixture.candidate()
                #expect(throws: MemoryFailure.unavailable) {
                    try library.confirm(candidate, topic: candidate.topic, content: candidate.content)
                }
                let preserved = try Data(contentsOf: url)
                #expect(preserved == data)
                try library.clearAndRebuild()
                #expect(library.isAvailable)
                let rebuilt = try FileMemoryStore(fileURL: url).load()
                #expect(rebuilt == MemoryDocument())
            }
        }
    }

    @Test func oversizedFileIsNotLoadedOrOverwritten() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("memory.json")
            let data = Data(repeating: 32, count: FileMemoryStore.maximumBytes + 1)
            try data.write(to: url)
            #expect(throws: MemoryFailure.fileTooLarge) { try FileMemoryStore(fileURL: url).load() }
            let preserved = try Data(contentsOf: url)
            #expect(preserved == data)
        }
    }

    @Test func invalidSaveCannotReplaceAValidFile() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("memory.json")
            let store = FileMemoryStore(fileURL: url)
            let record = ConversationFixture.record()
            let original = MemoryDocument(records: [record])
            try store.save(original)
            #expect(throws: MemoryFailure.duplicateTopic) { try store.save(MemoryDocument(records: [record, record])) }
            let restored = try store.load()
            #expect(restored == original)
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Bina-Memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

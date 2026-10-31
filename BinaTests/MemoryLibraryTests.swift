import Foundation
import Testing
@testable import Bina

@MainActor
struct MemoryLibraryTests {
    @Test func candidateRequiresAnExactUserQuote() throws {
        let candidate = try ConversationFixture.candidate()
        #expect(candidate.evidenceQuote == "我喜欢清淡的绿茶")
        #expect(candidate.sourceText == ConversationFixture.source)
        #expect(throws: MemoryFailure.invalidEvidence) {
            try MemoryCandidate.decode(ConversationFixture.extracted, sourceID: UUID(), sourceText: "今天天气不错。")
        }
    }

    @Test func nullCandidateDoesNotCreateAMemory() throws {
        let candidate = try MemoryCandidate.decode(#"{"memory":null}"#, sourceID: UUID(), sourceText: "你好")
        #expect(candidate == nil)
    }

    @Test func missingOrUnexpectedSchemaFieldsAreNotSilentlyAccepted() throws {
        for text in [#"{}"#, #"{"memory":null,"extra":true}"#, #"{"memory":{"topic":"x","content":"x","evidence_quote":"x","extra":true}}"#] {
            #expect(throws: MemoryFailure.invalidRecord) { try MemoryCandidate.decode(text, sourceID: UUID(), sourceText: "x") }
        }
    }

    @Test func invalidCandidateTypesAndLengthsAreRejected() throws {
        #expect(throws: (any Error).self) {
            try MemoryCandidate.decode(#"{"memory":{"topic":12,"content":"x","evidence_quote":"x"}}"#, sourceID: UUID(), sourceText: "x")
        }
        let value: [String: Any] = ["memory": ["topic": String(repeating: "t", count: 61), "content": "x", "evidence_quote": "x"]]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        #expect(throws: MemoryFailure.invalidRecord) { try MemoryCandidate.decode(text, sourceID: UUID(), sourceText: "x") }
    }

    @Test func confirmationPublishesOnlyAfterSuccessfulSave() throws {
        let store = TestMemoryStore()
        let library = MemoryLibrary(store: store)
        let candidate = try ConversationFixture.candidate()
        #expect(library.records.isEmpty)
        try library.confirm(candidate, topic: candidate.topic, content: candidate.content)
        #expect(store.saveCount == 1)
        let record = try #require(library.records.first)
        #expect(record.content == candidate.content)
        #expect(record.evidence.sourceUtteranceID == candidate.sourceUtteranceID)
        #expect(record.evidence.quote == candidate.evidenceQuote)
        #expect(record.evidence.origin == .confirmedUtterance)
    }

    @Test func failurePreservesRecordsAndRevision() throws {
        let store = TestMemoryStore()
        store.document = MemoryDocument(records: [ConversationFixture.record()])
        let library = MemoryLibrary(store: store)
        let revision = library.revision
        let before = library.records
        store.saveError = MemoryFailure.unavailable
        #expect(throws: MemoryFailure.unavailable) { try library.delete(before[0].id) }
        #expect(library.records == before)
        #expect(library.revision == revision)
    }

    @Test func correctionReplacesBothOldContentAndOldEvidence() throws {
        let store = TestMemoryStore()
        store.document = MemoryDocument(records: [ConversationFixture.record()])
        let library = MemoryLibrary(store: store)
        let old = try #require(library.records.first)
        try library.correct(old.id, expectedRevision: old.revision, topic: old.topic, content: "用户现在更喜欢白开水。")
        let current = try #require(library.records.first)
        #expect(current.id == old.id)
        #expect(current.revision == old.revision + 1)
        #expect(current.createdAt == old.createdAt)
        #expect(current.evidence.origin == .manualCorrection)
        #expect(current.evidence.quote == current.content)
        #expect(current.evidence.sourceUtteranceID == nil)
        #expect(!String(decoding: try JSONEncoder().encode(store.document), as: UTF8.self).contains(old.content))
    }

    @Test func aMatchingTopicRequiresExplicitReplacement() throws {
        let store = TestMemoryStore()
        store.document = MemoryDocument(records: [ConversationFixture.record()])
        let library = MemoryLibrary(store: store)
        let candidate = try ConversationFixture.candidate()
        #expect(throws: MemoryFailure.duplicateTopic) {
            try library.confirm(candidate, topic: " 饮品偏好 ", content: "更喜欢白开水。")
        }
        let id = try #require(library.records.first?.id)
        try library.confirm(candidate, topic: candidate.topic, content: "更喜欢白开水。", replacing: id)
        #expect(library.records.count == 1)
        #expect(library.records.first?.id == id)
        #expect(library.records.first?.revision == 2)
    }

    @Test func anObsoleteEditorCannotOverwriteANewerCorrection() throws {
        let store = TestMemoryStore()
        let old = ConversationFixture.record()
        store.document = MemoryDocument(records: [old])
        let library = MemoryLibrary(store: store)
        try library.correct(old.id, expectedRevision: old.revision, topic: old.topic, content: "新的偏好")
        #expect(throws: MemoryFailure.staleRevision) {
            try library.correct(old.id, expectedRevision: old.revision, topic: old.topic, content: "旧窗口的内容")
        }
        #expect(library.records.first?.content == "新的偏好")
        #expect(store.saveCount == 1)
    }

    @Test func missingReplacementCannotBecomeAnUnrelatedNewRecord() throws {
        let library = MemoryLibrary(store: TestMemoryStore())
        let candidate = try ConversationFixture.candidate()
        #expect(throws: MemoryFailure.invalidRecord) {
            try library.confirm(candidate, topic: candidate.topic, content: candidate.content, replacing: UUID())
        }
    }

    @Test func retrievalIsBoundedAndRanksLocalMatches() throws {
        let store = TestMemoryStore()
        store.document = MemoryDocument(records: (0..<12).map {
            ConversationFixture.record(topic: "主题\($0)", content: "偏好\($0)", date: Date(timeIntervalSince1970: Double(100 + $0)))
        })
        let library = MemoryLibrary(store: store)
        let selected = library.retrieve(for: "偏好4")
        #expect(selected.count == 8)
        #expect(selected.first?.content == "偏好4")
        #expect(library.retrieve(for: "unrelated", limit: 1).first?.content == "偏好11")
        #expect(library.retrieve(for: "x", limit: -1).isEmpty)
    }

    @Test func deletionRemovesTheFactAndItsEvidenceFromSavedData() throws {
        let store = TestMemoryStore()
        store.document = MemoryDocument(records: [ConversationFixture.record()])
        let library = MemoryLibrary(store: store)
        try library.delete(try #require(library.records.first?.id))
        #expect(library.records.isEmpty)
        #expect(library.retrieve(for: "喜欢什么").isEmpty)
        #expect(store.document.records.isEmpty)
    }

    @Test func unavailableStoreDoesNotAcceptWrites() throws {
        let store = TestMemoryStore()
        store.loadError = MemoryFailure.unsupportedVersion(2)
        let library = MemoryLibrary(store: store)
        let candidate = try ConversationFixture.candidate()
        #expect(!library.isAvailable)
        #expect(library.availabilityMessage != nil)
        #expect(throws: MemoryFailure.unavailable) {
            try library.confirm(candidate, topic: candidate.topic, content: candidate.content)
        }
        #expect(store.saveCount == 0)
    }

    @Test func capacityAndMalformedEvidenceAreRejectedBeforeWriting() throws {
        let store = TestMemoryStore()
        store.document = MemoryDocument(records: (0..<100).map { ConversationFixture.record(topic: "Topic \($0)") })
        let library = MemoryLibrary(store: store)
        let candidate = try ConversationFixture.candidate()
        #expect(throws: MemoryFailure.capacityReached) {
            try library.confirm(candidate, topic: candidate.topic, content: candidate.content)
        }
        #expect(store.saveCount == 0)
        var malformed = store.document.records
        let old = malformed.removeLast()
        malformed.append(MemoryRecord(
            id: old.id, revision: 0, topic: old.topic, content: old.content,
            createdAt: old.createdAt, updatedAt: old.updatedAt, evidence: old.evidence
        ))
        #expect(throws: MemoryFailure.invalidRecord) { try MemoryDocument(records: malformed).validate() }
    }
}

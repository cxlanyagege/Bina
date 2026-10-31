import Foundation
import Testing
@testable import Bina

@MainActor
final class TestMemoryStore: MemoryPersisting {
    var document = MemoryDocument()
    var loadError: Error?
    var saveError: Error?
    var saveCount = 0

    func load() throws -> MemoryDocument {
        if let loadError { throw loadError }
        return document
    }

    func save(_ document: MemoryDocument) throws {
        if let saveError { throw saveError }
        self.document = document
        saveCount += 1
    }
}

@MainActor
final class TestAPIKeyStore: APIKeyPersisting {
    var key: String? = "sk-fixture-key-only"
    var error: Error?

    func load() throws -> String? {
        if let error { throw error }
        return key
    }
    func save(_ key: String) throws {
        if let error { throw error }
        self.key = key
    }
    func remove() throws {
        if let error { throw error }
        key = nil
    }
}

@MainActor
final class ScriptedConversationService: ConversationServing {
    var requests: [ConversationRequest] = []
    var continuations: [AsyncThrowingStream<ConversationEvent, Error>.Continuation] = []
    var terminated: Set<Int> = []

    func stream(_ request: ConversationRequest, apiKey: String) -> AsyncThrowingStream<ConversationEvent, Error> {
        requests.append(request)
        let index = continuations.count
        return AsyncThrowingStream { continuation in
            continuations.append(continuation)
            continuation.onTermination = { @Sendable [weak self] _ in
                guard let owner = self else { return }
                Task { @MainActor in owner.terminated.insert(index) }
            }
        }
    }

    func complete(_ text: String, at index: Int? = nil) {
        let continuation = continuations[index ?? (continuations.count - 1)]
        continuation.yield(.text(text))
        continuation.finish()
    }
}

@MainActor
enum ConversationFixture {
    static let source = "我喜欢清淡的绿茶，不喜欢很甜的饮料。"
    static let extracted = #"{"memory":{"topic":"饮品偏好","content":"用户喜欢清淡的绿茶。","evidence_quote":"我喜欢清淡的绿茶"}}"#

    static func candidate() throws -> MemoryCandidate {
        let result = try MemoryCandidate.decode(extracted, sourceID: UUID(), sourceText: source)
        return try #require(result)
    }

    static func record(topic: String = "饮品偏好", content: String = "用户喜欢清淡的绿茶。", date: Date = Date(timeIntervalSince1970: 100)) -> MemoryRecord {
        MemoryRecord(
            id: UUID(), revision: 1, topic: topic, content: content,
            createdAt: date, updatedAt: date,
            evidence: MemoryEvidence(origin: .confirmedUtterance, sourceUtteranceID: UUID(), quote: "我喜欢清淡的绿茶", recordedAt: date)
        )
    }

    static func preferences() -> UserDefaults {
        UserDefaults(suiteName: "Bina.Tests.Conversation.\(UUID().uuidString)")!
    }

    static func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the scripted operation.")
        throw FixtureTimeout()
    }

    struct FixtureTimeout: Error {}
}

import Foundation
import Observation

@MainActor
@Observable
final class MemoryLibrary {
    private(set) var records: [MemoryRecord] = []
    private(set) var revision = UUID()
    private(set) var loadFailure: Error?
    private(set) var isLoaded = false
    @ObservationIgnored private let store: any MemoryPersisting

    init(store: any MemoryPersisting) {
        self.store = store
        reload()
    }

    var isAvailable: Bool { isLoaded && loadFailure == nil }

    var availabilityMessage: String? {
        guard let loadFailure else { return nil }
        return (loadFailure as? MemoryFailure)?.userMessage
            ?? "无法读取本地记忆，原文件未被覆盖。可重试读取或在记忆页清空重建。"
    }

    func reload() {
        do {
            let document = try store.load()
            try document.validate()
            records = document.records
            loadFailure = nil
            isLoaded = true
        } catch {
            records = []
            loadFailure = error
            isLoaded = false
        }
        revision = UUID()
    }

    func confirm(
        _ candidate: MemoryCandidate, topic: String, content: String,
        replacing recordID: UUID? = nil, now: Date = Date()
    ) throws {
        guard isAvailable else { throw MemoryFailure.unavailable }
        guard candidate.sourceText.contains(candidate.evidenceQuote) else { throw MemoryFailure.invalidEvidence }
        let topic = try MemoryText.checked(topic, maximum: 60, multiline: false)
        let content = try MemoryText.checked(content, maximum: 300)
        var updated = records
        let previous = recordID.flatMap { id in records.first { $0.id == id } }
        guard recordID == nil || previous != nil else { throw MemoryFailure.invalidRecord }
        let record = MemoryRecord(
            id: previous?.id ?? UUID(), revision: (previous?.revision ?? 0) + 1,
            topic: topic, content: content, createdAt: previous?.createdAt ?? now, updatedAt: now,
            evidence: MemoryEvidence(
                origin: .confirmedUtterance, sourceUtteranceID: candidate.sourceUtteranceID,
                quote: candidate.evidenceQuote, recordedAt: now
            )
        )
        updated.removeAll { $0.id == record.id }
        updated.append(record)
        try commit(updated)
    }

    func correct(_ id: UUID, expectedRevision: Int, topic: String, content: String, now: Date = Date()) throws {
        guard isAvailable, let old = records.first(where: { $0.id == id }) else { throw MemoryFailure.unavailable }
        guard old.revision == expectedRevision else { throw MemoryFailure.staleRevision }
        let topic = try MemoryText.checked(topic, maximum: 60, multiline: false)
        let content = try MemoryText.checked(content, maximum: 300)
        let replacement = MemoryRecord(
            id: old.id, revision: old.revision + 1, topic: topic, content: content,
            createdAt: old.createdAt, updatedAt: now,
            evidence: MemoryEvidence(origin: .manualCorrection, sourceUtteranceID: nil, quote: content, recordedAt: now)
        )
        try commit(records.map { $0.id == id ? replacement : $0 })
    }

    func delete(_ id: UUID) throws {
        guard isAvailable else { throw MemoryFailure.unavailable }
        try commit(records.filter { $0.id != id })
    }

    /// Explicit recovery is allowed even after an unsupported or damaged file failed to load.
    func clearAndRebuild() throws {
        try commit([])
        isLoaded = true
        loadFailure = nil
    }

    func matchingTopic(_ topic: String) -> MemoryRecord? {
        records.first { MemoryText.topicKey($0.topic) == MemoryText.topicKey(topic) }
    }

    func retrieve(for query: String, limit: Int = 8) -> [MemoryRecord] {
        guard isAvailable else { return [] }
        let queryTerms = Self.terms(query)
        return records.sorted { left, right in
            let leftScore = queryTerms.intersection(Self.terms(left.topic + left.content)).count
            let rightScore = queryTerms.intersection(Self.terms(right.topic + right.content)).count
            if leftScore != rightScore { return leftScore > rightScore }
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id.uuidString < right.id.uuidString
        }.prefix(max(0, min(limit, 8))).map { $0 }
    }

    private static func terms(_ text: String) -> Set<String> {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(words.flatMap { word -> [String] in
            let characters = Array(word)
            guard characters.count > 1 else { return [String(word)] }
            return [String(word)] + zip(characters, characters.dropFirst()).map { String([$0, $1]) }
        })
    }

    private func commit(_ records: [MemoryRecord]) throws {
        let document = MemoryDocument(records: records)
        try document.validate()
        try store.save(document)
        // Publish only after an atomic save succeeds; failed mutations preserve the current view.
        self.records = records
        revision = UUID()
    }
}

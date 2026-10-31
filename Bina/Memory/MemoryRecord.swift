import Foundation

enum MemoryFailure: Error, Equatable {
    case invalidRecord
    case invalidEvidence
    case duplicateTopic
    case capacityReached
    case unavailable
    case unsupportedVersion(Int)
    case fileTooLarge
    case staleRevision

    var userMessage: String {
        switch self {
        case .invalidRecord: return "记忆主题或内容无效，请检查长度和文字。"
        case .invalidEvidence: return "记忆建议缺少这句话中的有效依据，未保存。"
        case .duplicateTopic: return "已有相同主题的记忆，请选择替换或修改主题。"
        case .capacityReached: return "首版最多保存 100 条记忆，请先整理已有记录。"
        case .unavailable: return "本地记忆暂不可用，请先重试读取或清空重建。"
        case .unsupportedVersion: return "记忆文件来自暂不支持的版本，未覆盖原文件。"
        case .fileTooLarge: return "记忆文件超出首版大小限制，未覆盖原文件。"
        case .staleRevision: return "这条记忆已被修改，请重新打开后再编辑。"
        }
    }
}

enum MemoryText {
    static func checked(_ text: String, maximum: Int, multiline: Bool = true) throws -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= maximum,
              !result.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
                      && !(multiline && ($0 == "\n" || $0 == "\t"))
              }) else { throw MemoryFailure.invalidRecord }
        return result
    }

    static func topicKey(_ topic: String) -> String {
        topic.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace }
    }
}

struct MemoryEvidence: Codable, Equatable {
    enum Origin: String, Codable { case confirmedUtterance, manualCorrection }
    let origin: Origin
    let sourceUtteranceID: UUID?
    let quote: String
    let recordedAt: Date
}

/// A current, explicitly confirmed fact. Correction replaces content rather than retaining hidden history.
struct MemoryRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let revision: Int
    let topic: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let evidence: MemoryEvidence

    func validate() throws {
        _ = try MemoryText.checked(topic, maximum: 60, multiline: false)
        _ = try MemoryText.checked(content, maximum: 300)
        _ = try MemoryText.checked(evidence.quote, maximum: 400)
        guard revision > 0,
              createdAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince1970.isFinite,
              evidence.recordedAt.timeIntervalSince1970.isFinite,
              updatedAt >= createdAt,
              evidence.origin != .confirmedUtterance || evidence.sourceUtteranceID != nil else {
            throw MemoryFailure.invalidRecord
        }
    }
}

struct MemoryDocument: Codable, Equatable {
    let schemaVersion: Int
    let records: [MemoryRecord]

    init(records: [MemoryRecord] = []) {
        schemaVersion = 1
        self.records = records
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw MemoryFailure.unsupportedVersion(schemaVersion) }
        guard records.count <= 100 else { throw MemoryFailure.capacityReached }
        guard Set(records.map(\.id)).count == records.count,
              Set(records.map { MemoryText.topicKey($0.topic) }).count == records.count else {
            throw MemoryFailure.duplicateTopic
        }
        for record in records { try record.validate() }
    }
}

struct MemoryCandidate: Identifiable, Equatable {
    let id: UUID
    let sourceUtteranceID: UUID
    let sourceText: String
    let topic: String
    let content: String
    let evidenceQuote: String
    let proposedAt: Date

    /// Only the selected user utterance can supply evidence; model prose is never evidence.
    static func decode(_ text: String, sourceID: UUID, sourceText: String, now: Date = Date()) throws -> Self? {
        struct Response: Decodable {
            struct Fact: Decodable {
                let topic: String
                let content: String
                let evidence_quote: String
            }
            let memory: Fact?
        }
        guard text.utf8.count <= 16_384 else { throw MemoryFailure.invalidRecord }
        let data = Data(text.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["memory"] else { throw MemoryFailure.invalidRecord }
        if let fact = object["memory"] as? [String: Any], Set(fact.keys) != ["topic", "content", "evidence_quote"] {
            throw MemoryFailure.invalidRecord
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let fact = response.memory else { return nil }
        let topic = try MemoryText.checked(fact.topic, maximum: 60, multiline: false)
        let content = try MemoryText.checked(fact.content, maximum: 300)
        let quote = try MemoryText.checked(fact.evidence_quote, maximum: 400)
        guard sourceText.contains(quote) else { throw MemoryFailure.invalidEvidence }
        return Self(
            id: UUID(), sourceUtteranceID: sourceID, sourceText: sourceText,
            topic: topic, content: content, evidenceQuote: quote, proposedAt: now
        )
    }
}

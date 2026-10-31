import Foundation

/// Incremental SSE framing, independent of URLSession and UI state.
struct MiMoSSEDecoder {
    private(set) var isDone = false
    private var dataLines: [String] = []
    private var eventBytes = 0
    private var totalBytes = 0
    private var visibleText = ""
    private var finishReason: String?

    mutating func accept(_ line: String) throws -> [ConversationEvent] {
        guard !isDone else { return [] }
        totalBytes += line.utf8.count
        guard totalBytes <= 1_048_576, line.utf8.count <= 65_536 else { throw ConversationFailure.malformedResponse }
        if line.isEmpty { return try flushEvent() }
        if line.hasPrefix(":") { return [] }
        guard line == "data" || line.hasPrefix("data:") else { return [] }
        var value = line == "data" ? "" : String(line.dropFirst(5))
        if value.first == " " { value.removeFirst() }
        eventBytes += value.utf8.count
        guard eventBytes <= 65_536 else { throw ConversationFailure.malformedResponse }
        dataLines.append(value)
        return []
    }

    mutating func finish() throws -> [ConversationEvent] {
        let final = try flushEvent()
        guard finishReason == "stop" else { throw ConversationFailure.incompleteResponse }
        guard !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversationFailure.emptyResponse
        }
        return final
    }

    private mutating func flushEvent() throws -> [ConversationEvent] {
        guard !dataLines.isEmpty else { return [] }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        eventBytes = 0
        if payload == "[DONE]" {
            isDone = true
            return []
        }
        let data = Data(payload.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConversationFailure.malformedResponse
        }
        if object["error"] != nil { throw ConversationFailure.providerRejected }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.choices != nil || envelope.usage != nil else {
            throw ConversationFailure.malformedResponse
        }
        var events: [ConversationEvent] = []
        let choices = envelope.choices ?? []
        guard choices.count <= 1 else { throw ConversationFailure.unsupportedOutput }
        if let choice = choices.first {
            guard choice.index == nil || choice.index == 0 else { throw ConversationFailure.unsupportedOutput }
            if let refusal = choice.delta?.refusal, !refusal.isEmpty { throw ConversationFailure.policyRejection }
            if let content = choice.delta?.content, !content.isEmpty {
                guard finishReason == nil else { throw ConversationFailure.malformedResponse }
                visibleText += content
                guard visibleText.count <= 16_384 else { throw ConversationFailure.outputLimit }
                events.append(.text(content))
            }
            if let reason = choice.finishReason {
                switch reason {
                case "stop": finishReason = reason
                case "length": throw ConversationFailure.outputLimit
                case "content_filter", "sensitive": throw ConversationFailure.policyRejection
                default: throw ConversationFailure.unsupportedOutput
                }
            }
        }
        if let usage = envelope.usage {
            let cached = usage.promptTokensDetails?.cachedTokens ?? 0
            guard usage.promptTokens >= 0, usage.completionTokens >= 0, cached >= 0, cached <= usage.promptTokens else {
                throw ConversationFailure.malformedResponse
            }
            events.append(.usage(ConversationUsage(
                inputTokens: usage.promptTokens, outputTokens: usage.completionTokens, cachedInputTokens: cached
            )))
        }
        return events
    }

    private struct Envelope: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let refusal: String?
            }
            let index: Int?
            let delta: Delta?
            let finishReason: String?
        }
        struct Usage: Decodable {
            struct Details: Decodable { let cachedTokens: Int? }
            let promptTokens: Int
            let completionTokens: Int
            let promptTokensDetails: Details?
        }
        let choices: [Choice]?
        let usage: Usage?
    }
}

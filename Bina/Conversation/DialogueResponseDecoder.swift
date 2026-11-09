import Foundation

/// Withholds only the reserved first line; ordinary reply text can still stream immediately.
nonisolated struct DialogueResponseDecoder {
    private enum State { case detecting, header, body }
    private static let prefix = "<bina-expression>"
    private static let suffix = "</bina-expression>"
    private var state = State.detecting
    private var pending = ""
    private(set) var intent: DialogueIntent?

    mutating func append(_ delta: String) throws -> String {
        if state == .body { return delta }
        pending += delta
        if state == .detecting {
            let probe = String(pending.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }))
            guard pending.utf8.count - probe.utf8.count <= 32 else { throw ConversationFailure.malformedResponse }
            if probe.isEmpty { return "" }
            if Self.prefix.hasPrefix(probe), probe != Self.prefix { return "" }
            if probe.hasPrefix(Self.prefix) {
                pending = probe
                state = .header
            } else {
                state = .body
                return drain()
            }
        }
        if let closing = pending.range(of: Self.suffix) {
            guard pending[..<closing.upperBound].utf8.count <= 512 else { throw ConversationFailure.malformedResponse }
            let tail = String(pending[closing.upperBound...])
            // CRLF is a single Swift Character, including when received across different deltas.
            guard !tail.isEmpty, tail != "\r" else { return "" }
            guard tail.hasPrefix("\n") || tail.hasPrefix("\r\n") else { throw ConversationFailure.malformedResponse }
            let json = pending[pending.index(pending.startIndex, offsetBy: Self.prefix.count)..<closing.lowerBound]
            intent = DialogueIntent.decode(Data(json.utf8))
            pending = String(tail.dropFirst())
            state = .body
            return drain()
        }
        guard pending.utf8.count <= 512 else { throw ConversationFailure.malformedResponse }
        return ""
    }

    mutating func finish() throws -> String {
        if state == .body { return "" }
        guard pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversationFailure.malformedResponse
        }
        return drain()
    }

    private mutating func drain() -> String {
        let value = pending
        pending = ""
        return value
    }
}

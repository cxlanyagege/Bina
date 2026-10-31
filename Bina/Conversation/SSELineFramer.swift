import Foundation

/// Unlike AsyncBytes.lines, SSE framing must preserve empty lines that terminate events.
struct SSELineFramer {
    private var buffer = Data()
    private var previousWasCR = false
    private var totalBytes = 0

    mutating func accept(_ byte: UInt8) throws -> String? {
        totalBytes += 1
        guard totalBytes <= 1_048_576 else { throw ConversationFailure.malformedResponse }
        if byte == 10, previousWasCR {
            previousWasCR = false
            return nil
        }
        previousWasCR = byte == 13
        if byte == 10 || byte == 13 {
            let line = try decodeBuffer()
            buffer.removeAll(keepingCapacity: true)
            return line
        }
        buffer.append(byte)
        guard buffer.count <= 65_536 else { throw ConversationFailure.malformedResponse }
        return nil
    }

    mutating func finish() throws -> String? {
        guard !buffer.isEmpty else { return nil }
        let line = try decodeBuffer()
        buffer.removeAll()
        return line
    }

    private func decodeBuffer() throws -> String {
        guard let line = String(data: buffer, encoding: .utf8) else { throw ConversationFailure.malformedResponse }
        return line
    }
}

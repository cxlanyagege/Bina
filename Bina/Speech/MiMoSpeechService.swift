import Foundation

@MainActor protocol SpeechHTTPTransport {
    func data(for request: URLRequest, limit: Int) async throws -> Data
}

/// Runs bounded response consumption away from the scene actor; rejects credential redirects.
@MainActor final class URLSessionSpeechTransport: SpeechHTTPTransport {
    private let session: URLSession

    init(configuration: URLSessionConfiguration? = nil) {
        let configuration = configuration ?? .ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: MiMoSessionDelegate(), delegateQueue: nil)
    }

    func data(for request: URLRequest, limit: Int) async throws -> Data {
        try Task.checkCancellation()
        let task = Task.detached { [session] in
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw ConversationFailure.malformedResponse }
            if let error = ConversationFailure.forHTTPStatus(response.statusCode) { throw error }
            guard response.expectedContentLength <= limit else { throw SpeechFailure.tooLong }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw SpeechFailure.tooLong }
                if data.count % 4_096 == 0 { try Task.checkCancellation() }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

@MainActor final class MiMoSpeechService: SpeechServing {
    private let transport: any SpeechHTTPTransport
    init(transport: (any SpeechHTTPTransport)? = nil) { self.transport = transport ?? URLSessionSpeechTransport() }

    func transcribe(_ recording: Data, apiKey: String) async throws -> String {
        try Task.checkCancellation()
        let encoding = Task.detached { try Self.recognitionRequest(recording, apiKey: apiKey) }
        let request = try await withTaskCancellationHandler { try await encoding.value } onCancel: { encoding.cancel() }
        try Task.checkCancellation()
        let data = try await transport.data(for: request, limit: 64 * 1_024)
        try Task.checkCancellation()
        let response = try Self.decode(data)
        guard let text = response.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw SpeechFailure.emptyTranscript
        }
        guard text.count <= ConversationPrompt.maximumUserCharacters else { throw SpeechFailure.tooLong }
        return text
    }

    func synthesize(_ text: String, voice: MiMoVoice, apiKey: String) async throws -> SpeechAudio {
        try Task.checkCancellation()
        let request = try Self.synthesisRequest(text, voice: voice, apiKey: apiKey)
        let data = try await transport.data(for: request, limit: 18 * 1_024 * 1_024)
        try Task.checkCancellation()
        let task = Task.detached {
            let response = try Self.decode(data)
            guard let encoded = response.message.audio?.data, encoded.utf8.count <= 16 * 1_024 * 1_024,
                  let wav = Data(base64Encoded: encoded) else { throw SpeechFailure.invalidAudio }
            return try SpeechAudio(wav: wav)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    nonisolated static func recognitionRequest(_ recording: Data, apiKey: String) throws -> URLRequest {
        guard recording.count <= 1_024_000 else { throw SpeechFailure.tooLong }
        // Validated capture duration is bounded independently from the provider's larger limit.
        let audio = try SpeechAudio(wav: recording)
        guard audio.duration >= 0.25 else { throw SpeechFailure.tooShort }
        guard audio.duration <= 30.1 else { throw SpeechFailure.tooLong }
        return try request([
            "model": "mimo-v2.5-asr", "stream": false, "asr_options": ["language": "zh"],
            "messages": [["role": "user", "content": [["type": "input_audio", "input_audio": ["data": "data:audio/wav;base64," + recording.base64EncodedString()]]]]]
        ], apiKey: apiKey)
    }

    nonisolated static func synthesisRequest(_ text: String, voice: MiMoVoice, apiKey: String) throws -> URLRequest {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4_000 else { throw SpeechFailure.tooLong }
        return try request([
            "model": "mimo-v2.5-tts", "stream": false,
            "messages": [["role": "user", "content": "Speak Mandarin naturally, gently, and unhurriedly, with subtle curiosity and playfulness. Use clear speech without forced whispering or singing. Say only the supplied text."], ["role": "assistant", "content": text]],
            "audio": ["format": "wav", "voice": voice.rawValue]
        ], apiKey: apiKey)
    }

    private nonisolated static func request(_ body: [String: Any], apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: MiMoConversationService.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue(try MiMoAPIKey.validate(apiKey), forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private nonisolated struct Choice: Decodable {
        struct Message: Decodable {
            struct Audio: Decodable { let data: String }
            let role: String
            let content: String?
            let audio: Audio?
            let refusal: String?
        }
        let message: Message
        let finish_reason: String
    }

    private nonisolated static func decode(_ data: Data) throws -> Choice {
        struct Response: Decodable { let choices: [Choice]; let error: ErrorBody? }
        struct ErrorBody: Decodable { let message: String? }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.error == nil, response.choices.count == 1,
              let choice = response.choices.first, choice.message.role == "assistant" else {
            throw ConversationFailure.malformedResponse
        }
        if choice.message.refusal != nil { throw ConversationFailure.policyRejection }
        guard choice.finish_reason == "stop" else { throw ConversationFailure.incompleteResponse }
        return choice
    }
}

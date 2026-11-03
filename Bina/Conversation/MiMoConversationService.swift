import Foundation

@MainActor
protocol ChatLineTransport {
    /// Return false to stop consuming a response, including the provider's terminal SSE event.
    func stream(_ request: URLRequest, receive: @escaping @MainActor (String) throws -> Bool) async throws
}

/// Redirects are rejected so a custom API-key header cannot escape the configured origin.
final class MiMoSessionDelegate: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
final class URLSessionChatTransport: ChatLineTransport {
    private let session: URLSession

    init(configuration: URLSessionConfiguration? = nil) {
        let configuration = configuration ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: MiMoSessionDelegate(), delegateQueue: nil)
    }

    func stream(_ request: URLRequest, receive: @escaping @MainActor (String) throws -> Bool) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ConversationFailure.malformedResponse }
        if let failure = ConversationFailure.forHTTPStatus(response.statusCode) { throw failure }
        var framer = SSELineFramer()
        for try await byte in bytes {
            try Task.checkCancellation()
            if let line = try framer.accept(byte), try !receive(line) { return }
        }
        if let line = try framer.finish() { _ = try receive(line) }
        try Task.checkCancellation()
    }
}

@MainActor
final class MiMoConversationService: ConversationServing {
    nonisolated static let endpoint = URL(string: "https://api.xiaomimimo.com/v1/chat/completions")!
    private let transport: any ChatLineTransport

    init(transport: (any ChatLineTransport)? = nil) {
        self.transport = transport ?? URLSessionChatTransport()
    }

    func stream(_ request: ConversationRequest, apiKey: String) -> AsyncThrowingStream<ConversationEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(2_048)) { continuation in
            let task = Task { @MainActor in
                do {
                    try Task.checkCancellation()
                    let urlRequest = try Self.makeURLRequest(request, apiKey: apiKey)
                    var decoder = MiMoSSEDecoder()
                    func deliver(_ events: [ConversationEvent]) throws {
                        for event in events {
                            switch continuation.yield(event) {
                            case .terminated: throw CancellationError()
                            case .dropped: throw ConversationFailure.malformedResponse
                            case .enqueued: break
                            @unknown default: throw ConversationFailure.malformedResponse
                            }
                        }
                    }
                    try await transport.stream(urlRequest) { line in
                        try Task.checkCancellation()
                        try deliver(decoder.accept(line))
                        return !decoder.isDone
                    }
                    try Task.checkCancellation()
                    try deliver(decoder.finish())
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: ConversationFailure.sanitized(error))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func makeURLRequest(_ request: ConversationRequest, apiKey: String) throws -> URLRequest {
        struct Body: Encodable {
            struct Thinking: Encodable { let type = "disabled" }
            struct Format: Encodable { let type = "json_object" }
            let model: String
            let messages: [ChatMessage]
            let stream = true
            let thinking = Thinking()
            let max_completion_tokens = 768
            let response_format: Format?
        }
        let key = try MiMoAPIKey.validate(apiKey)
        let format: Body.Format?
        switch request.purpose {
        case .dialogue: format = nil
        case .memoryExtraction: format = .init()
        }
        guard !request.messages.isEmpty, request.messages.count <= 16 else { throw ConversationFailure.malformedResponse }
        let body = try JSONEncoder().encode(Body(model: request.model.rawValue, messages: request.messages, response_format: format))
        guard body.count <= 102_400 else { throw ConversationFailure.malformedResponse }
        var urlRequest = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(key, forHTTPHeaderField: "api-key")
        urlRequest.httpBody = body
        return urlRequest
    }
}

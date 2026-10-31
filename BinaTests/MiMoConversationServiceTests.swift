import Foundation
import Testing
@testable import Bina

@MainActor
struct MiMoConversationServiceTests {
    @Test func payAsYouGoRequestKeepsTheSecretOutOfPromptAndDisablesThinking() throws {
        let request = ConversationRequest(model: .flash, messages: [ChatMessage(role: .user, content: "你好")], purpose: .dialogue)
        let urlRequest = try MiMoConversationService.makeURLRequest(request, apiKey: "sk-fixture-key-only")
        #expect(urlRequest.url?.absoluteString == "https://api.xiaomimimo.com/v1/chat/completions")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "api-key") == "sk-fixture-key-only")
        let data = try #require(urlRequest.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "mimo-v2.6-flash")
        #expect(body["stream"] as? Bool == true)
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        #expect(body["response_format"] == nil)
        #expect(body["max_completion_tokens"] as? Int == 768)
        #expect(!String(decoding: data, as: UTF8.self).contains("sk-fixture-key-only"))
    }

    @Test func extractionRequestsUseJSONModeWithTheSameProvider() throws {
        let source = ConversationTurn(id: UUID(), userText: ConversationFixture.source, createdAt: Date())
        let request = try ConversationPrompt.extraction(source: source, model: .pro)
        let urlRequest = try MiMoConversationService.makeURLRequest(request, apiKey: "sk-fixture-key-only")
        let data = try #require(urlRequest.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let body = try #require(object as? [String: Any])
        #expect(body["model"] as? String == "mimo-v2.6-pro")
        #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
        #expect(request.messages.count == 2)
        #expect(request.messages.last?.content.contains(ConversationFixture.source) == true)
    }

    @Test func tokenPlanAndHeaderInjectionKeysAreRejected() {
        for value in ["tp-fixture", "ttp-fixture", "sk-ab\nheader", "", "sk-短密钥", "sk-x"] {
            #expect(throws: ConversationFailure.invalidKey) { try MiMoAPIKey.validate(value) }
        }
    }

    @Test func multilineSSEIgnoresReasoningAndIncludesFinalUsage() throws {
        let events = try decode([
            ": heartbeat", "event: message", "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"hidden\"}}]}", "",
            "data: {\"choices\":", "data: [{\"index\":0,\"delta\":{\"content\":\"你好\"}}]}", "",
            Self.finish, "",
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":2,\"prompt_tokens_details\":{\"cached_tokens\":8}}}", "",
            "data: [DONE]", ""
        ])
        #expect(text(events) == "你好")
        let usage = events.compactMap { event -> ConversationUsage? in
            if case .usage(let value) = event { return value }
            return nil
        }
        #expect(usage == [ConversationUsage(inputTokens: 20, outputTokens: 2, cachedInputTokens: 8)])
    }

    @Test func finalEventWithoutTrailingBlankLineIsFlushed() throws {
        let events = try decode([Self.hello, "", Self.finish])
        #expect(text(events) == "你好")
    }

    @Test func disconnectedAndTruncatedRepliesCannotBecomeComplete() throws {
        #expect(throws: ConversationFailure.incompleteResponse) { try decode([Self.hello, ""]) }
        #expect(throws: ConversationFailure.outputLimit) {
            try decode([Self.hello, "", "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}", ""])
        }
        #expect(throws: ConversationFailure.emptyResponse) { try decode([Self.finish, ""]) }
    }

    @Test func malformedAndUnsupportedOutputIsRejected() throws {
        #expect(throws: ConversationFailure.malformedResponse) { try decode(["data: not JSON", ""]) }
        #expect(throws: ConversationFailure.unsupportedOutput) {
            try decode(["data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}", ""])
        }
        #expect(throws: ConversationFailure.policyRejection) {
            try decode(["data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"content_filter\"}]}", ""])
        }
    }

    @Test func dataAfterFinishAndUnboundedEventsAreRejected() throws {
        #expect(throws: ConversationFailure.malformedResponse) { try decode([Self.hello, "", Self.finish, "", Self.hello, ""]) }
        #expect(throws: ConversationFailure.malformedResponse) { try decode(["data: " + String(repeating: "x", count: 65_536)]) }
    }

    @Test func serviceStreamsThroughAnInjectedLineTransport() async throws {
        let transport = FixtureLineTransport(lines: [Self.hello, "", Self.finish, "", "data: [DONE]", ""])
        let service = MiMoConversationService(transport: transport)
        var received = ""
        for try await event in service.stream(simpleRequest(), apiKey: "sk-fixture-key-only") {
            if case .text(let value) = event { received += value }
        }
        #expect(received == "你好")
        #expect(transport.requests.count == 1)
    }

    @Test func stoppingTheConsumerCancelsTransportWork() async throws {
        let transport = WaitingLineTransport()
        let service = MiMoConversationService(transport: transport)
        let consumer = Task {
            for try await _ in service.stream(simpleRequest(), apiKey: "sk-fixture-key-only") {}
        }
        try await ConversationFixture.waitUntil { transport.started }
        consumer.cancel()
        _ = await consumer.result
        try await ConversationFixture.waitUntil { transport.cancelled }
    }

    @Test func aSlowConsumerCannotSilentlyLoseTheFinalUnterminatedEvent() async throws {
        var lines = (0..<2_048).flatMap { _ in [Self.hello, ""] }
        lines.append(#"data: {"choices":[{"index":0,"delta":{"content":"!"},"finish_reason":"stop"}]}"#)
        let transport = FixtureLineTransport(lines: lines)
        let stream = MiMoConversationService(transport: transport).stream(simpleRequest(), apiKey: "sk-fixture-key-only")
        try await ConversationFixture.waitUntil { transport.completed }
        do {
            for try await _ in stream {}
            Issue.record("A dropped final event must fail rather than mark a shortened answer complete.")
        } catch {
            #expect(error as? ConversationFailure == .malformedResponse)
        }
    }

    @Test func realURLSessionLineFramingWorksWithoutAPIAccess() async throws {
        let service = fixtureSessionService()
        var received = ""
        for try await event in service.stream(simpleRequest(), apiKey: "sk-fixture-key-only") {
            if case .text(let value) = event { received += value }
        }
        #expect(received == "你好")
    }

    @Test func realTransportMapsHTTPFailure() async throws {
        let service = fixtureSessionService(scenario: "rate-limit")
        do {
            for try await _ in service.stream(simpleRequest(), apiKey: "sk-fixture-key-only") {}
            Issue.record("Expected the fixture HTTP failure.")
        } catch {
            #expect(error as? ConversationFailure == .rateLimited)
        }
    }

    @Test func redirectDelegateNeverForwardsTheCredentialedRequest() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://fixture.invalid/redirected")!
        var request = URLRequest(url: url)
        request.setValue("sk-fixture-key-only", forHTTPHeaderField: "api-key")
        let task = session.dataTask(with: request)
        let response = HTTPURLResponse(url: MiMoConversationService.endpoint, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let forwarded: URLRequest? = await withCheckedContinuation { continuation in
            MiMoSessionDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
                continuation.resume(returning: $0)
            }
        }
        #expect(forwarded == nil)
    }

    @Test func byteFramingPreservesBlankLinesAndMultibyteText() throws {
        var framer = SSELineFramer()
        var lines: [String] = []
        for byte in Data("data: 你好\r\n\r\ndata: next\n\ndata: last".utf8) {
            if let line = try framer.accept(byte) { lines.append(line) }
        }
        if let last = try framer.finish() { lines.append(last) }
        #expect(lines == ["data: 你好", "", "data: next", "", "data: last"])
    }

    @Test func invalidUTF8AndOversizedRawLinesAreRejected() throws {
        var invalid = SSELineFramer()
        _ = try invalid.accept(255)
        #expect(throws: ConversationFailure.malformedResponse) { try invalid.accept(10) }
        var huge = SSELineFramer()
        #expect(throws: ConversationFailure.malformedResponse) {
            for _ in 0...65_536 { _ = try huge.accept(65) }
        }
    }

    @Test func HTTPAndTimeoutErrorsHaveSafeActionableCategories() {
        #expect(ConversationFailure.forHTTPStatus(401) == .authentication)
        #expect(ConversationFailure.forHTTPStatus(402) == .balance)
        #expect(ConversationFailure.forHTTPStatus(403) == .accessDenied)
        #expect(ConversationFailure.forHTTPStatus(404) == .modelUnavailable)
        #expect(ConversationFailure.forHTTPStatus(429) == .rateLimited)
        #expect(ConversationFailure.forHTTPStatus(503) == .server)
        #expect(ConversationFailure.sanitized(URLError(.timedOut)) == .timeout)
    }

    private static let hello = #"data: {"choices":[{"index":0,"delta":{"content":"你好"}}]}"#
    private static let finish = #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#

    private func simpleRequest() -> ConversationRequest {
        ConversationRequest(model: .flash, messages: [ChatMessage(role: .user, content: "Hello")], purpose: .dialogue)
    }

    private func decode(_ lines: [String]) throws -> [ConversationEvent] {
        var decoder = MiMoSSEDecoder()
        var events: [ConversationEvent] = []
        for line in lines { events += try decoder.accept(line) }
        events += try decoder.finish()
        return events
    }

    private func text(_ events: [ConversationEvent]) -> String {
        events.compactMap { event -> String? in
            if case .text(let value) = event { return value }
            return nil
        }.joined()
    }

    private func fixtureSessionService(scenario: String = "normal") -> MiMoConversationService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiMoFixtureURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Bina-Fixture": scenario]
        return MiMoConversationService(transport: URLSessionChatTransport(configuration: configuration))
    }
}

@MainActor
private final class FixtureLineTransport: ChatLineTransport {
    let lines: [String]
    var requests: [URLRequest] = []
    var completed = false

    init(lines: [String]) { self.lines = lines }

    func stream(_ request: URLRequest, receive: @escaping @MainActor (String) throws -> Bool) async throws {
        requests.append(request)
        defer { completed = true }
        for line in lines {
            if try !receive(line) { return }
        }
    }
}

@MainActor
private final class WaitingLineTransport: ChatLineTransport {
    var started = false
    var cancelled = false

    func stream(_ request: URLRequest, receive: @escaping @MainActor (String) throws -> Bool) async throws {
        started = true
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            cancelled = true
            throw error
        }
    }
}

/// Intercepts every request in its private test session; no DNS lookup or paid API call occurs.
nonisolated private final class MiMoFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let scenario = request.value(forHTTPHeaderField: "X-Bina-Fixture")
        let status = scenario == "rate-limit" ? 429 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = """
        data: {"choices":[{"index":0,"delta":{"content":"你好"}}]}

        data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

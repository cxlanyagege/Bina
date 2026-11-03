import Foundation
import Testing
@testable import Bina

@MainActor struct MiMoSpeechServiceTests {
    @Test func recognitionUsesBoundedChineseAudioAndKeepsCredentialsOutOfTheBody() throws {
        let audio = SpeechFixture.wav()
        let request = try MiMoSpeechService.recognitionRequest(audio, apiKey: "sk-fixture")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(request.url == MiMoConversationService.endpoint)
        #expect(request.value(forHTTPHeaderField: "api-key") == "sk-fixture")
        #expect(body["model"] as? String == "mimo-v2.5-asr")
        #expect(body["stream"] as? Bool == false)
        #expect((body["asr_options"] as? [String: String])?["language"] == "zh")
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect((content[0]["input_audio"] as? [String: String])?["data"] == "data:audio/wav;base64," + audio.base64EncodedString())
        #expect(!String(decoding: request.httpBody!, as: UTF8.self).contains("sk-fixture"))
    }

    @Test func synthesisUsesTheAssistantRoleAndAnExplicitChinesePreset() throws {
        let request = try MiMoSpeechService.synthesisRequest("Hello", voice: .moli, apiKey: "sk-fixture")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "mimo-v2.5-tts")
        #expect((body["audio"] as? [String: String]) == ["format": "wav", "voice": "茉莉"])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.last == ["role": "assistant", "content": "Hello"])
        #expect(messages.count == 2)
        #expect(throws: ConversationFailure.invalidKey) {
            try MiMoSpeechService.synthesisRequest("Hello", voice: .bingtang, apiKey: "secret")
        }
    }

    @Test func successfulResponsesProduceReviewedTextAndValidatedWaveAudio() async throws {
        let transport = FixtureSpeechHTTP()
        let service = MiMoSpeechService(transport: transport)
        transport.response = try SpeechFixture.response(text: "  哥伦比娅  ")
        #expect(try await service.transcribe(SpeechFixture.wav(), apiKey: "sk-fixture") == "哥伦比娅")
        transport.response = try SpeechFixture.response(audio: SpeechFixture.wav())
        let audio = try await service.synthesize("你好", voice: .bingtang, apiKey: "sk-fixture")
        #expect(audio.duration == 0.5)
    }

    @Test func emptyTruncatedMalformedAndInvalidAudioResponsesAreRejected() async throws {
        let transport = FixtureSpeechHTTP()
        let service = MiMoSpeechService(transport: transport)
        transport.response = try SpeechFixture.response(text: " ")
        await #expect(throws: SpeechFailure.emptyTranscript) { try await service.transcribe(SpeechFixture.wav(), apiKey: "sk-fixture") }
        transport.response = try SpeechFixture.response(audio: SpeechFixture.wav(), finish: "length")
        await #expect(throws: ConversationFailure.incompleteResponse) { try await service.synthesize("x", voice: .moli, apiKey: "sk-fixture") }
        for response in [Data("invalid json".utf8), try SpeechFixture.response(audio: Data("not audio".utf8)), try SpeechFixture.response()] {
            transport.response = response
            await #expect(throws: (any Error).self) { try await service.synthesize("x", voice: .moli, apiKey: "sk-fixture") }
        }
    }

    @Test func realSessionHonorsHTTPFailureAndResponseBoundsWithoutARealService() async throws {
        for scenario in ["rate-limit", "large"] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SpeechFixtureURLProtocol.self]
            configuration.httpAdditionalHeaders = ["X-Bina-Speech-Fixture": scenario]
            let transport = URLSessionSpeechTransport(configuration: configuration)
            let request = URLRequest(url: MiMoConversationService.endpoint)
            if scenario == "rate-limit" {
                await #expect(throws: ConversationFailure.rateLimited) { try await transport.data(for: request, limit: 8) }
            } else {
                await #expect(throws: SpeechFailure.tooLong) { try await transport.data(for: request, limit: 8) }
            }
        }
    }

    @Test func realSessionCancellationReachesTheUnderlyingRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechFixtureURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Bina-Speech-Fixture": "waiting"]
        let transport = URLSessionSpeechTransport(configuration: configuration)
        let task = Task { try await transport.data(for: URLRequest(url: MiMoConversationService.endpoint), limit: 100) }
        try await ConversationFixture.waitUntil { SpeechFixtureURLProtocol.hasStarted }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        try await ConversationFixture.waitUntil { SpeechFixtureURLProtocol.hasStopped }
    }

    @Test func anAlreadyCancelledSynthesisNeverReachesTheTransport() async throws {
        let transport = FixtureSpeechHTTP()
        let service = MiMoSpeechService(transport: transport)
        let task = Task { try await service.synthesize("hello", voice: .bingtang, apiKey: "sk-fixture") }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(transport.calls == 0)
    }
}

@MainActor private final class FixtureSpeechHTTP: SpeechHTTPTransport {
    var response = Data()
    var calls = 0
    func data(for request: URLRequest, limit: Int) async throws -> Data { calls += 1; return response }
}

/// A private URLProtocol prevents every fixture request from reaching DNS or a paid endpoint.
nonisolated private final class SpeechFixtureURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var started = false
    private static var stopped = false
    static var hasStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
    static var hasStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = request.value(forHTTPHeaderField: "X-Bina-Speech-Fixture")
        if scenario == "waiting" {
            Self.lock.lock(); Self.started = true; Self.stopped = false; Self.lock.unlock()
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: scenario == "rate-limit" ? 429 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("0123456789012345".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        if request.value(forHTTPHeaderField: "X-Bina-Speech-Fixture") == "waiting" {
            Self.lock.lock(); Self.stopped = true; Self.lock.unlock()
        }
    }
}

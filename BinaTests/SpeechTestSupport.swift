import Foundation
@testable import Bina

@MainActor enum SpeechFixture {
    static func wav(seconds: Double = 0.5, amplitude: Int16 = 8_000, rate: Int = 16_000) -> Data {
        let frames = Int(seconds * Double(rate))
        var data = Data()
        func text(_ text: String) { data.append(contentsOf: text.utf8) }
        func u16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
        func u32(_ n: UInt32) { u16(UInt16(n & 65_535)); u16(UInt16(n >> 16)) }
        text("RIFF"); u32(UInt32(36 + frames * 2)); text("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(frames * 2))
        for frame in 0..<frames { u16(UInt16(bitPattern: frame % 2 == 0 ? amplitude : -amplitude)) }
        return data
    }

    static func response(text: String = "你好", audio: Data? = nil, finish: String = "stop") throws -> Data {
        var message: [String: Any] = ["role": "assistant", "content": text]
        if let audio { message["audio"] = ["data": audio.base64EncodedString()] }
        return try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": message]]])
    }
}

@MainActor final class FixtureRecorder: SpeechRecording {
    var allowed = true
    var permissionRequests = 0
    var permissions: [CheckedContinuation<Bool, Never>] = []
    var suspendPermission = false
    var startError: Error?
    var startCount = 0
    var finishCount = 0
    var cancelCount = 0
    var recording = false
    var bytes = SpeechFixture.wav()
    func requestPermission() async -> Bool {
        permissionRequests += 1
        if suspendPermission { return await withCheckedContinuation { permissions.append($0) } }
        return allowed
    }
    func start() throws {
        if let startError { throw startError }
        startCount += 1
        recording = true
    }
    func finish() throws -> Data { finishCount += 1; recording = false; return bytes }
    func cancel() throws { cancelCount += 1; recording = false }
}

@MainActor final class FixtureSpeechService: SpeechServing {
    var recordings: [Data] = []
    var spokenTexts: [String] = []
    var voices: [MiMoVoice] = []
    var affects: [DialogueAffect] = []
    var recognition: [CheckedContinuation<String, Error>?] = []
    var synthesis: [CheckedContinuation<SpeechAudio, Error>?] = []
    func transcribe(_ recording: Data, apiKey: String) async throws -> String {
        recordings.append(recording)
        return try await withCheckedThrowingContinuation { recognition.append($0) }
    }
    func synthesize(_ text: String, voice: MiMoVoice, affect: DialogueAffect, apiKey: String) async throws -> SpeechAudio {
        spokenTexts.append(text)
        voices.append(voice)
        affects.append(affect)
        return try await withCheckedThrowingContinuation { synthesis.append($0) }
    }
    func recognize(_ text: String, at index: Int = 0) {
        let continuation = recognition[index]; recognition[index] = nil
        continuation?.resume(returning: text)
    }
    func synthesize(at index: Int = 0) throws {
        let continuation = synthesis[index]; synthesis[index] = nil
        continuation?.resume(returning: try SpeechAudio(wav: SpeechFixture.wav()))
    }
    func finishPending() {
        recognition.compactMap { $0 }.forEach { $0.resume(throwing: CancellationError()) }
        synthesis.compactMap { $0 }.forEach { $0.resume(throwing: CancellationError()) }
        recognition = []
        synthesis = []
    }
}

@MainActor final class FixtureSpeechPlayer: SpeechPlaying {
    var currentTime: TimeInterval = 0
    var route = SpeechPlaybackRoute.character
    var played: [SpeechAudio] = []
    var callbacks: [@MainActor (Bool) -> Void] = []
    var stopped = 0
    var error: Error?
    func play(_ audio: SpeechAudio, finished: @escaping @MainActor (Bool) -> Void) async throws {
        if let error { throw error }
        played.append(audio)
        callbacks.append(finished)
    }
    func stop() { stopped += 1 }
}

@MainActor final class SpeechHarness {
    let recorder = FixtureRecorder()
    let service = FixtureSpeechService()
    let player = FixtureSpeechPlayer()
    let chat = ScriptedConversationService()
    let keys = TestAPIKeyStore()
    let conversation: ConversationModel
    let speech: SpeechSession
    let clock: FixtureSpeechClock
    let presentation: FixtureSpeechPresentation
    var cues: [(CharacterConversationCue, Float)] = []

    init(limit: Duration = .seconds(30)) {
        let clock = FixtureSpeechClock()
        let presentation = FixtureSpeechPresentation()
        self.clock = clock
        self.presentation = presentation
        let conversation = ConversationModel(service: chat, memoryStore: TestMemoryStore(), keyStore: keys,
            preferences: ConversationFixture.preferences(), uptime: { clock.time })
        self.conversation = conversation
        speech = SpeechSession(conversation: conversation, recorder: recorder, service: service, player: player,
            preferences: ConversationFixture.preferences(), recordingLimit: limit,
            uptime: { clock.time }, present: { presentation.values.append($0) })
    }

    func record() async throws {
        speech.beginRecording()
        try await ConversationFixture.waitUntil { self.speech.phase == .recording }
        speech.endRecording()
        try await ConversationFixture.waitUntil { !self.service.recognition.isEmpty }
    }

    func reply() async throws {
        speech.setReadTypedReplies(true)
        speech.sendText("你好")
        try await ConversationFixture.waitUntil { !self.chat.continuations.isEmpty }
        chat.complete("今天想聊什么？")
        try await ConversationFixture.waitUntil { !self.service.synthesis.isEmpty }
    }

    func cleanup() {
        speech.stop()
        service.finishPending()
        recorder.permissions.forEach { $0.resume(returning: false) }
        recorder.permissions = []
        chat.continuations.forEach { $0.finish() }
    }
}

@MainActor final class FixtureSpeechClock { var time: TimeInterval = 100 }
@MainActor final class FixtureSpeechPresentation { var values: [CharacterConversationPresentation] = [] }

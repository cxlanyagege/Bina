import Foundation
import Testing
@testable import Bina

@MainActor struct SpeechAudioSessionTests {
    @Test func aQueuedStopCompletesBeforeTheNextActivation() async throws {
        var events: [String] = []
        var pending: CheckedContinuation<Void, Never>?
        var first = true
        let session = SpeechAudioSession(activate: { recording in
            events.append(recording ? "record" : "play")
            if first {
                first = false
                await withCheckedContinuation { pending = $0 }
            }
        }, deactivate: { events.append("stop") })
        let old = Task { try await session.activate(recording: false) }
        try await ConversationFixture.waitUntil { pending != nil }
        session.deactivate()
        let next = Task { try await session.activate(recording: true) }
        pending?.resume(); pending = nil
        try await old.value
        try await next.value
        await session.waitUntilIdle()
        #expect(events == ["play", "stop", "record"])
    }

    @Test func anActivationFailureDoesNotPoisonRecovery() async throws {
        var attempts = 0, stops = 0
        let session = SpeechAudioSession(activate: { _ in
            attempts += 1
            if attempts == 1 { throw SpeechFailure.recording }
        }, deactivate: { stops += 1 })
        await #expect(throws: SpeechFailure.recording) { try await session.activate(recording: true) }
        session.deactivate()
        try await session.activate(recording: false)
        #expect(attempts == 2)
        #expect(stops == 1)
    }

    @Test func cancelledMicrophoneActivationNeverStartsALateCapture() async throws {
        var pending: CheckedContinuation<Void, Never>?
        var stopped = false
        let session = SpeechAudioSession(activate: { _ in
            await withCheckedContinuation { pending = $0 }
        }, deactivate: { stopped = true })
        let recorder = MicrophoneRecorder(session: session)
        let capture = Task { try await recorder.start() }
        try await ConversationFixture.waitUntil { pending != nil }
        try recorder.cancel()
        capture.cancel()
        pending?.resume(); pending = nil
        await #expect(throws: CancellationError.self) { try await capture.value }
        await session.waitUntilIdle()
        #expect(stopped)
        #expect(throws: SpeechFailure.recording) { try recorder.finish() }
    }
}

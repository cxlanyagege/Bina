import Foundation
import Testing
import RealityKit
@testable import Bina

@MainActor @Suite(.serialized) struct SpeechAudioPlayerTests {
    @Test func validatedWaveCanBeImportedByTheNativeSpatialAudioLoader() async throws {
        let resource = try await AudioFileResource(from: SpeechFixture.wav(amplitude: 0), configuration: .init(loadingStrategy: .preload))
        #expect(!resource.configuration.shouldLoop)
    }
    @Test func actualWindowPlaybackCompletesWithoutSpeakingARealUtterance() async throws {
        let session = SpeechAudioSession()
        let player = SpeechAudioPlayer(session: session)
        defer { player.stop() }
        var finished: Bool?
        try await player.play(SpeechAudio(wav: SpeechFixture.wav(seconds: 0.3, amplitude: 0))) { finished = $0 }
        #expect(player.route == .window)
        try await ConversationFixture.waitUntil { finished != nil }
        #expect(finished == true)
        player.stop()
        await session.waitUntilIdle()
    }

    @Test func stoppingActualPlaybackSuppressesItsObsoleteCompletion() async throws {
        let session = SpeechAudioSession()
        let player = SpeechAudioPlayer(session: session)
        defer { player.stop() }
        var finished = false
        try await player.play(SpeechAudio(wav: SpeechFixture.wav(seconds: 0.4, amplitude: 0))) { _ in finished = true }
        player.stop()
        try await Task.sleep(for: .milliseconds(550))
        #expect(!finished)
        #expect(player.currentTime == 0)
        await session.waitUntilIdle()
    }
}

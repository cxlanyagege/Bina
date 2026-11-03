import Foundation
import Testing
@testable import Bina

@MainActor struct SpeechAudioTests {
    @Test func pcmDurationAndPlaybackEnergyAreValidated() throws {
        let audio = try SpeechAudio(wav: SpeechFixture.wav())
        #expect(audio.duration == 0.5)
        #expect(audio.mouthOpenness(at: 0.2) > 0)
        #expect(audio.mouthOpenness(at: -1) == 0)
        #expect(audio.mouthOpenness(at: 0.5) == 0)
        #expect(audio.mouthOpenness(at: .nan) == 0)
        #expect(try SpeechAudio(wav: SpeechFixture.wav(amplitude: 0)).mouthOpenness(at: 0.2) == 0)
    }

    @Test func truncatedWrongFormatAndInconsistentChunksAreRejected() throws {
        let valid = SpeechFixture.wav()
        var wrongRate = valid; wrongRate[24] = 0; wrongRate[25] = 0; wrongRate[26] = 0; wrongRate[27] = 0
        var compressed = valid; compressed[20] = 3
        var wrongSize = valid; wrongSize[4] = 1
        var overflow = valid; overflow[40] = 255; overflow[41] = 255; overflow[42] = 255; overflow[43] = 255
        for bytes in [Data(valid.dropLast()), Data("not wav".utf8), wrongRate, compressed, wrongSize, overflow] {
            #expect(throws: SpeechFailure.invalidAudio) { try SpeechAudio(wav: bytes) }
        }
    }

    @Test func recognitionRejectsAccidentalTapsAndOverlongRecordings() {
        for duration in [0.1, 30.5] {
            #expect(throws: SpeechFailure.self) {
                try MiMoSpeechService.recognitionRequest(SpeechFixture.wav(seconds: duration), apiKey: "sk-fixture")
            }
        }
    }

    @Test func interruptedSpeechIsNotSharedContextEvenIfItsTextIsComplete() {
        var turn = ConversationTurn(id: UUID(), userText: "hello", createdAt: Date())
        turn.state = .complete
        #expect(turn.isUsableInContext)
        for state: SpeechDelivery in [.preparing, .playing, .interrupted, .failed] {
            turn.speechDelivery = state
            #expect(!turn.isUsableInContext)
        }
        turn.speechDelivery = .played
        #expect(turn.isUsableInContext)
    }
}

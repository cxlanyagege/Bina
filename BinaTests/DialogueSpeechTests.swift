import Foundation
import Testing
@testable import Bina

@MainActor struct DialogueSpeechTests {
    @Test func expressionAndVoiceAgreeAtActualPlaybackAndCommitOnlyAfterDelivery() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.speech.setReadTypedReplies(true)
        h.speech.setVoice(.moli)
        h.speech.updatePresentation(available: true)
        try await ExpressionFixture.reply(h, affect: .concerned, input: "今天很累。")
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 1 }
        #expect(h.service.affects == [.concerned])
        #expect(h.service.voices == [.moli])
        #expect(h.service.spokenTexts == ["慢慢说，我在听。"])
        #expect(h.presentation.values.last?.cue == .thinking)
        #expect(h.presentation.values.last?.expression == nil)
        #expect(h.conversation.expressionContext == nil)
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        h.player.currentTime = 0.1
        h.speech.updatePresentation(available: true)
        #expect(h.presentation.values.last?.expression?.affect == .concerned)
        #expect(h.presentation.values.last!.mouth > 0)
        #expect(h.conversation.expressionContext == nil)
        h.player.callbacks[0](true)
        #expect(h.conversation.expressionContext?.affect == .concerned)
        #expect(h.presentation.values.last?.mouth == 0)
        h.clock.time += 9
        h.speech.updatePresentation(available: true)
        #expect(h.presentation.values.last?.expression?.strength == 0.5)
        h.clock.time += 3
        h.speech.updatePresentation(available: true)
        #expect(h.presentation.values.last?.expression == nil)
        #expect(h.conversation.expressionContext?.affect == .concerned)
    }

    @Test func interruptionReturnsToListeningAndCannotCommitAnUnheardReaction() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .concerned)
        h.speech.setReadTypedReplies(true)
        try await ExpressionFixture.reply(h, affect: .cheerful)
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 1 }
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        h.player.currentTime = 0.2
        h.speech.beginRecording()
        try await ConversationFixture.waitUntil { h.speech.phase == .recording }
        #expect(h.presentation.values.last?.cue == .listening)
        #expect(h.presentation.values.last?.expression == nil)
        #expect(h.presentation.values.last?.mouth == 0)
        h.player.callbacks[0](true)
        #expect(h.conversation.expressionContext?.affect == .concerned)
        #expect(h.conversation.turns.last?.speechDelivery == .interrupted)
        #expect(h.speech.phase == .recording)
    }

    @Test func synthesisFailureAndAuditionDoNotChangeDeliveredContinuity() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .warm)
        h.speech.setReadTypedReplies(true)
        try await ExpressionFixture.reply(h, affect: .cheerful)
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 1 }
        let continuation = h.service.synthesis[0]
        h.service.synthesis[0] = nil
        continuation?.resume(throwing: SpeechFailure.invalidAudio)
        try await ConversationFixture.waitUntil { h.speech.errorMessage != nil }
        #expect(h.conversation.expressionContext?.affect == .warm)
        #expect(h.presentation.values.last?.expression == nil)
        h.speech.audition()
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 2 }
        #expect(h.service.affects.last == .calm)
        try h.service.synthesize(at: 1)
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        h.player.callbacks[0](true)
        #expect(h.conversation.expressionContext?.affect == .warm)
    }

    @Test func memoryResetRejectsLatePlaybackAndItsPendingContinuity() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.speech.setReadTypedReplies(true)
        try await ExpressionFixture.reply(h, affect: .cheerful)
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 1 }
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        let turnID = h.conversation.turns[0].id
        h.conversation.clearMemories()
        h.player.callbacks[0](true)
        h.conversation.setSpeechDelivery(.played, for: turnID)
        #expect(h.conversation.expressionContext == nil)
        #expect(h.presentation.values.last?.expression == nil)
        #expect(h.conversation.turns[0].speechDelivery == .interrupted)
    }

    @Test func playbackFailureReleasesTheFaceWithoutReplacingThePreviousTone() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .warm)
        h.speech.setReadTypedReplies(true)
        try await ExpressionFixture.reply(h, affect: .curious)
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 1 }
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        h.player.callbacks[0](false)
        #expect(h.speech.phase == .idle)
        #expect(h.presentation.values.last?.expression == nil)
        #expect(h.conversation.expressionContext?.affect == .warm)
        #expect(h.conversation.turns.last?.speechDelivery == .failed)
    }
}

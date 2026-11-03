import Foundation
import Testing
@testable import Bina

@MainActor struct SpeechSessionTests {
    @Test func reviewedSpeechUsesTheExistingDialogueAndMemoryFlow() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try h.conversation.memory.confirm(ConversationFixture.candidate(), topic: "饮品偏好", content: "用户喜欢清淡的绿茶。")
        try await h.record()
        #expect(h.chat.requests.isEmpty)
        #expect(!h.recorder.recording)
        h.service.recognize("我喜欢红茶")
        try await ConversationFixture.waitUntil { h.speech.phase == .review }
        #expect(h.conversation.memory.records.count == 1)
        h.speech.transcript = "还记得我的饮品偏好吗？"
        #expect(h.speech.sendReviewedTranscript())
        try await ConversationFixture.waitUntil { h.chat.requests.count == 1 }
        #expect(h.chat.requests[0].messages.contains { $0.content.contains("清淡的绿茶") })
        #expect(h.conversation.turns[0].userText == "还记得我的饮品偏好吗？")
        h.chat.complete("你喜欢清淡的绿茶。")
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 1 }
        #expect(h.speech.phase == .synthesizing)
        #expect(h.player.played.isEmpty)
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        #expect(h.speech.subtitle == "你喜欢清淡的绿茶。")
        #expect(h.conversation.turns[0].speechDelivery == .playing)
        h.player.callbacks[0](true)
        #expect(h.speech.phase == .idle)
        #expect(h.conversation.turns[0].speechDelivery == .played)
        #expect(h.conversation.turns[0].playedSeconds == 0.5)
    }

    @Test func deniedPermissionDoesNotCaptureUploadOrGenerate() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.recorder.allowed = false
        h.speech.beginRecording()
        try await ConversationFixture.waitUntil { h.speech.errorMessage != nil }
        #expect(h.speech.phase == .idle)
        #expect(h.recorder.startCount == 0)
        #expect(h.service.recordings.isEmpty)
        #expect(h.chat.requests.isEmpty)
    }

    @Test func releasingDuringPermissionCannotStartALateRecording() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.recorder.suspendPermission = true
        h.speech.beginRecording()
        try await ConversationFixture.waitUntil { !h.recorder.permissions.isEmpty }
        h.speech.endRecording()
        let continuation = h.recorder.permissions.removeFirst()
        continuation.resume(returning: true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.recorder.startCount == 0)
        #expect(h.speech.phase == .idle)
    }

    @Test func immediateReleaseCannotOpenALatePermissionPrompt() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.speech.beginRecording()
        h.speech.endRecording()
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.recorder.permissionRequests == 0)
        #expect(h.recorder.startCount == 0)
        #expect(h.speech.phase == .idle)
    }

    @Test func recordingLimitFinishesCaptureAndRequiresReview() async throws {
        let h = SpeechHarness(limit: .milliseconds(40)); defer { h.cleanup() }
        h.speech.beginRecording()
        try await ConversationFixture.waitUntil { h.service.recordings.count == 1 }
        #expect(h.recorder.finishCount == 1)
        h.service.recognize("短录音")
        try await ConversationFixture.waitUntil { h.speech.phase == .review }
        #expect(h.chat.requests.isEmpty)
    }

    @Test func lateRecognitionCannotOverwriteANewInteraction() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await h.record()
        h.speech.sendText("新的文字问题")
        h.service.recognize("旧的识别结果")
        try await ConversationFixture.waitUntil { h.chat.requests.count == 1 }
        #expect(h.speech.transcript.isEmpty)
        #expect(h.conversation.turns.last?.userText == "新的文字问题")
        #expect(h.speech.phase == .thinking)
    }

    @Test func emptyRecognitionAndCaptureFailureHaveRecoverableErrors() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await h.record()
        h.service.recognize("  \n")
        try await ConversationFixture.waitUntil { h.speech.errorMessage != nil }
        #expect(h.speech.phase == .idle)
        h.recorder.startError = SpeechFailure.recording
        h.speech.beginRecording()
        try await ConversationFixture.waitUntil { h.speech.errorMessage == SpeechFailure.recording.userMessage }
        #expect(h.chat.requests.isEmpty)
    }

    @Test func typedRepliesAreSilentUnlessExplicitlyEnabled() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        #expect(!h.speech.readTypedReplies)
        h.speech.sendText("文字聊天")
        try await ConversationFixture.waitUntil { h.chat.continuations.count == 1 }
        h.chat.complete("文字回复")
        try await ConversationFixture.waitUntil { h.speech.phase == .idle }
        #expect(h.service.spokenTexts.isEmpty)
        #expect(h.conversation.turns[0].isUsableInContext)
    }

    @Test func cancelledSynthesisCannotStartLatePlayback() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await h.reply()
        h.speech.stop()
        try h.service.synthesize()
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.player.played.isEmpty)
        #expect(h.speech.phase == .idle)
        #expect(h.conversation.turns[0].state == .complete)
        #expect(h.conversation.turns[0].speechDelivery == .interrupted)
    }

    @Test func playbackInterruptionStopsAudioAndExcludesTheUnheardAnswer() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await h.reply()
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        h.player.currentTime = 0.2
        let previousStops = h.player.stopped
        h.speech.sendText("换个话题")
        try await ConversationFixture.waitUntil { h.chat.requests.count == 2 }
        #expect(h.player.stopped > previousStops)
        #expect(h.conversation.turns[0].speechDelivery == .interrupted)
        #expect(h.conversation.turns[0].playedSeconds == 0.2)
        #expect(!h.chat.requests[1].messages.contains { $0.content == "今天想聊什么？" })
        h.player.callbacks[0](true)
        #expect(h.speech.phase == .thinking)
        #expect(h.conversation.turns[0].speechDelivery == .interrupted)
    }

    @Test func playbackFailurePreservesReadableTextWithoutClaimingItWasHeard() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.player.error = SpeechFailure.playback
        try await h.reply()
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.errorMessage != nil }
        #expect(h.conversation.turns[0].answer == "今天想聊什么？")
        #expect(h.conversation.turns[0].state == .complete)
        #expect(h.conversation.turns[0].speechDelivery == .failed)
        #expect(!h.conversation.turns[0].isUsableInContext)
    }

    @Test func aNewRecordingStopsThePreviousVoiceBeforeOpeningTheMicrophone() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await h.reply()
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        let previousStops = h.player.stopped
        h.speech.beginRecording()
        try await ConversationFixture.waitUntil { h.speech.phase == .recording }
        #expect(h.player.stopped > previousStops)
        #expect(h.conversation.turns[0].speechDelivery == .interrupted)
        h.player.callbacks[0](true)
        #expect(h.speech.phase == .recording)
    }

    @Test func memoryMutationAndSettingsInvalidatePendingSpeech() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await h.reply()
        h.conversation.clearMemories()
        try h.service.synthesize()
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.player.played.isEmpty)
        #expect(h.speech.phase == .idle)
        h.speech.audition()
        try await ConversationFixture.waitUntil { h.service.synthesis.count == 2 }
        _ = h.conversation.saveSettings(model: .flash, displayName: "test", newKey: "", allowsMemoryWrites: false)
        try h.service.synthesize(at: 1)
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.player.played.isEmpty)
    }

    @Test func spaceLossCancelsSpatialSpeechButNotAnOrdinaryTextReply() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.speech.updatePresentation(available: true)
        try await h.reply()
        h.speech.updatePresentation(available: false)
        try h.service.synthesize()
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.speech.phase == .idle)
        #expect(h.player.played.isEmpty)
        h.speech.setReadTypedReplies(false)
        h.speech.updatePresentation(available: true)
        h.speech.sendText("继续文字")
        h.speech.updatePresentation(available: false)
        #expect(h.speech.phase == .thinking)
    }

    @Test func newConversationAndCredentialRemovalDiscardRecordingAndReview() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await h.record()
        h.conversation.newConversation()
        h.service.recognize("旧记录")
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.speech.transcript.isEmpty)
        h.conversation.removeAPIKey()
        h.speech.beginRecording()
        #expect(h.speech.phase == .idle)
        #expect(h.recorder.startCount == 1)
    }

    @Test func auditionIsExplicitAndVoiceChangesDoNotMakeRequests() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.speech.setVoice(.moli)
        #expect(h.service.spokenTexts.isEmpty)
        h.speech.audition()
        try await ConversationFixture.waitUntil { h.service.voices.count == 1 }
        #expect(h.service.voices == [.moli])
        #expect(h.conversation.turns.isEmpty)
        try h.service.synthesize()
        try await ConversationFixture.waitUntil { h.speech.phase == .speaking }
        h.speech.spaceDidDisappear()
        // A window-only audition is not tied to an immersive scene that was never present.
        #expect(h.speech.phase == .speaking)
    }
}

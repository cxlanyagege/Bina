import Foundation
import Testing
@testable import Bina

@MainActor struct DialogueConversationTests {
    @Test func theHeaderIsPrivateWhileTheAnswerStillStreamsAndFeedsHistory() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        h.speech.sendText("今天过得怎么样？")
        try await ConversationFixture.waitUntil { h.chat.requests.count == 1 }
        h.chat.continuations[0].yield(.text(ExpressionFixture.header(.warm)))
        h.chat.continuations[0].yield(.usage(.init(inputTokens: 1, outputTokens: 1, cachedInputTokens: 0)))
        try await ConversationFixture.waitUntil { h.conversation.turns[0].usage != nil }
        #expect(h.conversation.turns[0].answer.isEmpty)
        #expect(h.conversation.turns[0].firstContentLatency == nil)
        #expect(h.conversation.expressionContext == nil)
        h.chat.continuations[0].yield(.text("想听听你的新发现。"))
        try await ConversationFixture.waitUntil { !h.conversation.turns[0].answer.isEmpty }
        #expect(h.conversation.turns[0].state == .receiving)
        h.chat.continuations[0].finish()
        try await ConversationFixture.waitUntil { !h.conversation.isBusy }
        #expect(h.conversation.turns[0].expression.affect == .warm)
        #expect(h.conversation.expressionContext?.remainingReplies == 2)
        #expect(h.presentation.values.last?.expression?.affect == .warm)
        #expect(h.chat.requests.count == 1)
        #expect(h.service.spokenTexts.isEmpty)
        h.speech.sendText("比如呢？")
        try await ConversationFixture.waitUntil { h.chat.requests.count == 2 }
        #expect(h.chat.requests[1].messages.contains(.init(role: .assistant, content: "想听听你的新发现。")))
        let context = h.chat.requests[1].messages[1].content
        #expect(context.contains("expressionContinuity"))
        #expect(context.contains("warm"))
        #expect(context.contains("remainingReplies"))
        #expect(!h.chat.requests[1].messages.filter { $0.role == .assistant }.contains { $0.content.contains("bina-expression") })
    }

    @Test func concernContinuesBrieflyAndAnExplicitTopicChangeResolvesIt() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .concerned, input: "今天工作很累。")
        try await ExpressionFixture.reply(h, affect: .concerned, continuity: .continue, input: "一整天都没停下来。")
        #expect(h.conversation.turns.last?.expression.strength == 0.75)
        #expect(h.conversation.expressionContext?.remainingReplies == 1)
        try await ExpressionFixture.reply(h, affect: .concerned, continuity: .continue, input: "现在好多了。")
        #expect(h.conversation.turns.last?.expression.strength == 0.5)
        #expect(h.conversation.expressionContext == nil)
        try await ExpressionFixture.reply(h, affect: .warm)
        try await ExpressionFixture.reply(h, affect: .calm, continuity: .resolve, input: "换个话题，解释一下月相。")
        #expect(h.conversation.turns.last?.expression == .calm)
        #expect(h.conversation.expressionContext == nil)
        #expect(h.conversation.memory.records.isEmpty)
    }

    @Test func invalidOrMissingIntentKeepsReadableTextWithCalmDelivery() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .warm)
        for output in ["<bina-expression>{\"affect\":\"unbounded\"}</bina-expression>\n正常回答", "正常回答"] {
            h.speech.sendText("继续")
            let count = h.conversation.turns.count
            try await ConversationFixture.waitUntil { h.chat.requests.count == count }
            h.chat.complete(output)
            try await ConversationFixture.waitUntil { !h.conversation.isBusy }
            #expect(h.conversation.turns.last?.answer == "正常回答")
            #expect(h.conversation.turns.last?.expression == .calm)
            #expect(h.conversation.errorMessage == nil)
            #expect(h.conversation.expressionContext == nil)
        }
    }

    @Test func failedAndObsoleteRepliesCannotReplaceDeliveredContinuity() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .concerned)
        h.speech.sendText("第二个问题")
        try await ConversationFixture.waitUntil { h.chat.requests.count == 2 }
        h.chat.continuations[1].yield(.text(ExpressionFixture.header(.cheerful) + "未完成"))
        h.chat.continuations[1].finish(throwing: ConversationFailure.network)
        try await ConversationFixture.waitUntil { !h.conversation.isBusy }
        #expect(h.conversation.expressionContext?.affect == .concerned)
        #expect(h.presentation.values.last?.expression == nil)
        h.speech.sendText("第三个问题")
        try await ConversationFixture.waitUntil { h.chat.requests.count == 3 }
        h.speech.stop()
        h.chat.complete(ExpressionFixture.header(.cheerful) + "迟到的回答", at: 2)
        await Task.yield()
        #expect(h.conversation.turns.last?.state == .interrupted)
        #expect(h.conversation.expressionContext?.affect == .concerned)
        #expect(h.presentation.values.last?.cue == .idle)
    }

    @Test func contextReplacementsClearContinuityWithoutSavingAnEmotionRecord() async throws {
        for action in ["new", "settings", "memory", "reload", "key"] {
            let h = SpeechHarness(); defer { h.cleanup() }
            try await ExpressionFixture.reply(h, affect: .warm)
            switch action {
            case "new": h.conversation.newConversation()
            case "settings": _ = h.conversation.saveSettings(model: .flash, displayName: "", newKey: "", allowsMemoryWrites: true)
            case "memory": h.conversation.clearMemories()
            case "reload": h.conversation.reloadMemories()
            default: h.conversation.removeAPIKey()
            }
            #expect(h.conversation.expressionContext == nil)
            #expect(h.conversation.memory.records.isEmpty)
            #expect(h.presentation.values.last?.expression == nil)
        }
    }

    @Test func anExpiredToneIsOmittedFromRequestsAndCannotBeContinued() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .concerned)
        h.clock.time += 300
        h.speech.sendText("另一件事")
        try await ConversationFixture.waitUntil { h.chat.requests.count == 2 }
        #expect(!h.chat.requests[1].messages[1].content.contains("expressionContinuity"))
        h.chat.complete(ExpressionFixture.header(.concerned, .continue) + "新的回答")
        try await ConversationFixture.waitUntil { !h.conversation.isBusy }
        #expect(h.conversation.turns.last?.expression == .calm)
        #expect(h.conversation.expressionContext == nil)
    }

    @Test func expressionMetadataNeverBecomesMemoryEvidence() async throws {
        let h = SpeechHarness(); defer { h.cleanup() }
        try await ExpressionFixture.reply(h, affect: .warm, input: ConversationFixture.source)
        h.conversation.extractMemory(from: h.conversation.turns[0].id)
        try await ConversationFixture.waitUntil { h.chat.requests.count == 2 }
        #expect(!h.chat.requests[1].messages.last!.content.contains("bina-expression"))
        #expect(h.chat.requests[1].messages.last!.content.contains(ConversationFixture.source))
        h.chat.complete(ConversationFixture.extracted)
        try await ConversationFixture.waitUntil { !h.conversation.isBusy }
        #expect(h.conversation.candidate?.evidenceQuote == "我喜欢清淡的绿茶")
        #expect(h.conversation.memory.records.isEmpty)
    }
}

@MainActor enum ExpressionFixture {
    static func header(_ affect: DialogueAffect, _ continuity: DialogueIntent.Continuity = .new) -> String {
        "<bina-expression>{\"affect\":\"\(affect.rawValue)\",\"continuity\":\"\(continuity.rawValue)\"}</bina-expression>\n"
    }

    static func reply(_ h: SpeechHarness, affect: DialogueAffect, continuity: DialogueIntent.Continuity = .new,
                      input: String = "聊聊今天", answer: String = "慢慢说，我在听。") async throws {
        let count = h.chat.requests.count + 1
        h.speech.sendText(input)
        try await ConversationFixture.waitUntil { h.chat.requests.count == count }
        h.chat.complete(header(affect, continuity) + answer)
        try await ConversationFixture.waitUntil { !h.conversation.isBusy }
    }
}

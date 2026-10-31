import Foundation
import Testing
@testable import Bina

@MainActor
struct ConversationModelTests {
    @Test func missingKeyDoesNotStartAPaidRequestOrCreateATurn() {
        let fixture = Harness()
        fixture.keys.key = nil
        fixture.model.send("你好")
        #expect(fixture.service.requests.isEmpty)
        #expect(fixture.model.turns.isEmpty)
        #expect(fixture.model.errorMessage != nil)
        #expect(!fixture.model.hasAPIKey)
    }

    @Test func streamingReplyCompletesAndFeedsTheNextRequest() async throws {
        let fixture = Harness()
        fixture.model.send("你好")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 1 }
        fixture.service.continuations[0].yield(.text("晚上好"))
        try await ConversationFixture.waitUntil { fixture.model.turns.first?.answer == "晚上好" }
        #expect(fixture.model.turns.first?.state == .receiving)
        fixture.service.continuations[0].yield(.usage(ConversationUsage(inputTokens: 10, outputTokens: 3, cachedInputTokens: 0)))
        fixture.service.continuations[0].finish()
        try await ConversationFixture.waitUntil { !fixture.model.isBusy }
        #expect(fixture.model.turns.first?.state == .complete)
        #expect(fixture.model.turns.first?.usage?.inputTokens == 10)
        #expect(fixture.model.turns.first?.firstContentLatency != nil)
        fixture.model.send("今天想玩什么？")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 2 }
        #expect(fixture.service.requests[1].messages.contains(ChatMessage(role: .assistant, content: "晚上好")))
        fixture.model.cancel()
    }

    @Test func interruptionExcludesBothSidesOfAnIncompleteTurn() async throws {
        let fixture = Harness()
        fixture.model.send("旧问题")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 1 }
        fixture.service.continuations[0].yield(.text("旧回答的一部分"))
        try await ConversationFixture.waitUntil { fixture.model.turns.first?.answer.isEmpty == false }
        fixture.model.send("新问题")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 2 }
        fixture.service.complete("迟到的旧回答", at: 0)
        fixture.service.complete("新回答", at: 1)
        try await ConversationFixture.waitUntil { !fixture.model.isBusy }
        #expect(fixture.model.turns[0].state == .interrupted)
        #expect(fixture.model.turns[0].answer == "旧回答的一部分")
        #expect(fixture.model.turns[1].answer == "新回答")
        #expect(!fixture.service.requests[1].messages.contains { $0.content == "旧问题" || $0.content == "旧回答的一部分" })
        try await ConversationFixture.waitUntil { fixture.service.terminated.contains(0) }
    }

    @Test func failedPartialReplyIsVisibleButNotReusedAsComplete() async throws {
        let fixture = Harness()
        fixture.model.send("测试失败的提问")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 1 }
        fixture.service.continuations[0].yield(.text("部分文字"))
        fixture.service.continuations[0].finish(throwing: ConversationFailure.rateLimited)
        try await ConversationFixture.waitUntil { !fixture.model.isBusy }
        #expect(fixture.model.turns[0].state == .failed)
        #expect(fixture.model.errorMessage == ConversationFailure.rateLimited.userMessage)
        fixture.model.send("新的提问")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 2 }
        #expect(!fixture.service.requests[1].messages.contains { $0.content == "部分文字" })
        fixture.model.cancel()
    }

    @Test func emptySuccessfulAdapterOutputStillCannotCompleteAReply() async throws {
        let fixture = Harness()
        fixture.model.send("你好")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 1 }
        fixture.service.continuations[0].finish()
        try await ConversationFixture.waitUntil { !fixture.model.isBusy }
        #expect(fixture.model.turns[0].state == .failed)
        #expect(fixture.model.errorMessage == ConversationFailure.emptyResponse.userMessage)
    }

    @Test func aNewSendInvalidatesTheOldReplyEvenIfCredentialsBecomeUnavailable() async throws {
        let fixture = Harness()
        fixture.model.send("旧问题")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 1 }
        fixture.keys.error = KeychainFailure(status: -1)
        fixture.model.send("新问题")
        fixture.service.complete("迟到的旧回答")
        try await ConversationFixture.waitUntil { fixture.service.terminated.contains(0) }
        #expect(!fixture.model.isBusy)
        #expect(fixture.model.turns[0].state == .interrupted)
        #expect(fixture.model.turns[0].answer.isEmpty)
        #expect(fixture.service.requests.count == 1)
        #expect(fixture.model.errorMessage != nil)
    }

    @Test func extractionNeedsConfirmationAndRetainsUserEvidence() async throws {
        let fixture = Harness()
        try await fixture.propose()
        #expect(fixture.model.memory.records.isEmpty)
        #expect(fixture.store.saveCount == 0)
        let candidate = try #require(fixture.model.candidate)
        #expect(fixture.model.confirmMemory(candidate.id, topic: candidate.topic, content: candidate.content, replacing: nil))
        #expect(fixture.model.candidate == nil)
        #expect(fixture.model.memory.records.count == 1)
        #expect(fixture.model.memory.records.first?.evidence.quote == "我喜欢清淡的绿茶")
        #expect(!fixture.model.canExtract(from: fixture.model.turns[0].id))
        fixture.model.send("你还记得我的饮品偏好吗？")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 3 }
        #expect(fixture.service.requests[2].messages.contains { $0.content.contains(candidate.content) })
        fixture.model.cancel()
    }

    @Test func malformedExtractionAndFalseEvidenceCannotCreateCandidates() async throws {
        for output in ["{", #"{"memory":{"topic":"x","content":"y","evidence_quote":"从未说过的话"}}"#] {
            let fixture = Harness()
            try await fixture.completeTurn(ConversationFixture.source)
            fixture.model.extractMemory(from: fixture.model.turns[0].id)
            try await ConversationFixture.waitUntil { fixture.service.requests.count == 2 }
            fixture.service.complete(output)
            try await ConversationFixture.waitUntil { !fixture.model.isBusy }
            #expect(fixture.model.candidate == nil)
            #expect(fixture.model.memory.records.isEmpty)
            #expect(fixture.model.errorMessage != nil)
        }
    }

    @Test func failedConfirmationRetainsTheCandidateForAnExplicitRetry() async throws {
        let fixture = Harness()
        try await fixture.propose()
        let candidate = try #require(fixture.model.candidate)
        fixture.store.saveError = MemoryFailure.unavailable
        #expect(!fixture.model.confirmMemory(candidate.id, topic: candidate.topic, content: candidate.content, replacing: nil))
        #expect(fixture.model.candidate == candidate)
        #expect(fixture.model.memory.records.isEmpty)
        fixture.store.saveError = nil
        #expect(fixture.model.confirmMemory(candidate.id, topic: candidate.topic, content: candidate.content, replacing: nil))
    }

    @Test func aStaleReviewCannotConfirmADifferentProposal() async throws {
        let fixture = Harness()
        try await fixture.propose()
        #expect(!fixture.model.confirmMemory(UUID(), topic: "旧建议", content: "旧内容", replacing: nil))
        #expect(fixture.model.candidate != nil)
        #expect(fixture.model.memory.records.isEmpty)
    }

    @Test func deletionCancelsExtractionAndRejectsLateRecreation() async throws {
        let fixture = Harness(records: [ConversationFixture.record()])
        try await fixture.completeTurn(ConversationFixture.source)
        let sourceID = fixture.model.turns[0].id
        fixture.model.extractMemory(from: sourceID)
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 2 }
        fixture.model.deleteMemory(try #require(fixture.model.memory.records.first?.id))
        fixture.service.complete(ConversationFixture.extracted)
        try await ConversationFixture.waitUntil { fixture.service.terminated.contains(1) }
        #expect(fixture.model.candidate == nil)
        #expect(fixture.model.memory.records.isEmpty)
        #expect(!fixture.model.canExtract(from: sourceID))
        #expect(!fixture.model.isBusy)
    }

    @Test func correctionInvalidatesOldReplyAndAllPreviousContext() async throws {
        let old = ConversationFixture.record()
        let fixture = Harness(records: [old])
        fixture.model.send("旧上下文问题")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 1 }
        #expect(fixture.model.correctMemory(old.id, expectedRevision: old.revision, topic: old.topic, content: "用户更喜欢白开水。"))
        fixture.service.complete("旧值：" + old.content, at: 0)
        fixture.model.send("我现在喜欢喝什么？")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 2 }
        let content = fixture.service.requests[1].messages.map(\.content).joined()
        #expect(content.contains("用户更喜欢白开水。"))
        #expect(!content.contains(old.content))
        #expect(!content.contains("旧上下文问题"))
        #expect(fixture.model.turns[0].state == .interrupted)
        fixture.model.cancel()
    }

    @Test func disabledWritesKeepRecallAndDeletionAvailable() async throws {
        let record = ConversationFixture.record()
        let fixture = Harness(records: [record])
        #expect(fixture.model.saveSettings(model: .flash, displayName: "", newKey: "", allowsMemoryWrites: false))
        try await fixture.completeTurn(ConversationFixture.source)
        #expect(!fixture.model.canExtract(from: fixture.model.turns[0].id))
        #expect(!fixture.model.correctMemory(record.id, expectedRevision: record.revision, topic: record.topic, content: "新的内容"))
        #expect(!fixture.model.confirmMemory(UUID(), topic: "新主题", content: "新内容", replacing: nil))
        #expect(fixture.service.requests[0].messages.contains { $0.content.contains(record.content) })
        fixture.model.deleteMemory(record.id)
        #expect(fixture.model.memory.records.isEmpty)
    }

    @Test func newConversationDropsTransientTurnsAndProposalsButKeepsConfirmedRecords() async throws {
        let fixture = Harness(records: [ConversationFixture.record()])
        try await fixture.propose()
        fixture.model.newConversation()
        #expect(fixture.model.turns.isEmpty)
        #expect(fixture.model.candidate == nil)
        #expect(fixture.model.memory.records.count == 1)
    }

    @Test func settingsPersistWithoutPuttingKeysInPreferences() throws {
        let fixture = Harness()
        #expect(fixture.model.saveSettings(model: .pro, displayName: "小沈", newKey: "sk-new-fixture-only", allowsMemoryWrites: false))
        #expect(fixture.keys.key == "sk-new-fixture-only")
        let restored = ConversationModel(service: ScriptedConversationService(), memoryStore: fixture.store, keyStore: fixture.keys, preferences: fixture.preferences)
        #expect(restored.selectedModel == .pro)
        #expect(restored.userDisplayName == "小沈")
        #expect(!restored.memoryWritingEnabled)
        #expect(restored.turns.isEmpty)
        #expect(!fixture.preferences.dictionaryRepresentation().values.contains { ($0 as? String) == "sk-new-fixture-only" })
        #expect(!fixture.model.saveSettings(model: .flash, displayName: "x", newKey: "tp-not-supported", allowsMemoryWrites: true))
        #expect(fixture.model.selectedModel == .pro)
        #expect(fixture.keys.key == "sk-new-fixture-only")
    }

    @Test func keyRemovalStopsAnActiveReplyWithoutDeletingMemories() async throws {
        let fixture = Harness(records: [ConversationFixture.record()])
        fixture.model.send("你好")
        try await ConversationFixture.waitUntil { fixture.service.requests.count == 1 }
        fixture.model.removeAPIKey()
        fixture.service.complete("迟到的回答")
        #expect(fixture.keys.key == nil)
        #expect(!fixture.model.hasAPIKey)
        #expect(!fixture.model.isBusy)
        #expect(fixture.model.turns[0].state == .interrupted)
        #expect(fixture.model.memory.records.count == 1)
    }

    @Test func storageFailureDoesNotSilentlyEraseOrOverwriteUnknownMemories() {
        let fixture = Harness(loadError: MemoryFailure.unsupportedVersion(2))
        #expect(!fixture.model.memory.isAvailable)
        #expect(fixture.store.saveCount == 0)
        fixture.model.clearMemories()
        #expect(fixture.model.memory.isAvailable)
        #expect(fixture.store.saveCount == 1)
    }

    @Test func oversizedOrEmptyInputCannotStartARequest() {
        let fixture = Harness()
        fixture.model.send("   ")
        fixture.model.send(String(repeating: "x", count: 2_001))
        #expect(fixture.service.requests.isEmpty)
        #expect(fixture.model.turns.isEmpty)
    }
}

@MainActor
private final class Harness {
    let service = ScriptedConversationService()
    let store = TestMemoryStore()
    let keys = TestAPIKeyStore()
    let preferences = ConversationFixture.preferences()
    let model: ConversationModel

    init(records: [MemoryRecord] = [], loadError: Error? = nil) {
        store.document = MemoryDocument(records: records)
        store.loadError = loadError
        model = ConversationModel(service: service, memoryStore: store, keyStore: keys, preferences: preferences)
    }

    func completeTurn(_ input: String, answer: String = "我听见了。") async throws {
        let expected = service.requests.count + 1
        model.send(input)
        try await ConversationFixture.waitUntil { self.service.requests.count == expected }
        service.complete(answer)
        try await ConversationFixture.waitUntil { !self.model.isBusy }
    }

    func propose() async throws {
        try await completeTurn(ConversationFixture.source)
        let expected = service.requests.count + 1
        model.extractMemory(from: model.turns[0].id)
        try await ConversationFixture.waitUntil { self.service.requests.count == expected }
        service.complete(ConversationFixture.extracted)
        try await ConversationFixture.waitUntil { !self.model.isBusy }
    }
}

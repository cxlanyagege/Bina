import Foundation
import Testing
@testable import Bina

@MainActor
struct ConversationPromptTests {
    @Test func personaAndMemoryStayDistinctFromRealObservations() throws {
        let store = TestMemoryStore()
        let record = ConversationFixture.record()
        store.document = MemoryDocument(records: [record])
        let request = try ConversationPrompt.dialogue(input: "你记得我的偏好吗？", history: [], library: MemoryLibrary(store: store), displayName: "测试称呼", model: .flash)
        #expect(request.messages.first?.content.contains("Columbina") == true)
        #expect(request.messages.first?.content.contains("No live camera") == true)
        #expect(request.messages.first?.content.contains("not your character name") == true)
        #expect(request.messages[1].content.contains(record.content))
        #expect(request.messages[1].content.contains("测试称呼"))
        #expect(!request.messages[1].content.contains(record.evidence.quote))
        #expect(request.messages.last == ChatMessage(role: .user, content: "你记得我的偏好吗？"))
    }

    @Test func historyContainsOnlyBoundedCompleteTurnPairs() throws {
        let turns = (0..<10).map { index in
            var turn = ConversationTurn(id: UUID(), userText: "Question \(index)", createdAt: Date())
            turn.answer = "Answer \(index)"
            turn.state = .complete
            return turn
        }
        var failed = ConversationTurn(id: UUID(), userText: "Incomplete question", createdAt: Date())
        failed.answer = "Partial answer"
        failed.state = .failed
        let request = try ConversationPrompt.dialogue(input: "current", history: turns + [failed], library: MemoryLibrary(store: TestMemoryStore()), displayName: "", model: .flash)
        #expect(request.messages.count == 15)
        #expect(!request.messages.contains { $0.content == "Question 0" || $0.content == "Partial answer" || $0.content == "Incomplete question" })
        #expect(request.messages[2] == ChatMessage(role: .user, content: "Question 4"))
        #expect(request.messages[3] == ChatMessage(role: .assistant, content: "Answer 4"))
    }

    @Test func aLargePriorTurnCannotOverflowTheHistoryBudget() throws {
        var large = ConversationTurn(id: UUID(), userText: "x", createdAt: Date())
        large.answer = String(repeating: "x", count: ConversationPrompt.maximumHistoryCharacters)
        large.state = .complete
        let request = try ConversationPrompt.dialogue(input: "current", history: [large], library: MemoryLibrary(store: TestMemoryStore()), displayName: "", model: .flash)
        #expect(request.messages.count == 3)
    }

    @Test func aFailedStoreIsReportedAsUnavailableInsteadOfEmpty() throws {
        let store = TestMemoryStore()
        store.loadError = MemoryFailure.unavailable
        let request = try ConversationPrompt.dialogue(input: "remember?", history: [], library: MemoryLibrary(store: store), displayName: "", model: .flash)
        #expect(request.messages[1].content.contains("Unavailable"))
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class ConversationModel {
    enum Activity: Equatable { case idle, reply(UUID), extraction(UUID) }

    private(set) var turns: [ConversationTurn] = []
    private(set) var activity: Activity = .idle
    private(set) var candidate: MemoryCandidate?
    private(set) var hasAPIKey = false
    private(set) var selectedModel: MiMoModel
    private(set) var userDisplayName: String
    private(set) var memoryWritingEnabled: Bool
    private(set) var errorMessage: String?
    private(set) var notice: String?
    let memory: MemoryLibrary

    @ObservationIgnored private let service: any ConversationServing
    @ObservationIgnored private let keyStore: any APIKeyPersisting
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var contextStartIndex = 0
    @ObservationIgnored private var continuity = DialogueContinuity()
    @ObservationIgnored private let uptime: @MainActor () -> TimeInterval
    @ObservationIgnored weak var observer: (any ConversationObserving)?

    init(
        service: (any ConversationServing)? = nil,
        memoryStore: (any MemoryPersisting)? = nil,
        keyStore: (any APIKeyPersisting)? = nil,
        preferences: UserDefaults = .standard,
        uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.service = service ?? MiMoConversationService()
        self.keyStore = keyStore ?? KeychainAPIKeyStore()
        self.preferences = preferences
        self.uptime = uptime
        selectedModel = preferences.string(forKey: "conversation.model").flatMap(MiMoModel.init(rawValue:)) ?? .flash
        userDisplayName = preferences.string(forKey: "conversation.displayName") ?? ""
        memoryWritingEnabled = preferences.object(forKey: "conversation.memoryWritingEnabled") as? Bool ?? true
        memory = MemoryLibrary(store: memoryStore ?? FileMemoryStore())
        refreshCredentialStatus()
    }

    var isBusy: Bool { activity != .idle }
    var expressionContext: DialogueContinuity.Context? { continuity.context(at: uptime()) }

    @discardableResult
    func saveSettings(model: MiMoModel, displayName: String, newKey: String, allowsMemoryWrites: Bool) -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 40, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            errorMessage = "称呼请控制在 40 字以内，不要包含换行。"
            return false
        }
        do {
            if !newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try keyStore.save(MiMoAPIKey.validate(newKey))
            }
        } catch {
            errorMessage = (error as? ConversationFailure)?.userMessage ?? "无法将密钥保存到本机钥匙串，设置未更新。"
            return false
        }
        invalidateContext()
        selectedModel = model
        userDisplayName = name
        memoryWritingEnabled = allowsMemoryWrites
        preferences.set(model.rawValue, forKey: "conversation.model")
        preferences.set(name, forKey: "conversation.displayName")
        preferences.set(allowsMemoryWrites, forKey: "conversation.memoryWritingEnabled")
        refreshCredentialStatus()
        notice = "设置已保存。"
        return true
    }

    func removeAPIKey() {
        invalidateContext()
        do {
            try keyStore.remove()
            hasAPIKey = false
            errorMessage = nil
            notice = "已移除本机密钥。"
        } catch {
            errorMessage = "无法移除钥匙串中的密钥，请稍后重试。"
        }
    }

    @discardableResult
    func send(_ text: String) -> UUID? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count <= ConversationPrompt.maximumUserCharacters else {
            errorMessage = "请发送 1 到 2000 字的消息。"
            return nil
        }
        cancel()
        candidate = nil
        let key: String
        do { key = try requireKey() } catch { return nil }
        errorMessage = nil
        notice = nil
        let request: ConversationRequest
        do {
            request = try ConversationPrompt.dialogue(
                input: input, history: Array(turns.dropFirst(contextStartIndex)),
                library: memory, displayName: userDisplayName, model: selectedModel,
                expressionContinuity: expressionContext
            )
        } catch {
            errorMessage = "无法准备这次对话，请重试。"
            return nil
        }
        let turn = ConversationTurn(id: UUID(), userText: input, createdAt: Date())
        turns.append(turn)
        if turns.count > 100 {
            let removed = turns.count - 100
            turns.removeFirst(removed)
            contextStartIndex = max(0, contextStartIndex - removed)
        }
        let operation = UUID()
        let memoryRevision = memory.revision
        let startedAt = ProcessInfo.processInfo.systemUptime
        operationID = operation
        activity = .reply(turn.id)
        observer?.conversationDidStartReply(turn.id)
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var decoder = DialogueResponseDecoder()
            do {
                for try await event in service.stream(request, apiKey: key) {
                    guard isCurrent(operation, memoryRevision: memoryRevision),
                          let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
                    switch event {
                    case .text(let delta):
                        let text = try decoder.append(delta)
                        guard turns[index].answer.count + text.count <= 16_384 else { throw ConversationFailure.outputLimit }
                        turns[index].answer += text
                        if turns[index].firstContentLatency == nil,
                           !turns[index].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            turns[index].firstContentLatency = ProcessInfo.processInfo.systemUptime - startedAt
                        }
                    case .usage(let usage): turns[index].usage = usage
                    }
                }
                guard isCurrent(operation, memoryRevision: memoryRevision),
                      let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
                turns[index].answer += try decoder.finish()
                guard !turns[index].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ConversationFailure.emptyResponse
                }
                let resolved = continuity.resolve(decoder.intent, at: uptime())
                turns[index].expression = resolved.expression
                turns[index].continuityAfterDelivery = resolved.next
                turns[index].state = .complete
                if turns[index].speechDelivery == .notRequested { continuity = resolved.next }
                finishOperation()
                observer?.conversationDidCompleteReply(turns[index])
            } catch {
                guard isCurrent(operation, memoryRevision: memoryRevision),
                      let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
                turns[index].state = error is CancellationError ? .interrupted : .failed
                errorMessage = error is CancellationError ? nil : ConversationFailure.sanitized(error).userMessage
                finishOperation()
                observer?.conversationDidFailReply()
            }
        }
        return turn.id
    }

    func cancel() {
        observer?.conversationDidInvalidate()
        operationID = nil
        requestTask?.cancel()
        requestTask = nil
        if case .reply(let id) = activity, let index = turns.firstIndex(where: { $0.id == id }), turns[index].state == .receiving {
            turns[index].state = .interrupted
        }
        activity = .idle
    }

    func credentialForSpeech() throws -> String { try requireKey() }

    func setSpeechDelivery(_ state: SpeechDelivery, for id: UUID, playedSeconds: TimeInterval = 0) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        // Only the current context can commit a fully heard reply; old callbacks cannot restore it.
        if state == .played {
            guard turns[index].speechDelivery == .playing || turns[index].speechDelivery == .preparing,
                  turns[index].state == .complete, index >= contextStartIndex else { return }
            continuity = turns[index].continuityAfterDelivery
        }
        turns[index].speechDelivery = state
        turns[index].playedSeconds = max(0, playedSeconds.isFinite ? playedSeconds : 0)
    }

    func newConversation() {
        cancel()
        turns = []
        continuity = DialogueContinuity()
        contextStartIndex = 0
        candidate = nil
        errorMessage = nil
        notice = "已开始新对话，确认过的记忆仍然保留。"
    }

    func canExtract(from id: UUID) -> Bool {
        memoryWritingEnabled && memory.isAvailable && !isBusy
            && turns.dropFirst(contextStartIndex).contains { $0.id == id }
    }

    func extractMemory(from id: UUID) {
        guard canExtract(from: id), let source = turns.first(where: { $0.id == id }) else { return }
        let key: String
        do { key = try requireKey() } catch { return }
        let request: ConversationRequest
        do { request = try ConversationPrompt.extraction(source: source, model: selectedModel) } catch {
            errorMessage = "无法准备记忆提取，请重试。"
            return
        }
        cancel()
        candidate = nil
        notice = nil
        errorMessage = nil
        let operation = UUID()
        let memoryRevision = memory.revision
        operationID = operation
        activity = .extraction(id)
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var output = ""
            do {
                for try await event in service.stream(request, apiKey: key) {
                    guard isCurrent(operation, memoryRevision: memoryRevision) else { return }
                    if case .text(let delta) = event {
                        guard output.utf8.count + delta.utf8.count <= 16_384 else { throw MemoryFailure.invalidRecord }
                        output += delta
                    }
                }
                guard isCurrent(operation, memoryRevision: memoryRevision), memoryWritingEnabled else { return }
                do {
                    candidate = try MemoryCandidate.decode(output, sourceID: source.id, sourceText: source.userText)
                    notice = candidate == nil ? "这句话中没有提取到适合长期保存的明确偏好或事实。" : "请检查记忆建议，确认后才会保存。"
                } catch {
                    errorMessage = (error as? MemoryFailure)?.userMessage ?? "记忆建议格式无效，未保存。"
                }
                finishOperation()
            } catch {
                guard isCurrent(operation, memoryRevision: memoryRevision) else { return }
                errorMessage = (error as? MemoryFailure)?.userMessage ?? ConversationFailure.sanitized(error).userMessage
                finishOperation()
            }
        }
    }

    @discardableResult
    func confirmMemory(_ candidateID: UUID, topic: String, content: String, replacing id: UUID?) -> Bool {
        guard memoryWritingEnabled, let candidate, candidate.id == candidateID else { return false }
        do {
            try memory.confirm(candidate, topic: topic, content: content, replacing: id)
            invalidateContext()
            notice = "记忆已保存到本机。后续对话将使用更新后的记忆。"
            return true
        } catch {
            errorMessage = (error as? MemoryFailure)?.userMessage ?? "保存记忆失败，原有记录保持不变。"
            return false
        }
    }

    @discardableResult
    func correctMemory(_ id: UUID, expectedRevision: Int, topic: String, content: String) -> Bool {
        guard memoryWritingEnabled else { return false }
        do {
            try memory.correct(id, expectedRevision: expectedRevision, topic: topic, content: content)
            invalidateContext()
            notice = "记忆已修改，此前对话不再作为后续请求的上下文。"
            return true
        } catch {
            errorMessage = (error as? MemoryFailure)?.userMessage ?? "修改记忆失败，原有记录保持不变。"
            return false
        }
    }

    func deleteMemory(_ id: UUID) {
        mutateMemory { try memory.delete(id) }
    }

    func clearMemories() {
        mutateMemory { try memory.clearAndRebuild() }
    }

    func reloadMemories() {
        invalidateContext()
        memory.reload()
        notice = memory.isAvailable ? "本地记忆已重新读取。" : nil
    }

    func dismissCandidate() { candidate = nil }

    private func mutateMemory(_ mutation: () throws -> Void) {
        // Invalidate even if storage fails: no old generation may race a user's deletion intent.
        invalidateContext()
        do {
            try mutation()
            notice = "本地记忆已更新，此前对话不再作为后续请求的上下文。"
        } catch {
            errorMessage = (error as? MemoryFailure)?.userMessage ?? "更新记忆失败，原有记录保持不变。"
        }
    }

    private func invalidateContext() {
        cancel()
        candidate = nil
        contextStartIndex = turns.count
        continuity = DialogueContinuity()
        errorMessage = nil
    }

    private func isCurrent(_ id: UUID, memoryRevision: UUID) -> Bool {
        operationID == id && memory.revision == memoryRevision && !Task.isCancelled
    }

    private func finishOperation() {
        operationID = nil
        requestTask = nil
        activity = .idle
    }

    private func refreshCredentialStatus() {
        do {
            hasAPIKey = try keyStore.load() != nil
            errorMessage = nil
        } catch {
            hasAPIKey = false
            errorMessage = "无法读取本机钥匙串，请解锁设备后重试设置。"
        }
    }

    private func requireKey() throws -> String {
        do {
            guard let key = try keyStore.load() else {
                hasAPIKey = false
                throw ConversationFailure.authentication
            }
            return try MiMoAPIKey.validate(key)
        } catch {
            errorMessage = (error as? ConversationFailure)?.userMessage ?? "无法读取本机钥匙串，请重新配置密钥。"
            throw error
        }
    }
}

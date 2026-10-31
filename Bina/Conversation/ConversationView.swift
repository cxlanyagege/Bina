import SwiftUI

struct ConversationView: View {
    @Bindable var model: ConversationModel
    @State private var draft = ""
    @State private var showsSettings = false
    @State private var showsMemories = false
    @State private var showsNewConversation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("哥伦比娅").font(.largeTitle)
                    Text(model.selectedModel.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showsMemories = true } label: {
                    Label("记忆 · \(model.memory.records.count)", systemImage: "brain")
                }
                .accessibilityIdentifier("conversation.memories")
                Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("对话设置")
                    .accessibilityIdentifier("conversation.settings")
                Button { showsNewConversation = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("开始新对话")
            }

            if !model.hasAPIKey {
                HStack {
                    Text("先配置 MiMo 按量 API 密钥，即可开始聊天。")
                    Spacer()
                    Button("设置") { showsSettings = true }
                }
                .font(.callout)
            }
            if let message = model.memory.availabilityMessage {
                Text(message).font(.callout).foregroundStyle(.orange)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if model.turns.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("与她说说今天的事。")
                                Text("想长期记住一句话时，可以提取记忆建议，检查并确认后保存。聊天记录仅保留在本次运行期间。")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 24)
                        }
                        ForEach(model.turns) { turn in
                            turnView(turn)
                        }
                        Color.clear.frame(height: 1).id("conversation.bottom")
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: model.turns.last?.answer) {
                    proxy.scrollTo("conversation.bottom", anchor: .bottom)
                }
                .onChange(of: model.turns.count) {
                    proxy.scrollTo("conversation.bottom", anchor: .bottom)
                }
            }
            .accessibilityIdentifier("conversation.transcript")

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("conversation.error")
            } else if let notice = model.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            if case .extraction = model.activity {
                ProgressView("正在提取记忆建议…")
            }
            HStack(alignment: .bottom) {
                TextField("想对她说什么？", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("conversation.input")
                if model.isBusy {
                    Button("停止") { model.cancel() }
                        .accessibilityIdentifier("conversation.stop")
                }
                Button("发送") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasAPIKey || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > ConversationPrompt.maximumUserCharacters)
                    .accessibilityIdentifier("conversation.send")
            }
            if draft.count > ConversationPrompt.maximumUserCharacters {
                Text("消息请控制在 2000 字以内。当前 \(draft.count) 字。")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("对话、角色设定和相关记忆片段会发送到 Xiaomi。确认过的记忆保存在本机。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(isPresented: $showsSettings) { ConversationSettingsView(model: model) }
        .sheet(isPresented: $showsMemories) { MemoryLibraryView(model: model) }
        .sheet(item: Binding(
            get: { model.candidate },
            set: { if $0 == nil { model.dismissCandidate() } }
        )) { candidate in
            MemoryCandidateView(model: model, candidate: candidate)
        }
        .confirmationDialog("开始新对话？", isPresented: $showsNewConversation, titleVisibility: .visible) {
            Button("开始新对话", role: .destructive) { model.newConversation() }
        } message: {
            Text("清除当前聊天和未确认的建议，保留确认过的记忆。")
        }
    }

    private func turnView(_ turn: ConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("你").font(.caption).foregroundStyle(.secondary)
                Text(turn.userText).textSelection(.enabled)
                Button("从这句话提取记忆") { model.extractMemory(from: turn.id) }
                    .font(.caption)
                    .disabled(!model.hasAPIKey || !model.canExtract(from: turn.id))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text("哥伦比娅").font(.caption).foregroundStyle(.secondary)
                if !turn.answer.isEmpty {
                    Text(turn.answer).textSelection(.enabled)
                }
                switch turn.state {
                case .receiving: ProgressView("正在回复…").font(.caption)
                case .interrupted: Text("已停止 · 这段回答不参与后续上下文").font(.caption).foregroundStyle(.secondary)
                case .failed: Text("回答未完成 · 不参与后续上下文").font(.caption).foregroundStyle(.orange)
                case .complete:
                    if let usage = turn.usage {
                        Text("用量：输入 \(usage.inputTokens) · 输出 \(usage.outputTokens) tokens")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        model.send(text)
    }
}

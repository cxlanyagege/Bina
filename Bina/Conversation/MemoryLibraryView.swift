import SwiftUI

struct MemoryLibraryView: View {
    @Bindable var model: ConversationModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingRecord: MemoryRecord?
    @State private var pendingDeletion: MemoryRecord?
    @State private var showsClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("只有你确认过的内容才会长期保存。修改或删除后，旧对话将退出后续模型上下文。")
                        .font(.callout)
                    if !model.memoryWritingEnabled {
                        Text("当前已关闭记忆写入；回忆和删除仍然可用。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let message = model.memory.availabilityMessage {
                    Section("读取遇到问题") {
                        Text(message).foregroundStyle(.orange)
                        Button("重试读取") { model.reloadMemories() }
                    }
                } else if model.memory.records.isEmpty {
                    Text("还没有确认过的记忆。可以从聊天中的一句话提取建议。")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.memory.records.sorted { $0.updatedAt > $1.updatedAt }) { record in
                    Section(record.topic) {
                        Text(record.content).textSelection(.enabled)
                        Text(record.evidence.origin == .confirmedUtterance ? "依据：你确认过的话语" : "依据：你在记忆页的修改")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(record.evidence.quote).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(record.updatedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Button("修改") { editingRecord = record }.disabled(!model.memoryWritingEnabled)
                            Button("删除", role: .destructive) { pendingDeletion = record }
                        }
                    }
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.orange)
                }
                Section {
                    Button(model.memory.isAvailable ? "清空全部记忆" : "清空并重建记忆文件", role: .destructive) {
                        showsClearConfirmation = true
                    }
                    .disabled(model.memory.isAvailable && model.memory.records.isEmpty)
                }
            }
            .navigationTitle("本地记忆")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editingRecord) { record in MemoryCorrectionView(model: model, record: record) }
            .confirmationDialog("删除这条记忆？", isPresented: Binding(
                get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("删除记忆", role: .destructive) {
                    if let record = pendingDeletion { model.deleteMemory(record.id) }
                    pendingDeletion = nil
                }
            } message: {
                Text("删除本机记录及其依据，后续请求不再使用。服务方此前收到的数据不受此操作影响。")
            }
            .confirmationDialog("清空所有本地记忆？", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                Button("清空并重建", role: .destructive) { model.clearMemories() }
            } message: {
                Text("此操作会替换现有记忆文件，无法从应用中恢复。保存的位置和角色外观不受影响。")
            }
        }
        .frame(width: 580, height: 700)
    }
}

struct MemoryCandidateView: View {
    @Bindable var model: ConversationModel
    let candidate: MemoryCandidate
    @Environment(\.dismiss) private var dismiss
    @State private var topic: String
    @State private var content: String
    @State private var replacementID: UUID?

    init(model: ConversationModel, candidate: MemoryCandidate) {
        self.model = model
        self.candidate = candidate
        _topic = State(initialValue: candidate.topic)
        _content = State(initialValue: candidate.content)
        _replacementID = State(initialValue: model.memory.matchingTopic(candidate.topic)?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("检查并确认后保存") {
                    TextField("主题（最多 60 字）", text: $topic)
                    TextField("记住的内容（最多 300 字）", text: $content, axis: .vertical).lineLimit(3...6)
                    Picker("保存方式", selection: $replacementID) {
                        Text("新建一条记忆").tag(nil as UUID?)
                        ForEach(model.memory.records) { record in
                            Text("替换：\(record.topic)").tag(record.id as UUID?)
                        }
                    }
                }
                Section("原话依据") {
                    Text(candidate.evidenceQuote).textSelection(.enabled)
                    Text("这是模型提出的建议，请确认它确实表达了你的意思。确认之前不会写入本地记忆。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = model.errorMessage { Text(message).foregroundStyle(.orange) }
            }
            .navigationTitle("记忆建议")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("不保存") { model.dismissCandidate(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认保存") {
                        if model.confirmMemory(candidate.id, topic: topic, content: content, replacing: replacementID) { dismiss() }
                    }
                    .disabled(!model.memoryWritingEnabled || model.candidate?.id != candidate.id)
                    .accessibilityIdentifier("memory.confirm")
                }
            }
        }
        .frame(width: 580, height: 580)
    }
}

private struct MemoryCorrectionView: View {
    @Bindable var model: ConversationModel
    let record: MemoryRecord
    @Environment(\.dismiss) private var dismiss
    @State private var topic: String
    @State private var content: String

    init(model: ConversationModel, record: MemoryRecord) {
        self.model = model
        self.record = record
        _topic = State(initialValue: record.topic)
        _content = State(initialValue: record.content)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("主题（最多 60 字）", text: $topic)
                TextField("记忆内容（最多 300 字）", text: $content, axis: .vertical).lineLimit(3...6)
                Text("保存后由这次明确修改作为依据，旧值不再参与回忆。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = model.errorMessage { Text(message).foregroundStyle(.orange) }
            }
            .navigationTitle("修改记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认修改") {
                        if model.correctMemory(record.id, expectedRevision: record.revision, topic: topic, content: content) { dismiss() }
                    }
                    .disabled(!model.memoryWritingEnabled)
                }
            }
        }
        .frame(width: 540, height: 480)
    }
}

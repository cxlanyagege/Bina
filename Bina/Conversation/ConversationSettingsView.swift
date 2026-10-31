import SwiftUI

struct ConversationSettingsView: View {
    @Bindable var model: ConversationModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedModel: MiMoModel
    @State private var displayName: String
    @State private var newKey = ""
    @State private var allowsMemoryWrites: Bool
    @State private var showsKeyRemoval = false

    init(model: ConversationModel) {
        self.model = model
        _selectedModel = State(initialValue: model.selectedModel)
        _displayName = State(initialValue: model.userDisplayName)
        _allowsMemoryWrites = State(initialValue: model.memoryWritingEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("MiMo 普通按量 API") {
                    Picker("模型", selection: $selectedModel) {
                        ForEach(MiMoModel.allCases) { item in Text(item.displayName).tag(item) }
                    }
                    SecureField(model.hasAPIKey ? "输入新密钥以替换，留空保留" : "sk- 开头的 API Key", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .accessibilityIdentifier("conversation.apiKey")
                    Text(model.hasAPIKey ? "已配置密钥，保存在本机钥匙串。" : "尚未配置密钥。")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.hasAPIKey {
                        Button("移除本机密钥", role: .destructive) { showsKeyRemoval = true }
                    }
                    Link("打开 MiMo 控制台", destination: URL(string: "https://platform.xiaomimimo.com")!)
                }
                Section("称呼与记忆") {
                    TextField("你希望她怎么称呼你", text: $displayName)
                        .accessibilityIdentifier("conversation.displayName")
                    Toggle("允许保存和修改记忆", isOn: $allowsMemoryWrites)
                    Text("记忆建议由你主动提取并确认。关闭写入后，已有记忆仍可回忆和删除。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("数据使用") {
                    Text("发送消息会将角色设定、称呼、最近完整对话和相关记忆片段发送到 Xiaomi。提取记忆会额外发送所选的那句话，并产生一次 API 调用。")
                    Text("聊天记录仅保留在本次运行期间；确认的记忆长期保存在本机。删除本地记忆不会自动删除服务方此前收到的数据。当前不发送音频、摄像头画面或房间网格。")
                    Link("查看 Xiaomi MiMo 隐私政策", destination: URL(string: "https://privacy.mi.com/XiaomiMiMoPlatform/zh_CN/")!)
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.orange)
                }
            }
            .navigationTitle("对话设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存设置") {
                        if model.saveSettings(model: selectedModel, displayName: displayName, newKey: newKey, allowsMemoryWrites: allowsMemoryWrites) {
                            newKey = ""
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("conversation.saveSettings")
                }
            }
        }
        .frame(width: 580, height: 700)
        .onDisappear { newKey = "" }
        .confirmationDialog("移除本机保存的密钥？", isPresented: $showsKeyRemoval, titleVisibility: .visible) {
            Button("移除密钥", role: .destructive) { model.removeAPIKey() }
        } message: {
            Text("不会撤销 Xiaomi 控制台中的密钥。再次聊天前需要重新配置。")
        }
    }
}

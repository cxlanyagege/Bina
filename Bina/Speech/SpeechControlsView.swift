import SwiftUI

struct SpeechControlsView: View {
    @Bindable var speech: SpeechSession
    let hasAPIKey: Bool
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(speech.phase.label, systemImage: speech.phase == .speaking ? "speaker.wave.2" : "waveform")
                    .accessibilityIdentifier("speech.status")
                if let route = speech.playbackRoute, speech.phase == .speaking {
                    Text(route == .character ? "角色位置播放" : "窗口播放").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showsSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("声音设置与试听")
                if speech.isActive {
                    Button("停止") { speech.stop() }.accessibilityIdentifier("speech.stop")
                }
                Button {} label: {
                    Label(speech.isCapturing ? "松开后识别" : "按住说话", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasAPIKey)
                .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 100, pressing: { pressing in
                    if pressing { speech.beginRecording() } else { speech.endRecording() }
                }, perform: {})
                .accessibilityIdentifier("speech.holdToTalk")
                Menu {
                    Button("开始录音") { speech.beginRecording() }
                    Button("结束录音并识别") { speech.endRecording() }.disabled(!speech.isCapturing)
                } label: { Image(systemName: "ellipsis.circle") }
                    .disabled(!hasAPIKey)
                    .accessibilityLabel("录音的替代操作")
            }
            if speech.phase == .recording {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text("录音 \(speech.recordedSeconds) / 30 秒").font(.caption).foregroundStyle(.secondary)
                }
            }
            if speech.phase == .review {
                TextField("检查并修改识别结果", text: $speech.transcript, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("speech.transcriptReview")
                HStack {
                    Text("检查后发送；识别结果不会自动写入记忆。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("发送并听回复") { speech.sendReviewedTranscript() }
                        .disabled(speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || speech.transcript.count > ConversationPrompt.maximumUserCharacters)
                        .accessibilityIdentifier("speech.sendReviewed")
                }
            }
            if let message = speech.errorMessage {
                Text(message).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("speech.error")
            }
            Text("首次授权后请再次按住录音。录音会发送到 Xiaomi 识别；听回复和试听会额外调用语音合成。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .onDisappear { if speech.isCapturing { speech.stop() } }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                Form {
                    Section("预置中文声音") {
                        Picker("声音", selection: Binding(get: { speech.voice }, set: { speech.setVoice($0) })) {
                            ForEach(MiMoVoice.allCases) { voice in Text(voice.rawValue).tag(voice) }
                        }
                        Button("试听当前声音") { speech.audition() }.disabled(!hasAPIKey)
                        Text("试听使用一段固定问候语，会产生一次语音合成调用。此处选择的是预置音色。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("文字回复") {
                        Toggle("自动朗读文字回复", isOn: Binding(
                            get: { speech.readTypedReplies }, set: { speech.setReadTypedReplies($0) }))
                        Text("语音识别后选择“发送并听回复”始终会朗读；普通文字输入默认只显示文字。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(speech.phase.label)
                    if let message = speech.errorMessage { Text(message).foregroundStyle(.orange) }
                    if speech.isActive { Button("停止") { speech.stop() } }
                }
                .navigationTitle("声音设置")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsSettings = false } } }
            }
            .frame(width: 540, height: 500)
        }
    }
}

struct SpeechCaptionView: View {
    let speech: SpeechSession
    var body: some View {
        VStack(spacing: 8) {
            Text(speech.phase.label).font(.headline)
            if !speech.subtitle.isEmpty {
                ScrollView { Text(speech.subtitle).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 150)
            }
            if speech.isActive { Button("停止") { speech.stop() } }
        }
        .frame(width: 340)
        .padding(16)
        .glassBackgroundEffect()
    }
}

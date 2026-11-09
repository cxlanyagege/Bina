import SwiftUI

struct CharacterFaceControls: View {
    @Bindable var face: CharacterFaceMotion
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("眼部状态", selection: $face.eyeState) {
                Text("眼罩 · 闭眼").tag(CharacterFacePlayback.EyeState.coveredClosed)
                Text("无眼罩 · 睁眼").tag(CharacterFacePlayback.EyeState.uncoveredOpen)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("character.eyeState")
            Toggle("自然眨眼", isOn: $face.automaticBlink)
                .disabled(face.eyeState == .coveredClosed)
            Toggle("表情跟随对话", isOn: $face.followsDialogue)
                .accessibilityIdentifier("character.dialogueExpression")
            Picker("手动表情", selection: $face.expression) {
                Text("中性").tag(CharacterFacePlayback.Expression.neutral)
                Text("轻微微笑").tag(CharacterFacePlayback.Expression.gentleSmile)
                Text("好奇").tag(CharacterFacePlayback.Expression.curious)
            }
            .pickerStyle(.segmented)
            .disabled(face.followsDialogue)
            Picker("口型预览", selection: $face.mouthPose) {
                Text("放松").tag(CharacterFacePlayback.MouthPose.relaxed)
                Text("张口").tag(CharacterFacePlayback.MouthPose.open)
                Text("圆口").tag(CharacterFacePlayback.MouthPose.round)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("眨眼预览") { face.previewBlink() }
                    .disabled(face.eyeState != .uncoveredOpen)
                Button("还原面部设置") { face.resetPreview() }
            }
            Text("眼罩状态保持闭眼；无眼罩状态自然眨眼。表情可跟随对话，关闭后可手动预览；口型为手动预览。暂停会冻结面部，参考姿势显示原模型。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!isPlaying)
    }
}

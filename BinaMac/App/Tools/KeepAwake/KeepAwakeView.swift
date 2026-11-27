import SwiftUI

struct KeepAwakeView: View {
    @Bindable var model: KeepAwakeModel

    var body: some View {
        Form {
            Section {
                Toggle("保持常亮", isOn: $model.keepsDisplayAwake)
                    .toggleStyle(.switch)

                Toggle("不要入眠", isOn: $model.keepsSystemAwake)
                    .toggleStyle(.switch)

                Toggle("缓慢刷新", isOn: $model.slowsRefreshRate)
                    .toggleStyle(.switch)
            }

            Section {
                LabeledContent("屏幕") {
                    Text(model.keepsDisplayAwake ? "保持常亮中" : "跟随系统设置")
                }
                .accessibilityElement(children: .combine)

                LabeledContent("闲置睡眠") {
                    Text(idleSleepStatus)
                }
                .accessibilityElement(children: .combine)
            } footer: {
                Text("开启「不要入眠」可阻止熄屏后的闲置睡眠。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("保持清醒")
        .alert(
            "无法更改清醒设置",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var idleSleepStatus: LocalizedStringKey {
        if model.keepsSystemAwake {
            return "阻止闲置睡眠"
        }
        return model.keepsDisplayAwake ? "常亮期间保持清醒" : "跟随系统设置"
    }
}

struct KeepAwakeCommands: Commands {
    let model: KeepAwakeModel

    var body: some Commands {
        @Bindable var model = model
        CommandMenu("控制") {
            Toggle("保持常亮", isOn: $model.keepsDisplayAwake)
            Toggle("不要入眠", isOn: $model.keepsSystemAwake)
            Toggle("缓慢刷新", isOn: $model.slowsRefreshRate)
        }
    }
}

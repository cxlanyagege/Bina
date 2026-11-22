import SwiftUI

struct KeepAwakeView: View {
    @Bindable var model: KeepAwakeModel

    var body: some View {
        Form {
            Section {
                Toggle("保持常亮", isOn: $model.keepsDisplayAwake)
                    .toggleStyle(.switch)

                Toggle("自动入睡", isOn: $model.allowsAutomaticSleep)
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
                Text("关闭「自动入睡」可阻止熄屏后的闲置睡眠。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("保持苏醒")
        .alert(
            "无法更改苏醒设置",
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
        if !model.allowsAutomaticSleep {
            return "阻止闲置睡眠"
        }
        return model.keepsDisplayAwake ? "常亮期间保持苏醒" : "跟随系统设置"
    }
}

struct KeepAwakeCommands: Commands {
    let model: KeepAwakeModel

    var body: some Commands {
        @Bindable var model = model
        CommandMenu("控制") {
            Toggle("保持常亮", isOn: $model.keepsDisplayAwake)
            Toggle("自动入睡", isOn: $model.allowsAutomaticSleep)
        }
    }
}

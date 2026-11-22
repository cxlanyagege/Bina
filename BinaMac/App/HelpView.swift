import SwiftUI

struct HelpView: View {
    static let windowID = "help"
    static let title: LocalizedStringKey = "Bina 帮助"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("使用 Bina")
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                topic(
                    "开启保持常亮",
                    "在「保持苏醒」页面打开「保持常亮」，或在菜单栏的「控制」菜单切换。屏幕保持常亮时，Mac 也会保持苏醒。"
                )

                topic(
                    "控制熄屏后的睡眠",
                    "「不要入眠」默认关闭。开启它可以让 Mac 在熄屏后继续运行。关闭它后，macOS 会按系统设置管理熄屏后的闲置睡眠。"
                )

                topic(
                    "从控制中心切换",
                    "打开「控制中心」，点按「编辑控制」，找到「Bina」的「保持常亮」。将它拖入控制中心并点按「完成」，之后即可点按该控制项切换。"
                )

                topic(
                    "结束本次苏醒",
                    "关闭主窗口后，当前设置会继续生效。退出 Bina 后，本次苏醒会结束。手动睡眠、合盖和系统电源策略均由 macOS 管理。"
                )
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
        .frame(minWidth: 380, minHeight: 260)
    }

    private func topic(_ title: LocalizedStringKey, _ description: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .lineSpacing(4)
        }
    }
}

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(HelpView.title) {
                openWindow(id: HelpView.windowID)
            }
        }
    }
}

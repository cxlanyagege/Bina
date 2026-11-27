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
                    "查看已安装的应用",
                    "在侧栏选择「应用管理」，可按名称浏览或搜索自行安装的应用。点按一行查看版本、位置和包标识符，再用工具栏的返回按钮回到列表。"
                )

                topic(
                    "检查应用更新",
                    "应用清单刷新时会自动检查更新。同一窗口内会缓存清单和结果 15 分钟，过期后再次进入「应用管理」会刷新。检测到应用安装、移除或版本变更时也会刷新。点按搜索框左边的向上箭头可查看版本变化。在「应用详情」，点按废纸篓左边的向上箭头可查看这份应用的结果和来源。"
                )

                topic(
                    "卸载应用",
                    "扫描位置受限时，「应用管理」会打开系统设置。可在「隐私与安全」的「完全磁盘访问权限」中允许 Bina。在应用详情中点按废纸篓图标可查找关联文件。取消勾选要保留的文件，再点按「移到废纸篓」。"
                )

                topic(
                    "开启保持常亮",
                    "在「保持清醒」页面打开「保持常亮」，或在菜单栏的「控制」菜单切换。屏幕保持常亮时，Mac 也会保持清醒。"
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
                    "结束本次清醒",
                    "关闭主窗口后，当前设置会继续生效。退出 Bina 后，本次清醒会结束。手动睡眠、合盖和系统电源策略均由 macOS 管理。"
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

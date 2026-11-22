import KeepAwakePower
import SwiftUI
import WidgetKit

@main
struct BinaMacControls: WidgetBundle {
    var body: some Widget {
        KeepAwakeControl()
    }
}

struct KeepAwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: KeepAwakeControlConfiguration.kind, provider: KeepAwakeValueProvider()) {
            isEnabled in
            ControlWidgetToggle("保持常亮", isOn: isEnabled, action: SetKeepAwakeIntent()) { isOn in
                Label(isOn ? "已开启" : "跟随系统", systemImage: isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
            }
        }
        .displayName("保持常亮")
        .description("一键保持屏幕常亮，关闭后按系统设置熄屏。")
    }
}

struct KeepAwakeValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        try IdleSleepAssertionStatus.isEnabled(for: .display)
    }
}

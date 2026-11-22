import SwiftUI

struct MainWindowContent: View {
    private enum Tool {
        case keepAwake
    }

    let keepAwake: KeepAwakeModel
    @State private var selection: Tool? = .keepAwake

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("工具") {
                    NavigationLink(value: Tool.keepAwake) {
                        Label("保持苏醒", systemImage: "cup.and.saucer")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 184, max: 260)
        } detail: {
            switch selection {
            case .keepAwake, .none:
                KeepAwakeView(model: keepAwake)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

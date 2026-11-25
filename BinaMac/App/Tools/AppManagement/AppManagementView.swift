import AppKit
import SwiftUI

struct AppManagementView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var didRequestDiskAccess: Bool
    @State private var catalog: InstalledApplicationCatalog?
    @State private var searchText = ""
    @State private var path: [InstalledApplication] = []
    @State private var selectedApplication: InstalledApplication?
    @State private var hasRestrictedScanAccess = false
    @State private var showSettingsError = false
    @FocusState private var isListFocused: Bool
    @AccessibilityFocusState(for: .voiceOver) private var focusedApplication: URL?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let catalog {
                    applicationList(catalog)
                } else {
                    ProgressView("正在查找应用…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasRestrictedScanAccess { diskAccessFooter }
            }
            .onChange(of: searchText) {
                selectedApplication = nil
            }
            .navigationTitle("应用管理")
            .toolbar {
                if path.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ApplicationSearchField(text: $searchText)
                            .frame(width: 160)
                    }
                }
            }
            .navigationDestination(for: InstalledApplication.self) { application in
                let hasOtherCopies =
                    catalog?.applications.contains {
                        $0.id != application.id && $0.bundleIdentifier != nil
                            && $0.bundleIdentifier?.lowercased() == application.bundleIdentifier?.lowercased()
                    } == true
                AppDetailsView(application: application, hasOtherCopies: hasOtherCopies) {
                    if let catalog {
                        self.catalog = InstalledApplicationCatalog(
                            applications: catalog.applications.filter { $0.id != application.id },
                            hasUnreadableLocations: catalog.hasUnreadableLocations)
                    }
                    path.removeAll()
                }
            }
        }
        .onChange(of: path) { previousPath, path in
            if path.isEmpty, let application = previousPath.last {
                selectedApplication = catalog?.applications.contains(application) == true ? application : nil
            }
        }
        .alert("无法打开权限设置", isPresented: $showSettingsError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在「系统设置 → 隐私与安全 → 完全磁盘访问权限」中添加 Bina。")
        }
        .task {
            let result = await InstalledApplicationCatalog.load()
            if !Task.isCancelled {
                catalog = result
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let isRestricted = await AppManagementDiskAccess.hasRestrictedScanAccess()
            guard !Task.isCancelled else { return }
            hasRestrictedScanAccess = isRestricted
            if isRestricted && !didRequestDiskAccess { openDiskAccessSettings() }
        }
    }

    private var diskAccessFooter: some View {
        HStack {
            Label("部分扫描位置受限。可检查 Bina 的完全磁盘访问权限。", systemImage: "lock")
                .foregroundStyle(.secondary)
            Spacer()
            Button("打开设置…", action: openDiskAccessSettings)
                .controlSize(.small)
                .help("打开完全磁盘访问权限设置")
        }
        .font(.footnote)
        .padding(12)
        .background(.bar)
    }

    private func openDiskAccessSettings() {
        didRequestDiskAccess = true
        showSettingsError = !AppManagementDiskAccess.openSettings()
    }

    @ViewBuilder
    private func applicationList(_ catalog: InstalledApplicationCatalog) -> some View {
        let matches = catalog.matching(searchText)
        if catalog.applications.isEmpty && catalog.hasUnreadableLocations {
            ContentUnavailableView(
                "无法读取应用", systemImage: "exclamationmark.triangle",
                description: Text("部分位置暂时无法读取。"))
        } else if catalog.applications.isEmpty {
            ContentUnavailableView("未找到已安装的应用", systemImage: "square.grid.2x2")
        } else if matches.isEmpty {
            ContentUnavailableView(
                "未找到匹配的应用", systemImage: "magnifyingglass",
                description: Text("请尝试其他应用名称。"))
        } else {
            ScrollViewReader { scrollView in
                List(matches, selection: $selectedApplication) { application in
                    Button {
                        path = [application]
                    } label: {
                        HStack {
                            Label {
                                Text(verbatim: application.name)
                            } icon: {
                                InstalledApplicationIcon(application: application, size: 24)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(application)
                    .id(application.id)
                    .help(application.url.path)
                    .accessibilityFocused($focusedApplication, equals: application.id)
                }
                .listStyle(.inset)
                .focusable(interactions: .edit)
                .focusEffectDisabled()
                .focused($isListFocused)
                .defaultFocus($isListFocused, true, priority: .userInitiated)
                .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                    let offset = press.key == .upArrow ? -1 : 1
                    let currentIndex = selectedApplication.flatMap { matches.firstIndex(of: $0) }
                    let nextIndex = currentIndex.map { min(max($0 + offset, 0), matches.count - 1) } ?? 0
                    let application = matches[nextIndex]
                    selectedApplication = application
                    scrollView.scrollTo(application.id)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let selectedApplication, matches.contains(selectedApplication) else { return .ignored }
                    path = [selectedApplication]
                    return .handled
                }
                .task(id: path.isEmpty) {
                    guard path.isEmpty, let selectedApplication else { return }
                    isListFocused = true
                    focusedApplication = selectedApplication.id
                }
                .safeAreaInset(edge: .bottom, alignment: .leading) {
                    if catalog.hasUnreadableLocations && !hasRestrictedScanAccess {
                        Text("有些位置无法读取，应用列表可能不完整。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
        }
    }
}

private struct ApplicationSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        let prompt = String(localized: "搜索应用")
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
        field.sendsSearchStringImmediately = true
        // AppKit sends the clear action even when the field has been recreated after returning from details.
        field.target = context.coordinator
        field.action = #selector(Coordinator.updateSearchText(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func updateSearchText(_ field: NSSearchField) {
            text.wrappedValue = field.stringValue
        }
    }
}

private struct AppDetailsView: View {
    let application: InstalledApplication
    let hasOtherCopies: Bool
    let onUninstalled: () -> Void
    @State private var showingUninstall = false
    @State private var applicationWasMoved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label {
                    Text(verbatim: application.name)
                        .font(.title2.weight(.semibold))
                } icon: {
                    InstalledApplicationIcon(application: application, size: 48)
                }
                .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 0) {
                    metadataRow("版本", value: application.version)
                    Divider()
                    metadataRow("位置", value: application.url.path)
                    Divider()
                    metadataRow("包标识符", value: application.bundleIdentifier)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("应用详情")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("卸载…", systemImage: "trash") { showingUninstall = true }
                    .labelStyle(.iconOnly)
                    .help("卸载…")
                    .disabled(application.url.path == Bundle.main.bundleURL.resolvingSymlinksInPath().path)
            }
        }
        .sheet(isPresented: $showingUninstall, onDismiss: completeUninstall) {
            AppUninstallSheet(application: application, hasOtherCopies: hasOtherCopies) {
                applicationWasMoved = true
            }
        }
    }

    private func completeUninstall() {
        if applicationWasMoved {
            onUninstalled()
        }
    }

    private func metadataRow(_ label: LocalizedStringKey, value: String?) -> some View {
        LabeledContent(label) {
            if let value {
                Text(verbatim: value)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("未提供")
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

private struct InstalledApplicationIcon: View {
    let application: InstalledApplication
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

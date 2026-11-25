import AppKit
import SwiftUI

struct AppUninstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var review: ApplicationUninstallReview
    @State private var highlightedFile: URL?
    let onApplicationMoved: () -> Void

    init(
        application: InstalledApplication, hasOtherCopies: Bool, onApplicationMoved: @escaping () -> Void
    ) {
        _review = State(
            initialValue: ApplicationUninstallReview(
                application: application, catalogHasOtherCopies: hasOtherCopies))
        self.onApplicationMoved = onApplicationMoved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let outcomes = review.outcomes {
                resultList(outcomes)
            } else {
                candidateList
            }
            if let message = review.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 600, idealWidth: 650, minHeight: 420, idealHeight: 480)
        .interactiveDismissDisabled(review.activity != nil)
        .task { await review.rescan() }
        .onChange(of: review.appWasMoved) { _, moved in
            if moved { onApplicationMoved() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            itemIcon(for: review.application.url, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("卸载「\(review.application.name)」")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if review.appWasMoved {
                    Text("应用已移到废纸篓。")
                        .foregroundStyle(.secondary)
                } else if review.outcomes != nil {
                    Text("移动应用失败，请查看下方结果。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var candidateList: some View {
        List(selection: $highlightedFile) {
            if let uninstaller = review.scan?.uninstaller {
                Section("专用卸载器") {
                    HStack {
                        Text("可以先检查应用提供的卸载器。")
                        Spacer()
                        Button("在访达中显示") {
                            revealInFinder(uninstaller)
                        }
                    }
                }
            }
            if review.scan != nil && review.hasOtherCopies {
                Text("还有一份同 Bundle ID 的应用。关联文件可能由多个副本共用。")
                    .foregroundStyle(.secondary)
            }
            itemRow(url: review.application.url, size: review.scan?.applicationSize) {
                Toggle(review.application.url.lastPathComponent, isOn: .constant(true))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(true)
            }
            ForEach(review.scan?.candidates ?? []) { candidate in
                candidateRow(candidate)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: URL.self) { urls in
            if let url = urls.first {
                Button("在访达中显示") { revealInFinder(url) }
                Button("复制路径") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url.path, forType: .string)
                }
            }
        } primaryAction: { urls in
            if let url = urls.first { revealInFinder(url) }
        }
        .disabled(review.activity != nil)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func candidateRow(_ candidate: UninstallCandidate) -> some View {
        itemRow(url: candidate.file.url, size: candidate.size) {
            if candidate.disposition == .reviewOnly {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("需单独处理")
                    .help("需单独处理")
            } else {
                Toggle(
                    candidate.file.url.lastPathComponent,
                    isOn: Binding(
                        get: { review.selection.contains(candidate.id) },
                        set: { selected in
                            if selected {
                                review.selection.insert(candidate.id)
                            } else {
                                review.selection.remove(candidate.id)
                            }
                        })
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
        }
    }

    private func resultList(_ outcomes: [ApplicationTrashPlan.Outcome]) -> some View {
        List(outcomes) { outcome in
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    outcome.originalURL.lastPathComponent,
                    systemImage: outcome.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                Text(verbatim: outcome.originalURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                switch outcome.status {
                case .moved:
                    Text("已移到废纸篓").font(.caption)
                case .failed(let reason):
                    Text(reason).font(.caption).foregroundStyle(.red)
                case .skipped:
                    Text("尚未处理").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            if review.activity == .scanning {
                ProgressView("正在扫描…").controlSize(.small)
            } else if review.activity == .moving {
                ProgressView("正在移到废纸篓…").controlSize(.small)
            } else if review.outcomes == nil, review.scan != nil {
                Text("共\(review.itemCount)个 · 已选择\(review.selectedItemCount)个项目 · \(selectedSizeText)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if review.outcomes == nil {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(review.activity != nil)
                Button("移到废纸篓", role: .destructive) {
                    Task { await review.moveSelection() }
                }
                .disabled(review.scan == nil || review.activity != nil)
            } else {
                if !review.appWasMoved {
                    Button("返回确认") { review.returnToReview() }
                }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var selectedSizeText: String {
        let size = review.selectedSize
        if !size.isComplete && size.knownBytes == 0 {
            return String(localized: "大小未知")
        }
        let formatted = ByteCountFormatter.string(fromByteCount: size.knownBytes, countStyle: .file)
        return size.isComplete ? formatted : String(localized: "至少 \(formatted)")
    }

    private func itemRow<Accessory: View>(
        url: URL, size: Int64?, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            accessory()
                .frame(width: 20)
            itemIcon(for: url, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: url.lastPathComponent)
                Text(verbatim: url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(
                size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                    ?? String(localized: "大小未知")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .tag(url)
    }

    private func itemIcon(for url: URL, size: CGFloat) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

import AppKit
import SwiftUI

struct ApplicationUpdateButton: View {
    let title: LocalizedStringKey
    let isChecking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isChecking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up")
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
        }
        .accessibilityLabel(isChecking ? "正在检查更新" : title)
        .help(isChecking ? "正在检查更新" : title)
    }
}

struct ApplicationUpdatesPopover: View {
    enum Scope {
        case catalog(AppManagementModel)
        case application(InstalledApplication)
    }

    let scope: Scope
    let checks: ApplicationUpdateChecks
    @State private var showAppStoreError = false

    private var applications: [InstalledApplication] {
        switch scope {
        case .catalog(let model): model.catalog?.applications ?? []
        case .application(let application): [application]
        }
    }

    private var isChecking: Bool {
        switch scope {
        case .catalog(let model): model.catalog == nil || model.isRefreshing || checks.isChecking
        case .application(let application): checks.isChecking(application)
        }
    }

    var body: some View {
        let available = checks.availableUpdates(for: applications)
        VStack(alignment: .leading, spacing: 12) {
            if !available.isEmpty {
                ViewThatFits(in: .vertical) {
                    updateRows(available)
                    ScrollView { updateRows(available) }
                }
                .frame(maxHeight: 300)
            }

            if case .application(let application) = scope, let result = checks.results[application.id] {
                if available.isEmpty {
                    updateMessage(for: result.outcome)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let version = result.outcome.publishedVersion?.displayVersion {
                        LabeledContent("来源版本", value: version)
                    }
                }
                if let source = result.source {
                    LabeledContent("更新来源", value: sourceName(source))
                    sourceLink(source)
                }
            } else if isChecking || available.isEmpty {
                Text(isChecking ? "正在检查应用更新…" : "暂无已发现的更新。")
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(width: 310)
        .alert("无法打开 App Store", isPresented: $showAppStoreError) {
            Button("好", role: .cancel) {}
        }
    }

    private func updateRows(_ available: [ApplicationUpdateChecks.AvailableUpdate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(available) { update in
                HStack(spacing: 10) {
                    InstalledApplicationIcon(application: update.application, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: update.application.name)
                            .fontWeight(.medium)
                        versionChange(update)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .help(update.application.url.path)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func versionChange(_ update: ApplicationUpdateChecks.AvailableUpdate) -> some View {
        let installed = update.installedVersion
        let available = update.availableVersion
        if let current = installed.displayVersion, let latest = available.displayVersion {
            if current == latest, let currentBuild = installed.buildVersion, let latestBuild = available.buildVersion {
                Text("\(current)（构建号 \(currentBuild) → \(latestBuild)）")
            } else {
                Text("\(current) → \(latest)")
            }
        }
    }

    private func sourceName(_ source: ApplicationUpdateResult.Source) -> String {
        switch source {
        case .sparkle(let host): host.map { "Sparkle · \($0)" } ?? "Sparkle"
        case .homebrew(let token): "Homebrew Cask · \(token)"
        case .appStore(_, let country): country.map { "Mac App Store · \($0)" } ?? "Mac App Store"
        case .github(let repository, _): "GitHub · \(repository)"
        case .website(let page): page.host() ?? String(localized: "官网")
        }
    }

    @ViewBuilder
    private func sourceLink(_ source: ApplicationUpdateResult.Source) -> some View {
        switch source {
        case .appStore(let id, _): Button("打开 App Store") { openAppStore(id: id) }
        case .github(_, let url): Link("查看发布页", destination: url)
        case .website(let url): Link("查看官网", destination: url)
        case .homebrew, .sparkle: EmptyView()
        }
    }

    private func openAppStore(id: UInt64?) {
        let workspace = NSWorkspace.shared
        if let id, let listing = URL(string: "macappstore://apps.apple.com/app/id\(id)"), workspace.open(listing) {
            return
        }
        if let store = workspace.urlForApplication(withBundleIdentifier: "com.apple.AppStore"), workspace.open(store) {
            return
        }
        showAppStoreError = true
    }

    private func updateMessage(for outcome: ApplicationUpdateResult.Outcome) -> Text {
        switch outcome {
        case .available: Text("发现可用更新。")
        case .noUpdate: Text("当前频道未发现更新。")
        case .incompatible(_, .minimumMacOS(let version)): Text("发现新版，需要 macOS \(version) 或更新版本。")
        case .incompatible(_, .maximumMacOS(let version)): Text("发现新版，支持的最高系统版本为 macOS \(version)。")
        case .incompatible(_, .appleSilicon): Text("发现新版，需要搭载 Apple 芯片的 Mac。")
        case .incompatible(_, .minimumBuild(let build)): Text("发现新版，需要先升级到构建号 \(build) 或更新的版本。")
        case .informational: Text("更新源发布了新版公告。")
        case .noSource: Text("更新来源待确认。")
        case .invalidFeedURL: Text("Sparkle 更新地址无效或未使用 HTTPS。")
        case .unreadableApplication: Text("无法读取这份应用的信息。")
        case .uncomparableVersion: Text("这份应用或更新来源未提供可比较的版本号。")
        case .requestFailed: Text("无法获取更新源。请稍后再试。")
        case .invalidAppcast: Text("无法读取 Sparkle 更新源的数据。")
        case .homebrewUnavailable: Text("无法核对 Homebrew 更新记录。")
        case .noStoreListing: Text("未能从 App Store 公开目录核对版本。")
        case .noMatchingRelease: Text("更新源没有返回与此应用匹配的版本。")
        case .manualCheck: Text("可前往官网查看版本。")
        }
    }
}

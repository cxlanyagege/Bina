import AppKit
import Observation

@MainActor
@Observable
final class ApplicationUninstallReview {
    enum Activity {
        case scanning, moving
    }

    let application: InstalledApplication
    let scanDirectories: [URL]
    private let catalogHasOtherCopies: Bool
    private(set) var scan: ApplicationUninstallScan?
    private(set) var activity: Activity?
    private(set) var outcomes: [ApplicationTrashPlan.Outcome]?
    private(set) var errorMessage: String?
    private(set) var hasOtherCopies = false
    var selection: Set<URL> = []

    init(
        application: InstalledApplication, catalogHasOtherCopies: Bool,
        scanDirectories: [URL] = ApplicationResidueScanner.defaultDirectories
    ) {
        self.application = application
        self.catalogHasOtherCopies = catalogHasOtherCopies
        self.scanDirectories = scanDirectories.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    var appWasMoved: Bool { outcomes?.first?.succeeded == true }
    var itemCount: Int { (scan?.candidates.count ?? 0) + 1 }
    var selectedItemCount: Int { selectedCandidates.count + 1 }

    var selectedSize: (knownBytes: Int64, isComplete: Bool) {
        let relatedSizes = ApplicationTrashPlan.outermostItems(in: selectedCandidates).map(\.size)
        let sizes = [scan?.applicationSize] + relatedSizes
        return (sizes.compactMap { $0 }.reduce(0, +), sizes.allSatisfy { $0 != nil })
    }

    func rescan() async {
        guard activity == nil else { return }
        activity = .scanning
        defer { activity = nil }
        errorMessage = nil
        let otherCopies = otherCopiesExist
        let previous = scan.map { Dictionary(uniqueKeysWithValues: $0.candidates.map { ($0.id, $0.file) }) }
        do {
            let result = try await ApplicationResidueScanner.scan(
                application: application, directories: scanDirectories, hasOtherCopies: otherCopies)
            try Task.checkCancellation()
            let selectable = result.candidates.filter { $0.disposition == .optional }
            if let previous {
                selection.formIntersection(selectable.filter { previous[$0.id] == $0.file }.map(\.id))
            } else {
                selection = Set(selectable.map(\.id))
            }
            hasOtherCopies = otherCopies
            scan = result
        } catch is CancellationError {
            return
        } catch {
            scan = nil
            selection = []
            errorMessage = error.localizedDescription
        }
    }

    func moveSelection() async {
        guard activity == nil, let scan, outcomes == nil else { return }
        errorMessage = nil
        guard !isRunning else {
            errorMessage = String(localized: "请先退出此应用，再移到废纸篓。")
            return
        }
        let selected = selectedCandidates
        guard selected.isEmpty || !otherCopiesExist else {
            errorMessage = String(localized: "还有一份同 Bundle ID 的应用。请重新打开卸载预览，核对共享文件。")
            return
        }

        activity = .moving
        defer { activity = nil }
        let plan = ApplicationTrashPlan(
            application: scan.application, relatedItems: selected, scanDirectories: scanDirectories)
        outcomes = await plan.execute()
    }

    func returnToReview() {
        guard !appWasMoved else { return }
        outcomes = nil
    }

    private var selectedCandidates: [UninstallCandidate] {
        scan?.candidates.filter { $0.disposition == .optional && selection.contains($0.id) } ?? []
    }

    private var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.resolvingSymlinksInPath().path == application.url.path
        }
    }

    private var otherCopiesExist: Bool {
        guard let bundleIdentifier = application.bundleIdentifier else { return false }
        return catalogHasOtherCopies
            || NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier).contains { url in
                let canonical = url.resolvingSymlinksInPath()
                return canonical.path != application.url.path && FileManager.default.fileExists(atPath: canonical.path)
            }
    }
}

import AppKit
import Darwin

enum AppManagementDiskAccess {
    /// Probes a location used by residue scans without reading the directory contents.
    @concurrent
    static func hasRestrictedScanAccess(
        in library: URL = FileManager.default.homeDirectoryForCurrentUser.appending(component: "Library")
    ) async -> Bool {
        let cookies = library.appending(component: "Cookies", directoryHint: .isDirectory)
        let descriptor = open(cookies.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        // The privacy setting does not override POSIX permissions or ACLs.
        guard descriptor >= 0 else { return errno == EPERM }
        close(descriptor)
        return false
    }

    @MainActor
    static func openSettings() -> Bool {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        else { return false }
        return NSWorkspace.shared.open(url)
    }
}

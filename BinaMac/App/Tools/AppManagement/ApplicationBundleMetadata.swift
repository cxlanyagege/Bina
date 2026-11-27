import Foundation

struct ApplicationVersion: Hashable, Sendable {
    let shortVersion: String?
    let buildVersion: String?

    var displayVersion: String? { shortVersion ?? buildVersion }
}

struct ApplicationBundleMetadata: Sendable {
    let version: ApplicationVersion
    let bundleIdentifier: String?
    let sparkleFeed: String?

    init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let string = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !string.isEmpty
            else { return nil }
            return string
        }

        version = ApplicationVersion(
            shortVersion: value("CFBundleShortVersionString"), buildVersion: value("CFBundleVersion"))
        bundleIdentifier = value("CFBundleIdentifier")
        sparkleFeed = value("SUFeedURL")
    }

    init(reading applicationURL: URL) throws {
        // Bundle can cache its info dictionary across replacements of an app at the same path.
        let data = try Data(contentsOf: applicationURL.appending(path: "Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        self.init(info: info)
    }
}

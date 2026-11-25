import Foundation
import Security

/// The names and identifiers that an application and its embedded components can use for local files.
struct ApplicationResidueIdentity {
    private static let componentDirectories = [
        "Contents/Library/LoginItems",
        "Contents/PlugIns",
        "Contents/XPCServices",
        "Contents/Helpers",
        "Contents/Library/SystemExtensions",
    ]
    private static let componentExtensions: Set<String> = ["app", "appex", "xpc", "systemextension"]
    private static let artifactExtensions: Set<String> = [
        "plist", "log", "savedstate", "binarycookies", "cookies", "sfl", "sfl2", "sfl3",
        "ips", "crash", "hang", "spin", "diag", "bom", "pkg", "db", "sqlite", "sqlite3", "json",
        "prefpane", "qlgenerator", "plugin", "workflow",
    ]
    private static let diagnosticExtensions: Set<String> = ["ips", "crash", "hang", "spin", "diag", "plist"]
    private static let versionSuffix = #"[\s_-]+[0-9]+(?:\.[0-9]+)*$"#
    private static let diagnosticSuffix =
        #"[-_](?:[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:[-_t].*)?$"#

    let bundleID: String?
    let groupIDs: Set<String>
    let unreadableLocations: [URL]
    private let componentIDs: Set<String>
    private let names: Set<String>
    private let diagnosticNames: Set<String>
    private let identifierPatterns: [NSRegularExpression]

    init(application: InstalledApplication, info: [String: Any], localizedInfo: [String: Any]?) {
        let primaryID = application.bundleIdentifier?.lowercased()
        bundleID = primaryID
        let displayNames = [
            application.name, application.url.deletingPathExtension().lastPathComponent,
            info["CFBundleName"] as? String, info["CFBundleDisplayName"] as? String,
            localizedInfo?["CFBundleName"] as? String, localizedInfo?["CFBundleDisplayName"] as? String,
        ].compactMap { $0 }
        names = Set(displayNames.map(Self.normalizedName).filter { $0.count >= 2 })

        // Executable names help identify diagnostic reports. Common launcher names are shared by unrelated apps.
        let genericExecutables: Set<String> = [
            "app", "electron", "helper", "javaappstub", "launcher", "main", "updater",
        ]
        let processName = (info["CFBundleExecutable"] as? String).map(Self.normalizedName)
        if let processName, processName.count >= 3, !genericExecutables.contains(processName) {
            diagnosticNames = names.union([processName])
        } else {
            diagnosticNames = names
        }

        var identifiers: Set<String> = []
        var groups = Self.applicationGroups(at: application.url)
        var unreadable: [URL] = []
        for path in Self.componentDirectories {
            do {
                let directory = try UninstallFile.directory(at: path, in: application.url)
                let entries = try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles)
                for url in entries where Self.componentExtensions.contains(url.pathExtension.lowercased()) {
                    guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                        let component = Bundle(url: url),
                        let identifier = component.bundleIdentifier?.lowercased(), identifier != primaryID
                    else { continue }
                    identifiers.insert(identifier)
                    groups.formUnion(Self.applicationGroups(at: url))
                }
            } catch {
                if !InstalledApplicationCatalog.isMissingFile(error) {
                    unreadable.append(application.url.appending(path: path))
                }
            }
        }
        componentIDs = identifiers
        groupIDs = groups
        unreadableLocations = unreadable
        if let primaryID { identifiers.insert(primaryID) }
        identifierPatterns = identifiers.filter { $0.contains(".") }.compactMap { identifier in
            let escaped = NSRegularExpression.escapedPattern(for: identifier)
            return try? NSRegularExpression(pattern: "(?:^|[ ._-])\(escaped)(?:$|[ ._-])")
        }
    }

    func exactIdentifierEvidence(for name: String, isHostPreference: Bool = false) -> UninstallCandidate.Evidence? {
        let stem = Self.artifactStem(name)
        if let bundleID {
            if name == bundleID || stem == bundleID { return .bundleIdentifier }
            if isHostPreference, stem.hasPrefix(bundleID + "."),
                UUID(uuidString: String(stem.dropFirst(bundleID.count + 1))) != nil
            {
                return .bundleIdentifier
            }
        }
        return componentIDs.contains(name) || componentIDs.contains(stem) ? .componentBundleIdentifier : nil
    }

    func matchesIdentifierVariant(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return identifierPatterns.contains { $0.firstMatch(in: name, range: range) != nil }
    }

    func matchesName(of url: URL, isDirectory: Bool) -> Bool {
        let name = url.lastPathComponent
        let stem =
            isDirectory
            ? Self.artifactStem(name.lowercased()) : url.deletingPathExtension().lastPathComponent
        return names.contains(Self.normalizedName(name)) || names.contains(Self.normalizedName(stem))
    }

    func matchesDiagnosticName(of url: URL) -> Bool {
        guard Self.diagnosticExtensions.contains(url.pathExtension.lowercased()) else { return false }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        guard let suffix = stem.range(of: Self.diagnosticSuffix, options: .regularExpression) else { return false }
        return diagnosticNames.contains(Self.normalizedName(String(stem[..<suffix.lowerBound])))
    }

    private static func normalizedName(_ rawName: String) -> String {
        let folded = rawName.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let base =
            folded.range(of: versionSuffix, options: .regularExpression)
            .map { folded[..<$0.lowerBound] } ?? folded[...]
        return String(base.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func artifactStem(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), artifactExtensions.contains(String(name[name.index(after: dot)...]))
        else { return name }
        return String(name[..<dot])
    }

    private static func applicationGroups(at url: URL) -> Set<String> {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return [] }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let entitlements = (information as? [String: Any])?[kSecCodeInfoEntitlementsDict as String]
                as? [String: Any],
            let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return Set(groups.map { $0.lowercased() })
    }
}

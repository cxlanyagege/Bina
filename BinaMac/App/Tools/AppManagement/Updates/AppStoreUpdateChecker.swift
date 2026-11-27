import CoreServices
import Foundation
import OSLog
import StoreKit

/// Compares an installed Mac App Store copy with the public catalog for its storefront.
struct AppStoreUpdateChecker: Sendable {
    private struct LookupResponse: Decodable {
        let results: [Listing]
    }

    private struct Listing: Decodable {
        let trackId: UInt64?
        let bundleId: String?
        let kind: String?
        let version: String?
        let minimumOsVersion: String?
    }

    private static let logger = Logger(subsystem: "BinaMac", category: "AppStoreUpdateCheck")
    private let spotlightID: @Sendable (URL) -> UInt64?
    private let currentCountry: @Sendable () async -> String
    private let fetch: @Sendable (URL) async throws -> Data

    init(
        spotlightID: @escaping @Sendable (URL) -> UInt64? = Self.appStoreID,
        currentCountry: @escaping @Sendable () async -> String = Self.storefrontCountry,
        fetch: @escaping @Sendable (URL) async throws -> Data = UpdateHTTPClient.fetch
    ) {
        self.spotlightID = spotlightID
        self.currentCountry = currentCountry
        self.fetch = fetch
    }

    @concurrent
    func checkIfInstalled(_ applicationURL: URL, metadata: ApplicationBundleMetadata) async -> ApplicationUpdateResult?
    {
        guard Self.hasReceipt(in: applicationURL) else { return nil }
        let id = spotlightID(applicationURL)
        guard let id, let bundleIdentifier = metadata.bundleIdentifier else {
            return ApplicationUpdateResult(
                installedVersion: metadata.version, source: .appStore(id: id, country: nil), outcome: .noStoreListing)
        }

        let country = await currentCountry()
        let source = ApplicationUpdateResult.Source.appStore(id: id, country: country)
        func result(_ outcome: ApplicationUpdateResult.Outcome) -> ApplicationUpdateResult {
            ApplicationUpdateResult(installedVersion: metadata.version, source: source, outcome: outcome)
        }

        var query = URLComponents()
        query.scheme = "https"
        query.host = "itunes.apple.com"
        query.path = "/lookup"
        query.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "country", value: country.lowercased()),
            URLQueryItem(name: "entity", value: "macSoftware"),
        ]
        guard let url = query.url else { return result(.noStoreListing) }

        do {
            let data = try await fetch(url)
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            let matches = response.results.filter {
                $0.trackId == id && $0.bundleId == bundleIdentifier && $0.kind == "mac-software"
            }
            guard matches.count == 1, let listing = matches.first else { return result(.noStoreListing) }
            return result(Self.evaluate(listing, installed: metadata.version))
        } catch {
            if !Task.isCancelled {
                Self.logger.error("Could not query the store catalog: \(error.localizedDescription, privacy: .private)")
            }
            return result(.requestFailed)
        }
    }

    private static func evaluate(_ listing: Listing, installed: ApplicationVersion) -> ApplicationUpdateResult.Outcome {
        guard let version = listing.version, !version.isEmpty else { return .noStoreListing }
        let published = ApplicationVersion(shortVersion: version, buildVersion: nil)
        guard let current = installed.shortVersion else { return .uncomparableVersion }
        if current == version { return .noUpdate(published) }
        guard let installedNumber = NumericApplicationVersion(current), let offered = NumericApplicationVersion(version)
        else { return .uncomparableVersion }
        guard installedNumber < offered else { return .noUpdate(published) }

        if let minimum = listing.minimumOsVersion, !minimum.isEmpty {
            guard let required = NumericApplicationVersion(minimum) else { return .uncomparableVersion }
            if NumericApplicationVersion(ProcessInfo.processInfo.operatingSystemVersion) < required {
                return .incompatible(published, .minimumMacOS(minimum))
            }
        }
        return .available(published)
    }

    static func country(storefront: String?, fallback: Locale.Region?) -> String {
        // The storefront uses ISO alpha-3 codes while the catalog expects ISO alpha-2 codes.
        let region = storefront.flatMap { Locale(identifier: "en_\($0)").region }
        return [region, fallback].compactMap { $0?.identifier.uppercased() }.first {
            $0.utf8.count == 2 && $0.utf8.allSatisfy { (65...90).contains($0) }
        } ?? "US"
    }

    private static func storefrontCountry() async -> String {
        let storefront = await Storefront.current
        return country(storefront: storefront?.countryCode, fallback: Locale.current.region)
    }

    private static func hasReceipt(in applicationURL: URL) -> Bool {
        let receipt = applicationURL.appending(path: "Contents/_MASReceipt/receipt")
        guard let values = try? receipt.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink == false && (values.fileSize ?? 0) > 0
    }

    private static func appStoreID(_ applicationURL: URL) -> UInt64? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, applicationURL as CFURL),
            let attribute = MDItemCopyAttribute(item, "kMDItemAppStoreAdamID" as CFString)
        else { return nil }
        let value = (attribute as? NSNumber)?.stringValue ?? (attribute as? String)
        guard let value, let id = UInt64(value), id > 0 else { return nil }
        return id
    }
}

import Foundation
import Security

@MainActor
protocol APIKeyPersisting {
    func load() throws -> String?
    func save(_ key: String) throws
    func remove() throws
}

struct KeychainFailure: Error {
    let status: OSStatus
}

enum MiMoAPIKey {
    static func validate(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), (8...512).contains(key.utf8.count),
              key.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else {
            throw ConversationFailure.invalidKey
        }
        return key
    }
}

/// This-device-only storage for a private development credential, never a shared distributed secret.
@MainActor
final class KeychainAPIKeyStore: APIKeyPersisting {
    private let service: String

    init(service: String = "Bina.MiMo.PayAsYouGo") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "developer-api-key",
            kSecAttrSynchronizable as String: false
        ]
    }

    func load() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainFailure(status: errSecDecode)
        }
        return key
    }

    func save(_ key: String) throws {
        let key = try MiMoAPIKey.validate(key)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure(status: status) }
    }
}

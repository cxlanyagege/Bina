import Foundation
import Testing
@testable import Bina

@MainActor
struct APIKeyStoreTests {
    @Test func isolatedKeychainEntryCanBeSavedReplacedAndRemoved() throws {
        let service = "Bina.Tests.MiMo.\(UUID().uuidString)"
        let store = KeychainAPIKeyStore(service: service)
        defer { try? store.remove() }
        let missing = try store.load()
        #expect(missing == nil)
        try store.save("sk-fixture-key-first")
        let first = try store.load()
        #expect(first == "sk-fixture-key-first")
        try KeychainAPIKeyStore(service: service).save("sk-fixture-key-second")
        let replaced = try store.load()
        #expect(replaced == "sk-fixture-key-second")
        #expect(throws: ConversationFailure.invalidKey) { try store.save("tp-fixture-key") }
        let preserved = try store.load()
        #expect(preserved == "sk-fixture-key-second")
        try store.remove()
        try store.remove()
        let deleted = try store.load()
        #expect(deleted == nil)
    }
}

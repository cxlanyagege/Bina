import CryptoKit
import Foundation
import Testing
@testable import Bina

@MainActor
struct CharacterFootwearProfileTests {
    private let modelHash = String(repeating: "a", count: 64)

    @Test func matchingVersionedProfileIsAccepted() throws {
        try CharacterFootwearProfile(schemaVersion: 1, modelSHA256: modelHash,
            barefootSHA256: String(repeating: "b", count: 64)).validate(modelSHA256: modelHash)
    }

    @Test func unsupportedSchemaInvalidDigestsAndDifferentSourceAreRejected() {
        let otherHash = String(repeating: "b", count: 64)
        for profile in [
            CharacterFootwearProfile(schemaVersion: 2, modelSHA256: modelHash, barefootSHA256: otherHash),
            CharacterFootwearProfile(schemaVersion: 1, modelSHA256: "invalid", barefootSHA256: otherHash),
            CharacterFootwearProfile(schemaVersion: 1, modelSHA256: modelHash, barefootSHA256: "invalid"),
            CharacterFootwearProfile(schemaVersion: 1, modelSHA256: otherHash, barefootSHA256: modelHash)
        ] {
            #expect(throws: CharacterFootwearError.self) { try profile.validate(modelSHA256: modelHash) }
        }
    }

    @Test func loaderAcceptsPairedBytesAndRejectsChangedLayer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let layer = folder.appendingPathComponent("bare.usdc"), file = folder.appendingPathComponent("footwear.json")
        let bytes = Data("Authored footwear fixture".utf8)
        try bytes.write(to: layer)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "modelSHA256": modelHash, "barefootSHA256": hash
        ]).write(to: file)
        let profile = try await CharacterFootwearProfile.load(profileURL: file, barefootURL: layer, modelSHA256: modelHash)
        #expect(profile.barefootSHA256 == hash)
        try Data("Changed layer".utf8).write(to: layer)
        await #expect(throws: CharacterFootwearError.self) {
            try await CharacterFootwearProfile.load(profileURL: file, barefootURL: layer, modelSHA256: modelHash)
        }
    }

    @Test func loaderReportsMissingAndMalformedMetadata() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("footwear.json"), layer = folder.appendingPathComponent("bare.usdc")
        await #expect(throws: (any Error).self) {
            try await CharacterFootwearProfile.load(profileURL: file, barefootURL: layer, modelSHA256: modelHash)
        }
        try Data("broken".utf8).write(to: file)
        await #expect(throws: DecodingError.self) {
            try await CharacterFootwearProfile.load(profileURL: file, barefootURL: layer, modelSHA256: modelHash)
        }
    }
}

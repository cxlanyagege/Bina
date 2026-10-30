import CryptoKit
import Foundation
import Testing
@testable import Bina

@MainActor
struct CharacterFaceProfileTests {
    @Test func completeSemanticMappingCanRoundTrip() throws {
        let profile = fixture()
        try profile.validate()
        let copy = try JSONDecoder().decode(CharacterFaceProfile.self, from: JSONEncoder().encode(profile))
        #expect(copy.channels == profile.channels)
    }

    @Test func incompleteAmbiguousAndUnsafeMappingsAreRejected() {
        for variant in 0..<6 {
            var channels = fixture().channels
            switch variant {
            case 0: channels.removeValue(forKey: "blink")
            case 1: channels["unknown"] = "Face_9999"
            case 2: channels["blink"] = channels["smile"]
            case 3: channels["blink"] = "../Face_0021"
            case 4: channels["blink"] = "Face_XX21"
            default: channels["blink"] = "Face_00211"
            }
            let invalid = CharacterFaceProfile(schemaVersion: 1, modelSHA256: fixture().modelSHA256,
                channels: channels, coveringMaterial: "CharacterMaterial_12")
            #expect(throws: CharacterFaceError.self) { try invalid.validate() }
        }
    }

    @Test func schemaHashAndCoverBindingAreValidated() {
        for profile in [
            CharacterFaceProfile(schemaVersion: 2, modelSHA256: fixture().modelSHA256, channels: fixture().channels, coveringMaterial: "CharacterMaterial_12"),
            CharacterFaceProfile(schemaVersion: 1, modelSHA256: "unpaired", channels: fixture().channels, coveringMaterial: "CharacterMaterial_12"),
            CharacterFaceProfile(schemaVersion: 1, modelSHA256: fixture().modelSHA256, channels: fixture().channels, coveringMaterial: "CharacterMaterial_11")
        ] { #expect(throws: CharacterFaceError.self) { try profile.validate() } }
    }

    @Test func loaderRejectsMismatchedAssetBytes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("test.usdz"), file = folder.appendingPathComponent("face.json")
        let bytes = Data("Face fixture".utf8)
        try bytes.write(to: model)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let profile = CharacterFaceProfile(schemaVersion: 1, modelSHA256: hash, channels: fixture().channels, coveringMaterial: "CharacterMaterial_12")
        try JSONEncoder().encode(profile).write(to: file)
        let loaded = try await CharacterFaceProfile.load(modelURL: model, profileURL: file)
        #expect(loaded.modelSHA256 == hash)
        try Data("Other asset".utf8).write(to: model)
        await #expect(throws: CharacterFaceError.self) { try await CharacterFaceProfile.load(modelURL: model, profileURL: file) }
    }

    private func fixture() -> CharacterFaceProfile {
        CharacterFaceProfile(schemaVersion: 1, modelSHA256: String(repeating: "a", count: 64),
            channels: ["blink":"Face_0021", "smile":"Face_0005", "browSmile":"Face_0040", "browRaise":"Face_0043", "mouthOpen":"Face_0000", "mouthRound":"Face_0004"],
            coveringMaterial: "CharacterMaterial_12")
    }
}

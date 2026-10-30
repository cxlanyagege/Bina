import CryptoKit
import Foundation

nonisolated enum CharacterFaceError: LocalizedError {
    case missingProfile
    case invalidProfile(String)
    case mismatchedAsset
    case invalidBinding(String)

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return "此构建缺少面部数据，当前保留原模型表情。"
        case .invalidProfile, .mismatchedAsset, .invalidBinding:
            return "面部数据与模型不匹配，已保留原模型表情。请检查配套面部资源。"
        }
    }
}

/// Semantic facial channels paired with an exact, locally prepared character asset.
nonisolated struct CharacterFaceProfile: Codable, Sendable {
    static let requiredChannels: Set<String> = ["blink", "smile", "browSmile", "browRaise", "mouthOpen", "mouthRound"]

    let schemaVersion: Int
    let modelSHA256: String
    let channels: [String: String]
    let coveringMaterial: String

    func validate() throws {
        guard schemaVersion == 1, modelSHA256.count == 64,
              modelSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              Set(channels.keys) == Self.requiredChannels,
              Set(channels.values).count == channels.count,
              channels.values.allSatisfy({ name in
                  name.hasPrefix("Face_") && name.count == 9 &&
                  name.dropFirst(5).utf8.allSatisfy { (48...57).contains($0) }
              }), coveringMaterial == "CharacterMaterial_12" else {
            throw CharacterFaceError.invalidProfile("Unsupported, incomplete, or ambiguous facial metadata.")
        }
    }

    static func load(modelURL: URL, profileURL: URL) async throws -> Self {
        try await Task.detached(priority: .userInitiated) {
            let profile = try JSONDecoder().decode(Self.self, from: Data(contentsOf: profileURL))
            try profile.validate()
            let bytes = try Data(contentsOf: modelURL, options: .mappedIfSafe)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard hash == profile.modelSHA256 else { throw CharacterFaceError.mismatchedAsset }
            return profile
        }.value
    }
}

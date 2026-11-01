import CryptoKit
import Foundation
import RealityKit

/// Pairs a local derived USD layer with the exact original model and layer bytes.
nonisolated struct CharacterFootwearProfile: Decodable, Sendable {
    let schemaVersion: Int
    let modelSHA256: String
    let barefootSHA256: String

    func validate(modelSHA256 expected: String) throws {
        func isDigest(_ value: String) -> Bool {
            value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        guard schemaVersion == 1, isDigest(modelSHA256), isDigest(barefootSHA256), modelSHA256 == expected else {
            throw CharacterFootwearError.invalidBinding("Footwear metadata is invalid or belongs to another model.")
        }
    }

    static func load(profileURL: URL, barefootURL: URL, modelSHA256: String) async throws -> Self {
        try await Task.detached(priority: .userInitiated) {
            let profile = try JSONDecoder().decode(Self.self, from: Data(contentsOf: profileURL))
            try profile.validate(modelSHA256: modelSHA256)
            let data = try Data(contentsOf: barefootURL, options: .mappedIfSafe)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == profile.barefootSHA256 else {
                throw CharacterFootwearError.invalidBinding("The barefoot layer does not match its metadata.")
            }
            return profile
        }.value
    }
}

/// Imports the authored variant through RealityKit instead of regenerating an imported mesh.
@MainActor
struct CharacterFootwearAsset {
    let mesh: MeshResource
    let materialNames: [String?]
    let jointNames: [String]

    static func load(in bundle: Bundle = .main, modelSHA256: String) async throws -> Self {
        guard let layerURL = CharacterAsset.resourceURL("ColumbinaBarefoot", extension: "usdc", in: bundle),
              let profileURL = CharacterAsset.resourceURL("ColumbinaFootwear", extension: "json", in: bundle) else {
            throw CharacterFootwearError.invalidBinding("The authored footwear layer or metadata is missing.")
        }
        _ = try await CharacterFootwearProfile.load(
            profileURL: profileURL, barefootURL: layerURL, modelSHA256: modelSHA256)
        let entity = try await Entity(contentsOf: layerURL)
        var models: [ModelEntity] = []
        func collect(_ entity: Entity) {
            if let model = entity as? ModelEntity, !model.jointNames.isEmpty { models.append(model) }
            for child in entity.children { collect(child) }
        }
        collect(entity)
        guard models.count == 1, let model = models.first, let component = model.model else {
            throw CharacterFootwearError.invalidBinding("The barefoot layer must contain one imported rig.")
        }
        return Self(mesh: component.mesh, materialNames: component.materials.map(\.name), jointNames: model.jointNames)
    }
}

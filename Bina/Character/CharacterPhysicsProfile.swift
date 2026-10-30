import CryptoKit
import Foundation
import simd

nonisolated enum CharacterPhysicsError: LocalizedError {
    case missingProfile
    case invalidProfile(String)
    case mismatchedAsset
    case invalidBinding(String)
    case unstableSimulation

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return "此构建缺少头发物理数据，当前保留原有待机和转头。"
        case .invalidProfile, .mismatchedAsset, .invalidBinding:
            return "头发物理数据与模型不匹配，已保留原有动作。请检查配套物理资源。"
        case .unstableSimulation:
            return "头发物理暂不可用，已恢复原有动作。请重新运行应用后重试。"
        }
    }
}

/// Local-only accessory settings paired with one exact skeletal asset.
nonisolated struct CharacterPhysicsProfile: Codable, Sendable {
    struct Chain: Codable, Sendable {
        let name: String
        let joints: [String]
        let tipOffset: [Float]
        let radius: Float
        let stiffness: Float
        let damping: Float
        let gravity: [Float]
        let maximumAngle: Float
        /// Optional bound relative to the complete primary pose, preventing long-chain foldover.
        var maximumChainAngle: Float? = nil
        /// Optional character-frame angular speed limit in radians per second.
        var maximumAngularSpeed: Float? = nil
    }

    struct Collider: Codable, Sendable {
        let name: String
        let joint: String
        let start: [Float]
        let end: [Float]
        let radius: Float
    }

    let schemaVersion: Int
    let modelSHA256: String
    let chains: [Chain]
    let colliders: [Collider]

    func validate() throws {
        func jointName(_ name: String) -> Bool {
            name.hasPrefix("Joint_") && name.count <= 32 && name.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
            }
        }
        func vector(_ value: [Float], limit: Float) -> Bool {
            value.count == 3 && value.allSatisfy { $0.isFinite && abs($0) <= limit }
        }
        let joints = chains.flatMap(\.joints)
        guard schemaVersion == 1, modelSHA256.count == 64,
              modelSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              (1...8).contains(chains.count), (1...24).contains(colliders.count),
              joints.count <= 128, Set(joints).count == joints.count,
              Set(chains.map(\.name)).count == chains.count,
              Set(colliders.map(\.name)).count == colliders.count else {
            throw CharacterPhysicsError.invalidProfile("Unsupported or ambiguous accessory metadata.")
        }
        for chain in chains {
            guard !chain.name.isEmpty, (1...32).contains(chain.joints.count),
                  chain.joints.allSatisfy(jointName), vector(chain.tipOffset, limit: 0.5),
                  simd_length(SIMD3(chain.tipOffset)) > 0.001,
                  chain.radius.isFinite, (0.001...0.05).contains(chain.radius),
                  chain.stiffness.isFinite, (1...1000).contains(chain.stiffness),
                  chain.damping.isFinite, (1...60).contains(chain.damping),
                  vector(chain.gravity, limit: 5), chain.maximumAngle.isFinite,
                  (0.05...1.2).contains(chain.maximumAngle),
                  chain.maximumChainAngle.map({ $0.isFinite && (0.05...1.2).contains($0) }) ?? true,
                  chain.maximumAngularSpeed.map({ $0.isFinite && (0.1...10).contains($0) }) ?? true else {
                throw CharacterPhysicsError.invalidProfile("Invalid spring-chain settings.")
            }
        }
        for collider in colliders {
            guard !collider.name.isEmpty, jointName(collider.joint),
                  vector(collider.start, limit: 1), vector(collider.end, limit: 1),
                  collider.radius.isFinite, (0.005...0.25).contains(collider.radius) else {
                throw CharacterPhysicsError.invalidProfile("Invalid collision-proxy settings.")
            }
        }
    }

    static func load(modelURL: URL, profileURL: URL) async throws -> Self {
        try await Task.detached(priority: .userInitiated) {
            let profile = try JSONDecoder().decode(Self.self, from: Data(contentsOf: profileURL))
            try profile.validate()
            let data = try Data(contentsOf: modelURL, options: .mappedIfSafe)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == profile.modelSHA256 else { throw CharacterPhysicsError.mismatchedAsset }
            return profile
        }.value
    }
}

import CryptoKit
import Foundation

nonisolated enum CharacterIdleError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration(String)
    case mismatchedAsset
    case missingSkeleton
    case missingJoint(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "当前构建缺少站姿数据，请重新生成并加入角色资源。"
        case .invalidConfiguration, .mismatchedAsset:
            return "站姿数据与模型不匹配，请将同一次导出的模型和站姿数据一起加入构建。"
        case .missingSkeleton, .missingJoint:
            return "当前模型没有完整的可用骨骼，请使用修正骨骼名称后的角色资源。"
        }
    }
}

/// Local authoring data is paired with one exact model export.
nonisolated struct CharacterIdlePose: Decodable, Sendable {
    let schemaVersion: Int
    let modelSHA256: String
    let jointDeltas: [String: [Float]]
    let motionJoints: [String: String]
    let fixedJoints: [String]

    func validate() throws {
        let roles: Set<String> = ["spine", "chest", "neck", "head"]
        guard schemaVersion == 1, !jointDeltas.isEmpty,
              modelSHA256.count == 64,
              modelSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              Set(motionJoints.keys) == roles,
              Set(motionJoints.values).count == roles.count,
              fixedJoints.count >= 2, Set(fixedJoints).count == fixedJoints.count else {
            throw CharacterIdleError.invalidConfiguration("Unsupported or incomplete pose metadata.")
        }
        let names = Array(jointDeltas.keys) + Array(motionJoints.values) + fixedJoints
        guard names.allSatisfy({ $0.hasPrefix("Joint_") && $0.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
        } }), Set(fixedJoints).isDisjoint(with: jointDeltas.keys),
              Set(fixedJoints).isDisjoint(with: motionJoints.values) else {
            throw CharacterIdleError.invalidConfiguration("Invalid or conflicting joint names.")
        }
        for matrix in jointDeltas.values {
            guard matrix.count == 16, matrix.allSatisfy(\.isFinite),
                  abs(matrix[3]) < 0.00001, abs(matrix[7]) < 0.00001,
                  abs(matrix[11]) < 0.00001, abs(matrix[15] - 1) < 0.00001 else {
                throw CharacterIdleError.invalidConfiguration("Joint deltas must be finite affine matrices.")
            }
        }
    }

    static func load(modelURL: URL, poseURL: URL) async throws -> CharacterIdlePose {
        // File hashing and decoding must not stall the immersive scene's main actor.
        try await Task.detached(priority: .userInitiated) {
            let pose = try JSONDecoder().decode(Self.self, from: Data(contentsOf: poseURL))
            try pose.validate()
            let model = try Data(contentsOf: modelURL, options: .mappedIfSafe)
            let digest = SHA256.hash(data: model).map { String(format: "%02x", $0) }.joined()
            guard digest == pose.modelSHA256 else { throw CharacterIdleError.mismatchedAsset }
            return pose
        }.value
    }
}

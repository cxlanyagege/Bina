import Foundation
import RealityKit
import simd

struct CharacterBoundsNormalization: Equatable {
    let scale: Float
    let translation: SIMD3<Float>

    /// Keeps authored rig transforms intact by expressing normalization on parent entities.
    static func make(
        minimum: SIMD3<Float>,
        maximum: SIMD3<Float>,
        referenceHeight: Float = 1.6
    ) -> CharacterBoundsNormalization? {
        guard referenceHeight.isFinite, referenceHeight > 0,
              (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite }) else {
            return nil
        }
        let extents = maximum - minimum
        guard (0..<3).allSatisfy({ extents[$0].isFinite && extents[$0] >= 0 }),
              extents.y > 0.0001 else {
            return nil
        }
        let center = minimum + extents / 2
        let scale = referenceHeight / extents.y
        let translation = SIMD3<Float>(-center.x, -minimum.y, -center.z)
        guard scale.isFinite, scale > 0,
              (0..<3).allSatisfy({ translation[$0].isFinite }) else {
            return nil
        }
        return CharacterBoundsNormalization(scale: scale, translation: translation)
    }
}

enum CharacterAssetError: LocalizedError {
    case missingResource
    case invalidBounds

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "未找到哥伦比娅模型，请使用包含角色资源的构建。"
        case .invalidBounds:
            return "哥伦比娅模型没有可用的尺寸信息，请检查模型导出结果。"
        }
    }
}

@MainActor
enum CharacterAsset {
    static let referenceHeight: Float = 1.6

    static func load(in bundle: Bundle = .main) async throws -> Entity {
        let url = resourceURL("Columbina", extension: "usdz", in: bundle)
        guard let url else { throw CharacterAssetError.missingResource }
        let model = try await Entity(contentsOf: url)
        configureMaterials(in: model)
        let normalized = Entity()
        normalized.name = "ColumbinaNormalized"
        let pivot = Entity()
        pivot.name = "ColumbinaAssetPivot"
        pivot.addChild(model)
        normalized.addChild(pivot)

        let bounds = model.visualBounds(recursive: true, relativeTo: pivot)
        guard let normalization = CharacterBoundsNormalization.make(
            minimum: bounds.min,
            maximum: bounds.max,
            referenceHeight: referenceHeight
        ) else {
            throw CharacterAssetError.invalidBounds
        }
        pivot.position = normalization.translation
        normalized.scale = SIMD3(repeating: normalization.scale)
        return normalized
    }

    static func loadIdleMotion(for character: Entity, in bundle: Bundle = .main) async throws -> CharacterIdleMotion {
        guard let modelURL = resourceURL("Columbina", extension: "usdz", in: bundle) else {
            throw CharacterAssetError.missingResource
        }
        guard let poseURL = resourceURL("ColumbinaIdlePose", extension: "json", in: bundle) else {
            throw CharacterIdleError.missingConfiguration
        }
        let pose = try await CharacterIdlePose.load(modelURL: modelURL, poseURL: poseURL)
        let motion = try CharacterIdleMotion(character: character, pose: pose)
        do {
            guard let profileURL = resourceURL("ColumbinaPhysics", extension: "json", in: bundle) else {
                throw CharacterPhysicsError.missingProfile
            }
            let profile = try await CharacterPhysicsProfile.load(modelURL: modelURL, profileURL: profileURL)
            try motion.configureHairPhysics(profile, pose: pose)
        } catch { motion.reportHairPhysicsUnavailable(error) }
        do {
            guard let profileURL = resourceURL("ColumbinaFace", extension: "json", in: bundle) else {
                throw CharacterFaceError.missingProfile
            }
            let profile = try await CharacterFaceProfile.load(modelURL: modelURL, profileURL: profileURL)
            try motion.configureFace(profile)
        } catch { motion.reportFaceUnavailable(error) }
        return motion
    }

    static func resourceURL(_ name: String, extension fileExtension: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Characters")
            ?? bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources/Characters")
            ?? bundle.url(forResource: name, withExtension: fileExtension)
    }

    /// Restores this Columbina source's sidedness without changing its opacity.
    static func configureMaterials(in entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard var surface = material as? PhysicallyBasedMaterial else { return material }
                // This export imports with back-face culling despite its doubleSided
                // mesh. All source materials except shoes (19) require both sides.
                surface.faceCulling = surface.name == "CharacterMaterial_19" ? .back : .none
                return surface
            }
            entity.components.set(model)
        }
        for child in entity.children {
            configureMaterials(in: child)
        }
    }
}

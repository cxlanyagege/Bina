import RealityKit

/// Owns blend weights and the eye-cover material; never writes skeletal transforms.
@MainActor
final class CharacterFaceBinding {
    private struct Channel {
        let semantic: String
        let setIndex: Int
        let weightIndex: Int
    }

    private let model: ModelEntity
    private let importedWeights: BlendShapeWeightsComponent?
    private let baselineWeights: BlendShapeWeightsComponent
    private let channels: [Channel]
    private let coveringIndex: Int
    private let covering: PhysicallyBasedMaterial
    private var lastCoveringOpacity: Float?

    init(model: ModelEntity, profile: CharacterFaceProfile, referenceWeights: BlendShapeWeightsComponent?, referenceMaterials: [any Material]) throws {
        try profile.validate()
        guard let component = model.model else { throw CharacterFaceError.invalidBinding("Missing model component.") }
        let matches = referenceMaterials.enumerated().filter { $0.element.name == profile.coveringMaterial }
        guard matches.count == 1, let match = matches.first, let covering = match.element as? PhysicallyBasedMaterial,
              component.materials.indices.contains(match.offset), component.materials[match.offset].name == profile.coveringMaterial,
              case .transparent = covering.blending else {
            throw CharacterFaceError.invalidBinding("Missing or ambiguous eye-cover material.")
        }
        let imported = referenceWeights
        let weights = imported ?? BlendShapeWeightsComponent(weightsMapping: BlendShapeWeightsMapping(meshResource: component.mesh))
        var channels: [Channel] = []
        for (semantic, name) in profile.channels {
            var matches: [Channel] = []
            for (setIndex, data) in weights.weightSet.enumerated() {
                guard data.weights.count == data.weightNames.count else {
                    throw CharacterFaceError.invalidBinding("Inconsistent facial weights.")
                }
                for (i, candidate) in data.weightNames.enumerated() where candidate == name {
                    matches.append(Channel(semantic: semantic, setIndex: setIndex, weightIndex: i))
                }
            }
            guard matches.count == 1 else { throw CharacterFaceError.invalidBinding("Missing or ambiguous channel: \(name)") }
            channels.append(matches[0])
        }
        self.model = model
        importedWeights = imported
        baselineWeights = weights
        self.channels = channels
        coveringIndex = match.offset
        self.covering = covering
    }

    func apply(_ sample: CharacterFacePlayback.Sample, influence: Float) throws {
        guard influence.isFinite, (0...1).contains(influence),
              sample.coveringOpacity.isFinite, (0...1).contains(sample.coveringOpacity),
              Set(sample.channels.keys) == CharacterFaceProfile.requiredChannels,
              sample.channels.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              var component = model.model, component.materials.indices.contains(coveringIndex),
              component.materials[coveringIndex].name == covering.name else {
            throw CharacterFaceError.invalidBinding("Invalid facial sample or changed material binding.")
        }
        var weights = baselineWeights
        for channel in channels {
            var data = weights.weightSet[channel.setIndex]
            let original = data.weights[channel.weightIndex]
            data.weights[channel.weightIndex] = original + (sample.channels[channel.semantic]! - original) * influence
            weights.weightSet[channel.setIndex] = data
        }
        model.components.set(weights)
        let amount = 1 + (sample.coveringOpacity - 1) * influence
        if amount != lastCoveringOpacity {
            var material = covering
            if case .transparent(var opacity) = material.blending {
                opacity.scale *= amount
                material.blending = .transparent(opacity: opacity)
            }
            component.materials[coveringIndex] = material
            model.model = component
            lastCoveringOpacity = amount
        }
    }

    func restore() {
        if let importedWeights { model.components.set(importedWeights) }
        else { model.components.remove(BlendShapeWeightsComponent.self) }
        if var component = model.model, component.materials.indices.contains(coveringIndex),
           component.materials[coveringIndex].name == covering.name {
            component.materials[coveringIndex] = covering
            model.model = component
        }
        lastCoveringOpacity = nil
    }
}

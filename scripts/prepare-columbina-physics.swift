import CryptoKit
import Foundation
import RealityKit
import simd

/// Author the selected accessory profile from the exact imported reference rig.
/// Compile with CharacterPhysicsProfile.swift; generated character data stays local.
@main
struct PrepareColumbinaPhysics {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw CharacterPhysicsError.invalidProfile("Usage: prepare-physics <model.usdz> <profile.json>")
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let character = try await Entity(contentsOf: input)
        func findRig(_ entity: Entity) -> ModelEntity? {
            if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
            for child in entity.children { if let result = findRig(child) { return result } }
            return nil
        }
        guard let model = findRig(character), let skeleton = model.model?.mesh.contents.skeletons.first else {
            throw CharacterPhysicsError.invalidBinding("No imported skeleton.")
        }
        let names = model.jointNames.map { String($0.split(separator: "/").last!) }
        let indices = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        var globals: [simd_float4x4] = []
        let characterFromModel = model.transformMatrix(relativeTo: character)
        for (i, joint) in skeleton.joints.enumerated() {
            if let parent = joint.parentIndex {
                guard parent < i else { throw CharacterPhysicsError.invalidBinding("Invalid joint topology.") }
                globals.append(globals[parent] * model.jointTransforms[i].matrix)
            } else { globals.append(characterFromModel * model.jointTransforms[i].matrix) }
        }
        func frame(_ name: String) throws -> simd_float4x4 {
            guard let index = indices[name] else { throw CharacterPhysicsError.invalidBinding("Missing \(name)") }
            return globals[index]
        }
        func point(_ matrix: simd_float4x4) -> SIMD3<Float> {
            SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        }
        func array(_ point: SIMD3<Float>) -> [Float] { [point.x, point.y, point.z] }
        func chain(_ name: String, joints: [String], tipJoint: String?, radius: Float, stiffness: Float) throws -> CharacterPhysicsProfile.Chain {
            let last = try frame(joints.last!)
            let tail: SIMD3<Float>
            if let tipJoint { tail = point(try frame(tipJoint)) }
            else { tail = point(last) * 2 - point(try frame(joints[joints.count - 2])) }
            let localTail = simd_inverse(last) * SIMD4(tail, 1)
            return .init(name: name, joints: joints, tipOffset: [localTail.x, localTail.y, localTail.z],
                         radius: radius, stiffness: stiffness, damping: 14,
                         gravity: [0, -0.6, 0], maximumAngle: 0.65)
        }
        let chains = try [
            chain("Left side lock", joints: ["Joint_0054", "Joint_0055", "Joint_0056"], tipJoint: nil, radius: 0.035, stiffness: 180),
            chain("Right side lock", joints: ["Joint_0057", "Joint_0058", "Joint_0059"], tipJoint: nil, radius: 0.035, stiffness: 180),
            chain("Right rear upper lock", joints: (70...77).map { String(format: "Joint_%04d", $0) }, tipJoint: "Joint_0078", radius: 0.05, stiffness: 140),
            chain("Left rear upper lock", joints: (107...114).map { String(format: "Joint_%04d", $0) }, tipJoint: "Joint_0115", radius: 0.05, stiffness: 140)
        ]
        let neck = point(try frame("Joint_0040"))
        func collider(_ name: String, joint: String, a: SIMD3<Float>, b: SIMD3<Float>, radius: Float) throws -> CharacterPhysicsProfile.Collider {
            let inverse = simd_inverse(try frame(joint))
            let start = inverse * SIMD4(neck + a, 1), end = inverse * SIMD4(neck + b, 1)
            return .init(name: name, joint: joint, start: [start.x, start.y, start.z], end: [end.x, end.y, end.z], radius: radius)
        }
        let colliders = try [
            collider("Neck", joint: "Joint_0040", a: [0,-0.01,0], b: [0,0.045,0], radius: 0.034),
            collider("Left collar", joint: "Joint_0039", a: [-0.04,0.025,-0.045], b: [-0.075,-0.035,-0.045], radius: 0.016),
            collider("Right collar", joint: "Joint_0039", a: [0.04,0.025,-0.045], b: [0.075,-0.035,-0.045], radius: 0.016),
            collider("Rear collar", joint: "Joint_0039", a: [-0.055,0,0.038], b: [0.055,0,0.038], radius: 0.022),
            collider("Left shoulder", joint: "Joint_0039", a: [-0.055,-0.025,0.005], b: [-0.14,-0.055,0.02], radius: 0.042),
            collider("Right shoulder", joint: "Joint_0039", a: [0.055,-0.025,0.005], b: [0.14,-0.055,0.02], radius: 0.042),
            collider("Upper back", joint: "Joint_0039", a: [-0.08,-0.075,0.065], b: [0.08,-0.075,0.065], radius: 0.06),
            collider("Upper chest", joint: "Joint_0039", a: [-0.06,-0.10,-0.018], b: [0.06,-0.10,-0.018], radius: 0.065)
        ]
        let digest = SHA256.hash(data: try Data(contentsOf: input)).map { String(format: "%02x", $0) }.joined()
        let profile = CharacterPhysicsProfile(schemaVersion: 1, modelSHA256: digest, chains: chains, colliders: colliders)
        try profile.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: output, options: .atomic)
        print("PASS: \(chains.count) chains, \(chains.flatMap(\.joints).count) joints, \(colliders.count) colliders; model \(digest)")
    }
}

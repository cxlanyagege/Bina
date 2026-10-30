import CryptoKit
import Foundation
import Testing
@testable import Bina

@MainActor
struct CharacterPhysicsProfileTests {
    @Test func validAccessoryMetadataCanRoundTrip() throws {
        let profile = try decoded()
        try profile.validate()
        let copy = try JSONDecoder().decode(CharacterPhysicsProfile.self, from: JSONEncoder().encode(profile))
        #expect(copy.chains[0].joints == ["Joint_0054"])
        #expect(copy.colliders[0].joint == "Joint_0040")
        #expect(copy.chains[0].maximumChainAngle == nil)
        #expect(copy.chains[0].maximumAngularSpeed == nil)
    }

    @Test func optionalChainMotionLimitsAreValidated() throws {
        let profile = try decoded { object in
            var chains = object["chains"] as! [[String: Any]]
            chains[0]["maximumChainAngle"] = 0.5
            object["chains"] = chains
        }
        try profile.validate()
        #expect(profile.chains[0].maximumChainAngle == 0.5)
        for limit in [-0.1, 0, 1.3] {
            var invalid = profile.chains[0]
            invalid.maximumChainAngle = Float(limit)
            let rejected = CharacterPhysicsProfile(schemaVersion: 1, modelSHA256: profile.modelSHA256,
                chains: [invalid], colliders: profile.colliders)
            #expect(throws: CharacterPhysicsError.self) { try rejected.validate() }
        }
        for speed: Float in [-1,0,11,.nan,.infinity] {
            var invalid = profile.chains[0]
            invalid.maximumAngularSpeed = speed
            let rejected = CharacterPhysicsProfile(schemaVersion: 1, modelSHA256: profile.modelSHA256,
                chains: [invalid], colliders: profile.colliders)
            #expect(throws: CharacterPhysicsError.self) { try rejected.validate() }
        }
    }

    @Test func rejectsMalformedVectorsBoundsAndAmbiguousJoints() throws {
        for change in 0..<7 {
            let profile = try decoded { object in
                var chains = object["chains"] as! [[String:Any]]
                var colliders = object["colliders"] as! [[String:Any]]
                switch change {
                case 0: chains[0]["tipOffset"] = [0,0]
                case 1: chains[0]["radius"] = -0.1
                case 2: chains[0]["joints"] = ["Joint_0054", "Joint_0054"]
                case 3: chains[0]["joints"] = ["unknown/joint"]
                case 4: colliders[0]["radius"] = 100
                case 5: object["modelSHA256"] = "unpaired"
                default: object["schemaVersion"] = 99
                }
                object["chains"] = chains; object["colliders"] = colliders
            }
            #expect(throws: CharacterPhysicsError.self) { try profile.validate() }
        }
    }

    @Test func nonfiniteParametersAreRejectedBeforeSimulation() {
        let chain = CharacterPhysicsProfile.Chain(name: "Invalid", joints: ["Joint_0054"], tipOffset: [0,-0.1,0],
            radius: 0.01, stiffness: .nan, damping: 14, gravity: [0,0,0], maximumAngle: 0.6)
        let profile = CharacterPhysicsProfile(schemaVersion: 1, modelSHA256: String(repeating: "a", count: 64),
            chains: [chain], colliders: [.init(name: "Neck", joint: "Joint_0040", start: [0,0,0], end: [0,0.1,0], radius: 0.03)])
        #expect(throws: CharacterPhysicsError.self) { try profile.validate() }
    }

    @Test func loaderRequiresTheExactModelBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = directory.appendingPathComponent("model.usdz"), file = directory.appendingPathComponent("physics.json")
        let bytes = Data("Test model".utf8)
        try bytes.write(to: model)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let profile = try decoded { $0["modelSHA256"] = hash }
        try JSONEncoder().encode(profile).write(to: file)
        let loaded = try await CharacterPhysicsProfile.load(modelURL: model, profileURL: file)
        #expect(loaded.modelSHA256 == hash)
        try Data("Different model".utf8).write(to: model)
        await #expect(throws: CharacterPhysicsError.self) {
            try await CharacterPhysicsProfile.load(modelURL: model, profileURL: file)
        }
    }

    private func decoded(_ change: (inout [String:Any]) -> Void = { _ in }) throws -> CharacterPhysicsProfile {
        var object: [String:Any] = [
            "schemaVersion": 1, "modelSHA256": String(repeating: "a", count: 64),
            "chains": [["name":"Side lock", "joints":["Joint_0054"], "tipOffset":[0,-0.1,0],
                        "radius":0.01, "stiffness":180, "damping":14, "gravity":[0,0,0], "maximumAngle":0.6]],
            "colliders": [["name":"Neck", "joint":"Joint_0040", "start":[0,0,0], "end":[0,0.1,0], "radius":0.03]]
        ]
        change(&object)
        return try JSONDecoder().decode(CharacterPhysicsProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

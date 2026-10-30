import CryptoKit
import Foundation
import Testing
@testable import Bina

@MainActor
struct CharacterIdlePoseTests {
    @Test func validMetadataAllowsFiniteAffineJointDeltas() throws {
        var translated = identity
        translated[12] = 0.02
        let pose = makePose(jointDeltas: ["Joint_0100": translated])

        try pose.validate()

        #expect(pose.jointDeltas["Joint_0100"] == translated)
        #expect(pose.motionJoints.count == 4)
        #expect(pose.fixedJoints == ["Joint_0200", "Joint_0201"])
    }

    @Test func rejectsUnsupportedOrIncompleteMetadata() {
        var missingRole = motionJoints
        missingRole.removeValue(forKey: "head")
        var extraRole = motionJoints
        extraRole["eye"] = "Joint_0004"
        let invalid: [(String, CharacterIdlePose)] = [
            ("Unsupported schema", makePose(schemaVersion: 2)),
            ("Short digest", makePose(modelSHA256: String(repeating: "a", count: 63))),
            ("Uppercase digest", makePose(modelSHA256: String(repeating: "A", count: 64))),
            ("Non-hex digest", makePose(modelSHA256: String(repeating: "g", count: 64))),
            ("Missing motion role", makePose(motionJoints: missingRole)),
            ("Unknown motion role", makePose(motionJoints: extraRole)),
            ("Missing pose deltas", makePose(jointDeltas: [:])),
        ]

        for (reason, pose) in invalid { expectInvalid(pose, reason: reason) }
    }

    @Test func rejectsNonfiniteOrNonaffineMatrices() {
        var matrices: [[Float]] = [Array(identity.dropLast()), identity + [0]]
        for invalid: Float in [.nan, .infinity, -.infinity] {
            var matrix = identity
            matrix[0] = invalid
            matrices.append(matrix)
        }
        for index in [3, 7, 11] {
            var matrix = identity
            matrix[index] = 0.1
            matrices.append(matrix)
        }
        var invalidHomogeneousCoordinate = identity
        invalidHomogeneousCoordinate[15] = 0
        matrices.append(invalidHomogeneousCoordinate)

        for (index, matrix) in matrices.enumerated() {
            expectInvalid(makePose(jointDeltas: ["Joint_0100": matrix]), reason: "Invalid matrix \(index)")
        }
    }

    @Test func rejectsMissingNamesAndConflictingFixedJoints() {
        var missingName = motionJoints
        missingName["head"] = ""
        var duplicateMotionJoint = motionJoints
        duplicateMotionJoint["head"] = duplicateMotionJoint["neck"]
        let invalid: [(String, CharacterIdlePose)] = [
            ("Empty delta joint name", makePose(jointDeltas: ["": identity])),
            ("Invalid joint path", makePose(jointDeltas: ["Joint_left/arm": identity])),
            ("Unexpected joint namespace", makePose(jointDeltas: ["UpperArm": identity])),
            ("Missing motion joint name", makePose(motionJoints: missingName)),
            ("Duplicate motion joint", makePose(motionJoints: duplicateMotionJoint)),
            ("Insufficient fixed joints", makePose(fixedJoints: ["Joint_0200"])),
            ("Duplicate fixed joints", makePose(fixedJoints: ["Joint_0200", "Joint_0200"])),
            ("A fixed joint has a pose delta", makePose(fixedJoints: ["Joint_0100", "Joint_0201"])),
            ("A fixed joint has a motion role", makePose(fixedJoints: ["Joint_0000", "Joint_0201"])),
        ]

        for (reason, pose) in invalid { expectInvalid(pose, reason: reason) }
    }

    @Test func loaderAcceptsOnlyTheExactPairedModelBytes() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(
            "Bina-IdlePose-\(UUID().uuidString)", isDirectory: true
        )
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do { try manager.removeItem(at: directory) }
            catch { Issue.record(error, "Could not remove the temporary pose test directory.") }
        }
        let modelURL = directory.appendingPathComponent("Character.usdz")
        let poseURL = directory.appendingPathComponent("CharacterIdlePose.json")
        let modelBytes = Data("A paired local model export".utf8)
        let digest = SHA256.hash(data: modelBytes).map { String(format: "%02x", $0) }.joined()
        let pose = makePose(modelSHA256: digest)
        let payload: [String: Any] = [
            "schemaVersion": pose.schemaVersion,
            "modelSHA256": pose.modelSHA256,
            "jointDeltas": pose.jointDeltas,
            "motionJoints": pose.motionJoints,
            "fixedJoints": pose.fixedJoints,
        ]
        try modelBytes.write(to: modelURL)
        try JSONSerialization.data(withJSONObject: payload).write(to: poseURL)

        let loaded = try await CharacterIdlePose.load(modelURL: modelURL, poseURL: poseURL)

        #expect(loaded.modelSHA256 == digest)
        #expect(loaded.jointDeltas == pose.jointDeltas)
        #expect(loaded.motionJoints == pose.motionJoints)
        #expect(loaded.fixedJoints == pose.fixedJoints)

        try Data("A different model export".utf8).write(to: modelURL)
        let rejection = await #expect(throws: CharacterIdleError.self) {
            try await CharacterIdlePose.load(modelURL: modelURL, poseURL: poseURL)
        }
        if let rejection {
            guard case .mismatchedAsset = rejection else {
                Issue.record("Expected a mismatched-asset error for changed model bytes.")
                return
            }
        }
    }

    private var identity: [Float] {
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    }

    private var motionJoints: [String: String] {
        ["spine": "Joint_0000", "chest": "Joint_0001", "neck": "Joint_0002", "head": "Joint_0003"]
    }

    private func makePose(
        schemaVersion: Int = 1,
        modelSHA256: String = String(repeating: "a", count: 64),
        jointDeltas: [String: [Float]]? = nil,
        motionJoints: [String: String]? = nil,
        fixedJoints: [String]? = nil
    ) -> CharacterIdlePose {
        CharacterIdlePose(
            schemaVersion: schemaVersion,
            modelSHA256: modelSHA256,
            jointDeltas: jointDeltas ?? ["Joint_0100": identity],
            motionJoints: motionJoints ?? self.motionJoints,
            fixedJoints: fixedJoints ?? ["Joint_0200", "Joint_0201"]
        )
    }

    private func expectInvalid(_ pose: CharacterIdlePose, reason: String) {
        let rejection = #expect(throws: CharacterIdleError.self, Comment(rawValue: reason)) {
            try pose.validate()
        }
        if let rejection {
            guard case .invalidConfiguration = rejection else {
                Issue.record("Expected an invalid-configuration error.")
                return
            }
        }
    }
}

import Foundation
import RealityKit
import XCTest
@testable import Bina

@MainActor
final class BundledCuffClearanceTests: XCTestCase {
    func testNaturalAndIdleHandGeometryDoesNotCrossCuffs() async throws {
        guard let modelURL = CharacterAsset.resourceURL("Columbina", extension: "usdz", in: .main) else {
            throw XCTSkip("The local-only character asset is not bundled in this checkout.")
        }
        let poseURL = try XCTUnwrap(CharacterAsset.resourceURL("ColumbinaIdlePose", extension: "json", in: .main))
        let character = try await CharacterAsset.load()
        let model = try XCTUnwrap(skinnedModel(in: character))
        let geometry = try CuffClearanceGeometry(model: model)
        // Check the bind-space assumption before using CPU skinning to classify
        // real hand/sleeve intersections; incorrect matrices could hide a defect.
        XCTAssertLessThan(geometry.referenceBindingError, 0.0001)
        let pose = try await CharacterIdlePose.load(modelURL: modelURL, poseURL: poseURL)
        let motion = try CharacterIdleMotion(character: character, pose: pose)
        var elapsed: TimeInterval = 0
        for time: TimeInterval in [0, 2.75, 6, 11] {
            while elapsed < time - 0.000001 {
                let step = min(1.0 / 60, time - elapsed)
                motion.advance(by: step, isVisible: true)
                elapsed += step
            }
            for (side, wrist) in [("left", "Joint_0181"), ("right", "Joint_0324")] {
                let result = try geometry.countCrossings(wrist: wrist)
                XCTAssertEqual(result.crossingPairs, 0,
                    "The \(side) hand crosses its cuff in the actual skinned mesh at \(time) seconds.")
            }
        }
    }

    private func skinnedModel(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        return entity.children.lazy.compactMap { self.skinnedModel(in: $0) }.first
    }
}

// This asset uses linear blend skinning. Ornament layers are deliberately
// excluded: this regression protects visible hand skin against the main sleeve.
@MainActor
private struct CuffClearanceGeometry {
    enum GeometryError: Error { case invalid(String) }
    struct Triangle {
        let a: SIMD3<Float>
        let b: SIMD3<Float>
        let c: SIMD3<Float>
        var minimum: SIMD3<Float> { simd_min(a, simd_min(b, c)) }
        var maximum: SIMD3<Float> { simd_max(a, simd_max(b, c)) }
    }
    struct Part {
        let material: String
        let positions: [SIMD3<Float>]
        let influences: [MeshJointInfluence]
        let influencesPerVertex: Int
        let triangles: [UInt32]
    }
    struct CrossingCount {
        let handTriangles: Int
        let cuffTriangles: Int
        let crossingPairs: Int
    }
    let model: ModelEntity
    let skeleton: MeshResource.Skeleton
    let parts: [Part]
    let referenceBindingError: Float

    init(model: ModelEntity) throws {
        guard let component = model.model, let skeleton = component.mesh.contents.skeletons.first,
              skeleton.joints.count == model.jointTransforms.count,
              skeleton.joints.map(\.name) == model.jointNames else {
            throw GeometryError.invalid("The imported pose does not match its mesh skeleton.")
        }
        let instances = component.mesh.contents.instances
        guard instances.allSatisfy({ Self.matrixError($0.transform, matrix_identity_float4x4) < 0.000001 }) else {
            throw GeometryError.invalid("This regression expects identity mesh instances.")
        }
        self.model = model
        self.skeleton = skeleton
        var parts: [Part] = []
        for mesh in component.mesh.contents.models {
            for part in mesh.parts {
                guard component.materials.indices.contains(part.materialIndex) else {
                    throw GeometryError.invalid("Invalid material index.")
                }
                let name = component.materials[part.materialIndex].name ?? ""
                guard ["CharacterMaterial_00", "CharacterMaterial_14", "CharacterMaterial_15", "CharacterMaterial_16"].contains(name) else { continue }
                let positions = part.positions.elements
                guard !positions.isEmpty, let influences = part.jointInfluences?.influences.elements,
                      influences.count % positions.count == 0, let triangles = part.triangleIndices?.elements,
                      triangles.count % 3 == 0, triangles.allSatisfy({ Int($0) < positions.count }),
                      influences.allSatisfy({ model.jointTransforms.indices.contains($0.jointIndex) }) else {
                    throw GeometryError.invalid("The selected skin or cuff lacks complete skinning geometry.")
                }
                parts.append(Part(material: name, positions: positions, influences: influences,
                                  influencesPerVertex: influences.count / positions.count, triangles: triangles))
            }
        }
        self.parts = parts
        let globals = try Self.globals(model.jointTransforms, skeleton: skeleton)
        referenceBindingError = zip(globals, skeleton.joints).map {
            Self.matrixError($0 * $1.inverseBindPoseMatrix, matrix_identity_float4x4)
        }.max() ?? .infinity
    }

    func countCrossings(wrist: String) throws -> CrossingCount {
        guard let wristIndex = model.jointNames.firstIndex(where: { $0.split(separator: "/").last == Substring(wrist) }) else {
            throw GeometryError.invalid("The source wrist joint is missing.")
        }
        let globals = try Self.globals(model.jointTransforms, skeleton: skeleton)
        let skinMatrices = zip(globals, skeleton.joints).map { $0 * $1.inverseBindPoseMatrix }
        let worldFromModel = model.transformMatrix(relativeTo: nil)
        let handJoints = Set(skeleton.joints.indices.filter { index in
            var current: Int? = index
            while let value = current {
                if value == wristIndex { return true }
                current = skeleton.joints[value].parentIndex
            }
            return false
        })
        let wristPoint = worldFromModel * globals[wristIndex].columns.3
        let wristPosition = SIMD3(wristPoint.x, wristPoint.y, wristPoint.z)
        var hand: [Triangle] = []
        var cuff: [Triangle] = []
        for part in parts {
            var positions: [SIMD3<Float>] = []
            var selected: [Bool] = []
            for (index, point) in part.positions.enumerated() {
                var result = SIMD4<Float>(repeating: 0)
                var isHand = false
                for influence in part.influences[(index * part.influencesPerVertex)..<((index + 1) * part.influencesPerVertex)] {
                    result += (skinMatrices[influence.jointIndex] * SIMD4(point, 1)) * influence.weight
                    if influence.weight > 0.05 && handJoints.contains(influence.jointIndex) { isHand = true }
                }
                let worldPoint = worldFromModel * result
                positions.append(SIMD3(worldPoint.x, worldPoint.y, worldPoint.z))
                selected.append(isHand)
            }
            for index in stride(from: 0, to: part.triangles.count, by: 3) {
                let ids = (0..<3).map { Int(part.triangles[index + $0]) }
                let triangle = Triangle(a: positions[ids[0]], b: positions[ids[1]], c: positions[ids[2]])
                if part.material == "CharacterMaterial_16" {
                    if ids.contains(where: { simd_distance(positions[$0], wristPosition) < 0.2 }) { cuff.append(triangle) }
                } else if ids.contains(where: { selected[$0] }) { hand.append(triangle) }
            }
        }
        guard !hand.isEmpty, !cuff.isEmpty else { throw GeometryError.invalid("Empty hand or cuff selection.") }
        var pairs = 0
        for skin in hand {
            for cloth in cuff {
                guard !any(skin.maximum .< cloth.minimum), !any(cloth.maximum .< skin.minimum) else { continue }
                if Self.crosses(skin, cloth) { pairs += 1 }
            }
        }
        return CrossingCount(handTriangles: hand.count, cuffTriangles: cuff.count, crossingPairs: pairs)
    }

    private static func globals(_ transforms: [Transform], skeleton: MeshResource.Skeleton) throws -> [simd_float4x4] {
        var globals: [simd_float4x4] = []
        for (index, joint) in skeleton.joints.enumerated() {
            if let parent = joint.parentIndex {
                guard parent >= 0, parent < index else { throw GeometryError.invalid("Invalid joint topology.") }
                globals.append(globals[parent] * transforms[index].matrix)
            } else { globals.append(transforms[index].matrix) }
        }
        return globals
    }

    private static func crosses(_ left: Triangle, _ right: Triangle) -> Bool {
        let a = [left.a, left.b, left.c]
        let b = [right.a, right.b, right.c]
        return (0..<3).contains { segmentCrosses(a[$0], a[($0 + 1) % 3], right) }
            || (0..<3).contains { segmentCrosses(b[$0], b[($0 + 1) % 3], left) }
    }

    private static func segmentCrosses(_ start: SIMD3<Float>, _ end: SIMD3<Float>, _ triangle: Triangle) -> Bool {
        let edge = end - start
        let length = simd_length(edge)
        guard length > 0.00000001 else { return false }
        let direction = edge / length
        let first = triangle.b - triangle.a
        let second = triangle.c - triangle.a
        let cross = simd_cross(direction, second)
        let determinant = simd_dot(first, cross)
        guard abs(determinant) > 0.000000000001 else { return false }
        let origin = start - triangle.a
        let u = simd_dot(origin, cross) / determinant
        guard u >= 0, u <= 1 else { return false }
        let other = simd_cross(origin, first)
        let v = simd_dot(direction, other) / determinant
        guard v >= 0, u + v <= 1 else { return false }
        let distance = simd_dot(second, other) / determinant
        return distance > 0.000001 && distance < length - 0.000001
    }

    private static func matrixError(_ left: simd_float4x4, _ right: simd_float4x4) -> Float {
        (0..<4).flatMap { column in (0..<4).map { row in abs(left[column][row] - right[column][row]) } }.max() ?? 0
    }
}

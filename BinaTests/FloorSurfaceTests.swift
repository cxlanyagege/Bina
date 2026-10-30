import Foundation
import Testing
import simd

@testable import Bina

@MainActor
struct FloorSurfaceTests {
    @Test func triangulatedFloorHasNoArtificialBoundaryAcrossItsInternalDiagonal() {
        let surface = FloorTestGeometry.rectangle()
        #expect(surface.isUsableFloor)
        #expect(surface.contains([0, 0, 0], clearance: 0.2))
        #expect(surface.contains([1, 0, 1], clearance: 0.2))
        #expect(!surface.contains([2.95, 0, 0], clearance: 0.2))
    }

    @Test func concaveOutlineRejectsBoundingBoxCornersAndInsufficientFootRoom() throws {
        let surface = try #require(
            FloorSurface(
                id: UUID(), classification: .floor, originFromAnchor: matrix_identity_float4x4,
                vertices: [[0, 0, 0], [3, 0, 0], [3, 0, 1], [1, 0, 1], [1, 0, 3], [0, 0, 3]],
                triangleIndices: [0, 1, 3, 1, 2, 3, 0, 3, 5, 3, 4, 5]))
        #expect(surface.contains([0.5, 0, 2], clearance: 0.2))
        #expect(!surface.contains([2, 0, 2], clearance: 0.2))
        #expect(!surface.contains([0.9, 0, 1.1], clearance: 0.2))
    }

    @Test func floorMeshHolesAndTheirEdgesCannotSupportFeet() throws {
        let surface = try #require(
            FloorSurface(
                id: UUID(), classification: .floor, originFromAnchor: matrix_identity_float4x4,
                vertices: [
                    [-3, 0, -3], [3, 0, -3], [3, 0, 3], [-3, 0, 3], [-0.4, 0, -0.4], [0.4, 0, -0.4], [0.4, 0, 0.4],
                    [-0.4, 0, 0.4],
                ],
                triangleIndices: [0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7]))
        #expect(!surface.contains([0, 0, 0], clearance: 0.2))
        #expect(!surface.contains([0.5, 0, 0], clearance: 0.2))
        #expect(surface.contains([1, 0, 0], clearance: 0.2))
    }

    @Test func worldCoordinatesRespectPlaneTranslationAndRotation() throws {
        var frame = simd_float4x4(simd_quatf(angle: .pi / 3, axis: [0, 1, 0]))
        frame.columns.3 = [4, 0.3, -2, 1]
        let surface = FloorTestGeometry.rectangle(frame: frame)
        let p = frame * SIMD4<Float>(1, 0, 0, 1)
        #expect(surface.contains(SIMD3(p.x, p.y, p.z), clearance: 0.2))
        #expect(abs(try #require(surface.height(at: SIMD2(p.x, p.z))) - 0.3) < 0.00001)
    }

    @Test func firstReleaseRejectsNonFloorClassificationsAndSteepSurfaces() {
        #expect(!FloorTestGeometry.rectangle(kind: .other).isUsableFloor)
        #expect(!FloorTestGeometry.rectangle(kind: .unclassified).isUsableFloor)
        let mild = FloorTestGeometry.rectangle(frame: simd_float4x4(simd_quatf(angle: 2 * .pi / 180, axis: [1, 0, 0])))
        let steep = FloorTestGeometry.rectangle(
            frame: simd_float4x4(simd_quatf(angle: 5 * .pi / 180, axis: [1, 0, 0])))
        #expect(mild.isUsableFloor)
        #expect(!steep.isUsableFloor)
        #expect(steep.height(at: .zero) == nil)
    }

    @Test func malformedMeshesAndNonRigidTransformsAreRejected() {
        let points: [SIMD3<Float>] = [[-1, 0, -1], [1, 0, -1], [0, 0, 1]]
        for indices: [UInt32] in [[], [0, 1], [0, 1, 9], [0, 0, 0], [0, 1, 2, 0, 1, 2, 0, 1, 2]] {
            #expect(
                FloorSurface(
                    id: UUID(), classification: .floor, originFromAnchor: matrix_identity_float4x4,
                    vertices: points, triangleIndices: indices) == nil)
        }
        for change in 0..<4 {
            var frame = matrix_identity_float4x4
            switch change {
            case 0: frame.columns.0.x = .nan
            case 1: frame.columns.0.x = 0
            case 2: frame.columns.0.x = 1.1
            default: frame.columns.3.w = 0
            }
            #expect(
                FloorSurface(
                    id: UUID(), classification: .floor, originFromAnchor: frame,
                    vertices: points, triangleIndices: [0, 1, 2]) == nil)
        }
    }

    @Test func invalidClearanceCannotProduceAValidLanding() {
        let surface = FloorTestGeometry.rectangle()
        for radius: Float in [0, -1, .nan, .infinity] { #expect(!surface.contains(.zero, clearance: radius)) }
        #expect(!surface.contains([.nan, 0, 0], clearance: 0.2))
    }
}

nonisolated enum FloorTestGeometry {
    static let settings = FloorPlacementSettings(distance: 2, characterScale: 1, headingRadians: 0, contactRadius: 0.15)

    static func device(height: Float = 1.7) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3.y = height
        return matrix
    }

    static func rectangle(
        id: UUID = UUID(), height: Float = 0, kind: FloorSurface.Classification = .floor,
        halfWidth: Float = 3, halfDepth: Float = 4, frame: simd_float4x4? = nil
    ) -> FloorSurface {
        var matrix = frame ?? matrix_identity_float4x4
        if frame == nil { matrix.columns.3.y = height }
        return FloorSurface(
            id: id, classification: kind, originFromAnchor: matrix,
            vertices: [
                [-halfWidth, 0, -halfDepth], [halfWidth, 0, -halfDepth], [halfWidth, 0, halfDepth],
                [-halfWidth, 0, halfDepth],
            ],
            triangleIndices: [0, 1, 2, 0, 2, 3])!
    }
}

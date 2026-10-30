import Foundation
import simd

/// A copied plane mesh in anchor-local meters; independent of ARKit buffer lifetimes.
nonisolated struct FloorSurface {
    enum Classification { case floor, unclassified, other }
    private struct Edge: Hashable {
        let a: Int
        let b: Int
        init(_ a: Int, _ b: Int) {
            self.a = min(a, b)
            self.b = max(a, b)
        }
    }

    let id: UUID
    let classification: Classification
    let originFromAnchor: simd_float4x4
    let normal: SIMD3<Float>
    private let anchorFromOrigin: simd_float4x4
    private let vertices: [SIMD2<Float>]
    private let triangles: [[Int]]
    private let boundary: [(SIMD2<Float>, SIMD2<Float>)]

    init?(
        id: UUID, classification: Classification, originFromAnchor: simd_float4x4,
        vertices: [SIMD3<Float>], triangleIndices: [UInt32]
    ) {
        guard (3...8192).contains(vertices.count), !triangleIndices.isEmpty,
            triangleIndices.count <= 49152, triangleIndices.count % 3 == 0,
            vertices.allSatisfy({ p in (0..<3).allSatisfy { p[$0].isFinite } && abs(p.y) < 0.01 }),
            triangleIndices.allSatisfy({ Int($0) < vertices.count }),
            (0..<4).allSatisfy({ c in (0..<4).allSatisfy { originFromAnchor[c][$0].isFinite } }),
            abs(originFromAnchor.columns.0.w) < 0.0001, abs(originFromAnchor.columns.1.w) < 0.0001,
            abs(originFromAnchor.columns.2.w) < 0.0001, abs(originFromAnchor.columns.3.w - 1) < 0.0001
        else { return nil }
        let basis = (0..<3).map { Self.xyz(originFromAnchor[$0]) }
        guard basis.allSatisfy({ abs(simd_length_squared($0) - 1) < 0.002 }),
            abs(simd_dot(basis[0], basis[1])) < 0.002, abs(simd_dot(basis[1], basis[2])) < 0.002,
            abs(simd_dot(basis[0], basis[2])) < 0.002, simd_determinant(originFromAnchor) > 0.99
        else { return nil }
        let points = vertices.map { SIMD2($0.x, $0.z) }
        var edges: [Edge: Int] = [:]
        var triangles: [[Int]] = []
        var area: Float = 0
        for offset in stride(from: 0, to: triangleIndices.count, by: 3) {
            let indices = (0..<3).map { Int(triangleIndices[offset + $0]) }
            let twiceArea = abs(
                Self.cross(points[indices[1]] - points[indices[0]], points[indices[2]] - points[indices[0]]))
            if twiceArea <= 0.00000001 { continue }
            area += twiceArea / 2
            triangles.append(indices)
            for i in 0..<3 { edges[Edge(indices[i], indices[(i + 1) % 3]), default: 0] += 1 }
        }
        guard area.isFinite, area > 0.01, edges.values.allSatisfy({ $0 <= 2 }) else { return nil }
        let boundary = edges.filter { $0.value == 1 }.map { (points[$0.key.a], points[$0.key.b]) }
        guard !boundary.isEmpty else { return nil }
        self.id = id
        self.classification = classification
        self.originFromAnchor = originFromAnchor
        normal = simd_normalize(basis[1])
        anchorFromOrigin = simd_inverse(originFromAnchor)
        self.vertices = points
        self.triangles = triangles
        self.boundary = boundary
    }

    var isUsableFloor: Bool { classification == .floor && abs(normal.y) >= cos(3 * Float.pi / 180) }
    var origin: SIMD3<Float> { Self.xyz(originFromAnchor.columns.3) }

    func height(at point: SIMD2<Float>) -> Float? {
        guard isUsableFloor else { return nil }
        let result = origin.y - (normal.x * (point.x - origin.x) + normal.z * (point.y - origin.z)) / normal.y
        return result.isFinite ? result : nil
    }

    /// Checks the actual mesh union and its boundary, including concavities and holes.
    func contains(_ worldPoint: SIMD3<Float>, clearance: Float) -> Bool {
        guard clearance.isFinite, clearance > 0 else { return false }
        let local = anchorFromOrigin * SIMD4(worldPoint, 1)
        let p = SIMD2(local.x, local.z)
        guard
            triangles.contains(where: { t in
                let a = Self.cross(vertices[t[1]] - vertices[t[0]], p - vertices[t[0]])
                let b = Self.cross(vertices[t[2]] - vertices[t[1]], p - vertices[t[1]])
                let c = Self.cross(vertices[t[0]] - vertices[t[2]], p - vertices[t[2]])
                return (a >= -0.000001 && b >= -0.000001 && c >= -0.000001)
                    || (a <= 0.000001 && b <= 0.000001 && c <= 0.000001)
            })
        else { return false }
        return boundary.allSatisfy { a, b in
            let axis = b - a
            let length = simd_length_squared(axis)
            let amount = length > 0 ? max(0, min(1, simd_dot(p - a, axis) / length)) : 0
            return simd_distance(p, a + axis * amount) >= clearance - 0.00001
        }
    }

    func isStable(comparedTo previous: FloorSurface) -> Bool {
        guard let y = height(at: SIMD2(previous.origin.x, previous.origin.z)) else { return false }
        // Re-basing a plane can change the meaning of a frozen world-space preview.
        // Conservatively require a fresh preview after significant frame corrections.
        return abs(y - previous.origin.y) <= 0.01 && simd_distance(origin, previous.origin) <= 0.02
            && simd_dot(normal, previous.normal) >= cos(Float.pi / 180)
            && simd_dot(Self.xyz(originFromAnchor.columns.0), Self.xyz(previous.originFromAnchor.columns.0))
                >= cos(Float.pi / 180)
    }

    private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
    private static func xyz(_ p: SIMD4<Float>) -> SIMD3<Float> { SIMD3(p.x, p.y, p.z) }
}

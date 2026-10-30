import simd

/// Shared strict surface-crossing checks for actual skinned-mesh regressions.
nonisolated enum TestTriangleGeometry {
    struct Triangle {
        let a: SIMD3<Float>
        let b: SIMD3<Float>
        let c: SIMD3<Float>
        var minimum: SIMD3<Float> { simd_min(a, simd_min(b, c)) }
        var maximum: SIMD3<Float> { simd_max(a, simd_max(b, c)) }
    }
    static func crosses(_ left: Triangle, _ right: Triangle) -> Bool {
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

}

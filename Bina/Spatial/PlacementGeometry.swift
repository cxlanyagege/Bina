import simd

enum PlacementGeometry {
    /// Places an upright character ahead of the device, facing the user without inheriting head tilt.
    nonisolated static func transform(
        inFrontOf deviceTransform: simd_float4x4,
        distance: Float,
        verticalOffset: Float
    ) -> simd_float4x4? {
        guard distance.isFinite, distance > 0, verticalOffset.isFinite else {
            return nil
        }

        for column in 0..<4 {
            for row in 0..<4 where !deviceTransform[column][row].isFinite {
                return nil
            }
        }

        let deviceForward = -SIMD3<Float>(
            deviceTransform.columns.2.x,
            0,
            deviceTransform.columns.2.z
        )
        let horizontalLength = simd_length(deviceForward)
        guard horizontalLength.isFinite, horizontalLength > 0.0001 else {
            return nil
        }

        let forward = deviceForward / horizontalLength
        let devicePosition = SIMD3<Float>(
            deviceTransform.columns.3.x,
            deviceTransform.columns.3.y,
            deviceTransform.columns.3.z
        )
        let position = devicePosition + forward * distance + SIMD3<Float>(0, verticalOffset, 0)
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            return nil
        }

        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_cross(up, forward)
        return simd_float4x4(columns: (
            SIMD4<Float>(right, 0),
            SIMD4<Float>(up, 0),
            SIMD4<Float>(forward, 0),
            SIMD4<Float>(position, 1)
        ))
    }
}

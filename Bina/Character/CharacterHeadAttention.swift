import Foundation
import simd

/// Selects and smooths a bounded head target in the character's upright frame.
nonisolated struct CharacterHeadAttention {
    static let maximumYaw: Float = 25 * .pi / 180
    static let maximumUpwardPitch: Float = 12 * .pi / 180
    static let maximumDownwardPitch: Float = 10 * .pi / 180
    static let maximumSpeed: Float = 30 * .pi / 180
    static let deadZone: Float = 1.5 * .pi / 180

    /// Yaw is positive toward character-local +X; pitch is positive upward.
    private(set) var angles = SIMD2<Float>.zero
    private var heldTarget = SIMD2<Float>.zero

    /// `direction` is measured in meters, with Y up and negative Z forward.
    mutating func advance(by deltaTime: TimeInterval, direction: SIMD3<Float>?, poseWeight: Float = 1) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let step = Float(min(deltaTime, 0.1))
        // Blend the target before smoothing so stance transitions cannot amplify
        // the displayed turn beyond the angular speed limit.
        let weight = poseWeight.isFinite ? max(0, min(1, poseWeight)) : 0
        let desired = Self.target(for: direction) * weight
        if desired == .zero {
            heldTarget = .zero
        } else {
            for axis in 0..<2 {
                let difference = desired[axis] - heldTarget[axis]
                if abs(difference) > Self.deadZone {
                    heldTarget[axis] = desired[axis] - copysign(Self.deadZone, difference)
                }
            }
        }
        let response: Float = heldTarget == .zero ? 0.45 : 0.35
        var movement = (heldTarget - angles) * (1 - exp(-step / response))
        let distance = simd_length(movement)
        let limit = Self.maximumSpeed * step
        if distance > limit { movement *= limit / distance }
        angles += movement
        if simd_length(angles) < 0.00001, heldTarget == .zero { angles = .zero }
    }

    /// Keep the displayed orientation while discarding target hysteresis on interruption.
    mutating func invalidateTarget() {
        heldTarget = .zero
    }

    mutating func reset() {
        angles = .zero
        heldTarget = .zero
    }

    static func target(for direction: SIMD3<Float>?) -> SIMD2<Float> {
        guard let direction, (0..<3).allSatisfy({ direction[$0].isFinite }) else { return .zero }
        let distance = simd_length(direction)
        guard distance.isFinite, distance > 0.45 else { return .zero }
        let horizontal = simd_length(SIMD2(direction.x, direction.z))
        let yaw = atan2(direction.x, -direction.z)
        let pitch = atan2(direction.y, horizontal)
        let weight = smoothRange(distance, from: 0.45, to: 0.7)
            * (1 - smoothRange(abs(yaw), from: 55 * .pi / 180, to: 80 * .pi / 180))
            * (1 - smoothRange(abs(pitch), from: 35 * .pi / 180, to: 60 * .pi / 180))
        return SIMD2(
            max(-maximumYaw, min(maximumYaw, yaw)),
            max(-maximumDownwardPitch, min(maximumUpwardPitch, pitch))
        ) * weight
    }

    static func rotation(for angles: SIMD2<Float>) -> simd_quatf {
        simd_quatf(angle: -angles.x, axis: [0, 1, 0])
            * simd_quatf(angle: angles.y, axis: [1, 0, 0])
    }

    private static func smoothRange(_ value: Float, from lower: Float, to upper: Float) -> Float {
        let progress = max(0, min(1, (value - lower) / (upper - lower)))
        return progress * progress * (3 - 2 * progress)
    }
}

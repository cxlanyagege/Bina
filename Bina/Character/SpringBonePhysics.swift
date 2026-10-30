import Foundation
import simd

/// Geometry for the accessory solver, expressed in reference-height character meters.
nonisolated struct SpringCapsule {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let radius: Float

    func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        let axis = end - start
        let lengthSquared = simd_length_squared(axis)
        guard lengthSquared > 0.00000001 else { return start }
        let amount = max(0, min(1, simd_dot(point - start, axis) / lengthSquared))
        return start + axis * amount
    }

    /// Returns closest points on two finite segments, including degenerate cases.
    static func closestPair(
        _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>
    ) -> (first: SIMD3<Float>, second: SIMD3<Float>, amount: Float) {
        let u = b - a, v = d - c, w = a - c
        let uu = simd_dot(u, u), vv = simd_dot(v, v)
        let vw = simd_dot(v, w), uw = simd_dot(u, w), uv = simd_dot(u, v)
        let epsilon: Float = 0.00000001
        var s: Float = 0, t: Float = 0
        if uu <= epsilon {
            if vv > epsilon { t = max(0, min(1, vw / vv)) }
        } else if vv <= epsilon {
            s = max(0, min(1, -uw / uu))
        } else {
            let denominator = uu * vv - uv * uv
            if denominator > epsilon * uu * vv { s = max(0, min(1, (uv * vw - uw * vv) / denominator)) }
            t = (uv * s + vw) / vv
            if t < 0 { t = 0; s = max(0, min(1, -uw / uu)) }
            else if t > 1 { t = 1; s = max(0, min(1, (uv - uw) / uu)) }
        }
        return (a + u * s, c + v * t, s)
    }
}

/// A damped, length-constrained spring with thickness-aware capsule contacts.
nonisolated struct SpringBoneState {
    private(set) var tail: SIMD3<Float>
    private var previousTail: SIMD3<Float>

    init(tail: SIMD3<Float>) {
        self.tail = tail
        previousTail = tail
    }

    mutating func advance(
        root: SIMD3<Float>, restTail: SIMD3<Float>, step: Float,
        settings: CharacterPhysicsProfile.Chain, colliders: [SpringCapsule]
    ) -> Bool {
        let rest = restTail - root
        let length = simd_length(rest)
        guard length.isFinite, length > 0.001, step.isFinite, step > 0 else { return false }
        let oldTail = tail
        var next = tail + (tail - previousTail) * exp(-settings.damping * step)
            + ((restTail - tail) * settings.stiffness + SIMD3(settings.gravity)) * step * step
        let restDirection = rest / length
        for _ in 0..<8 {
            let direction = Self.direction(next - root, fallback: restDirection)
            let angle = acos(max(-1, min(1, simd_dot(direction, restDirection))))
            if angle > settings.maximumAngle {
                let turn = simd_quatf(from: restDirection, to: direction)
                next = root + simd_slerp(simd_quatf(), turn, settings.maximumAngle / angle).act(rest)
            } else { next = root + direction * length }
            for collider in colliders {
                let contact = SpringCapsule.closestPair(root, next, collider.start, collider.end)
                let separation = contact.first - contact.second
                let distance = simd_length(separation)
                let clearance = collider.radius + settings.radius
                guard distance < clearance, contact.amount > 0.01 else { continue }
                // Move the free end enough to separate the lock segment; testing
                // only its tip misses collisions halfway along a wide hair lock.
                let towardRest = restTail - collider.closestPoint(to: restTail)
                let lateral = towardRest - restDirection * simd_dot(towardRest, restDirection)
                let axis: SIMD3<Float> = abs(restDirection.x) < 0.9 ? [1, 0, 0] : [0, 0, 1]
                let fallback = Self.direction(simd_cross(restDirection, axis), fallback: [1, 0, 0])
                let normal = Self.direction(separation, fallback: Self.direction(lateral, fallback: fallback))
                next += normal * min(0.025, (clearance - distance) / max(contact.amount, 0.2))
            }
        }
        next = root + Self.direction(next - root, fallback: restDirection) * length
        guard (0..<3).allSatisfy({ next[$0].isFinite }) else { return false }
        previousTail = oldTail
        tail = next
        return true
    }

    private static func direction(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        return length.isFinite && length > 0.000001 ? value / length : fallback
    }
}

/// A bounded fixed-step clock; interruptions discard stored kinetic history.
nonisolated struct SpringSimulationClock {
    static let step: TimeInterval = 1.0 / 120
    private var accumulator: TimeInterval = 0

    mutating func advance(_ deltaTime: TimeInterval) -> (steps: Int, needsReset: Bool) {
        guard deltaTime.isFinite, deltaTime > 0 else { return (0, false) }
        guard deltaTime <= 0.05 else { accumulator = 0; return (0, true) }
        accumulator += deltaTime
        let steps = min(6, Int((accumulator + 0.000000001) / Self.step))
        accumulator = max(0, accumulator - Double(steps) * Self.step)
        return (steps, false)
    }

    mutating func reset() { accumulator = 0 }
}

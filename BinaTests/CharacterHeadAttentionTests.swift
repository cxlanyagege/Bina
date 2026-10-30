import Foundation
import simd
import Testing
@testable import Bina

@MainActor
struct CharacterHeadAttentionTests {
    @Test func selectsTheCorrectSideAndHeight() {
        #expect(CharacterHeadAttention.target(for: [0, 0, -2]) == .zero)
        #expect(CharacterHeadAttention.target(for: [0.5, 0.2, -2]).x > 0)
        #expect(CharacterHeadAttention.target(for: [-0.5, -0.2, -2]).x < 0)
        #expect(CharacterHeadAttention.target(for: [0.5, 0.2, -2]).y > 0)
        #expect(CharacterHeadAttention.target(for: [-0.5, -0.2, -2]).y < 0)
        let direction = CharacterHeadAttention.rotation(for: [0.2, 0.1]).act([0, 0, -1])
        #expect(direction.x > 0)
        #expect(direction.y > 0)
        #expect(direction.z < 0)
    }

    @Test func boundsEverySupportedDirection() {
        for yaw in stride(from: Float(-180), through: 180, by: 5) {
            for pitch in stride(from: Float(-85), through: 85, by: 5) {
                let target = CharacterHeadAttention.target(for: direction(yaw: yaw, pitch: pitch))
                #expect(abs(target.x) <= CharacterHeadAttention.maximumYaw)
                #expect(target.y <= CharacterHeadAttention.maximumUpwardPitch)
                #expect(target.y >= -CharacterHeadAttention.maximumDownwardPitch)
            }
        }
    }

    @Test func rejectsRearCloseVerticalMissingAndNonfiniteTargets() {
        let invalid: [SIMD3<Float>?] = [nil, .zero, [0, 0, 2], [2, 0, 0], [0.1, 0, -0.1],
            [0, 2, 0], [0, -2, 0], [.nan, 0, -2], [0, .infinity, -2], [0, 0, -.infinity]]
        for target in invalid { #expect(CharacterHeadAttention.target(for: target) == .zero) }
    }

    @Test func fadesAtTheConeAndDistanceBoundaries() {
        let middle = CharacterHeadAttention.target(for: direction(yaw: 20))
        let nearby = CharacterHeadAttention.target(for: direction(yaw: 20, distance: 0.55))
        let nearBoundary = CharacterHeadAttention.target(for: direction(yaw: 20, distance: 0.451))
        #expect(nearby.x > 0 && nearby.x < middle.x)
        #expect(nearBoundary.x >= 0 && nearBoundary.x < 0.0001)
        let edge = CharacterHeadAttention.target(for: direction(yaw: 70))
        let farEdge = CharacterHeadAttention.target(for: direction(yaw: 79.99))
        #expect(edge.x > 0 && edge.x < CharacterHeadAttention.maximumYaw)
        #expect(farEdge.x >= 0 && farEdge.x < 0.0001)
        #expect(CharacterHeadAttention.target(for: direction(yaw: 81)) == .zero)
    }

    @Test func smallCenteredNoiseDoesNotMoveTheHead() {
        var attention = CharacterHeadAttention()
        for frame in 0..<180 {
            attention.advance(by: 1.0 / 60, direction: direction(yaw: frame.isMultiple(of: 2) ? 0.7 : -0.7, pitch: 0.5))
        }
        #expect(attention.angles == .zero)
    }

    @Test func approachesTheTargetSmoothlyWithoutOvershoot() {
        var attention = CharacterHeadAttention()
        var previous = SIMD2<Float>.zero
        for _ in 0..<240 {
            attention.advance(by: 1.0 / 60, direction: direction(yaw: 40, pitch: 25))
            #expect(attention.angles.x >= previous.x)
            #expect(attention.angles.y >= previous.y)
            #expect(simd_distance(previous, attention.angles) <= CharacterHeadAttention.maximumSpeed / 60 + 0.000001)
            #expect(attention.angles.x <= CharacterHeadAttention.maximumYaw)
            #expect(attention.angles.y <= CharacterHeadAttention.maximumUpwardPitch)
            previous = attention.angles
        }
        #expect(attention.angles.x > 20 * .pi / 180)
        #expect(attention.angles.y > 8 * .pi / 180)
    }

    @Test func missingTargetsReturnGraduallyToNeutral() {
        var attention = CharacterHeadAttention()
        for _ in 0..<180 { attention.advance(by: 1.0 / 60, direction: direction(yaw: -30, pitch: -20)) }
        let previous = attention.angles
        attention.advance(by: 1.0 / 60, direction: nil)
        #expect(attention.angles.x > previous.x && attention.angles.x < 0)
        #expect(simd_distance(attention.angles, previous) <= CharacterHeadAttention.maximumSpeed / 60 + 0.000001)
        for _ in 0..<360 { attention.advance(by: 1.0 / 60, direction: nil) }
        #expect(attention.angles == .zero)
    }

    @Test func invalidTimestepsFreezeAndLongGapsAreCapped() {
        var attention = CharacterHeadAttention()
        attention.advance(by: 0.1, direction: direction(yaw: 25))
        let previous = attention.angles
        for step: TimeInterval in [0, -1, .nan, .infinity, -.infinity] {
            attention.advance(by: step, direction: direction(yaw: -25))
            #expect(attention.angles == previous)
        }
        var capped = attention
        attention.advance(by: 120, direction: direction(yaw: -25))
        capped.advance(by: 0.1, direction: direction(yaw: -25))
        #expect(attention.angles == capped.angles)
    }

    @Test func responseIsStableAcrossFrameRates() {
        func sample(fps: Int) -> SIMD2<Float> {
            var attention = CharacterHeadAttention()
            for _ in 0..<(fps * 2) { attention.advance(by: 1.0 / Double(fps), direction: direction(yaw: 22, pitch: 10)) }
            return attention.angles
        }
        #expect(simd_distance(sample(fps: 30), sample(fps: 90)) < 0.003)
    }

    @Test func interruptionDiscardsTheHeldTargetWithoutSnapping() {
        var attention = CharacterHeadAttention()
        for _ in 0..<180 { attention.advance(by: 1.0 / 60, direction: direction(yaw: 20)) }
        let previous = attention.angles
        attention.invalidateTarget()
        #expect(attention.angles == previous)
        attention.advance(by: 1.0 / 60, direction: direction(yaw: 0.5))
        #expect(attention.angles.x < previous.x)
        attention.reset()
        #expect(attention.angles == .zero)
    }

    @Test func stanceTransitionPreservesTheAngularSpeedLimit() {
        var attention = CharacterHeadAttention()
        let target = direction(yaw: 40, pitch: 25)
        attention.advance(by: 1.0 / 60, direction: target, poseWeight: 0)
        #expect(attention.angles == .zero)
        var playback = CharacterIdlePlayback()
        playback.showNatural()
        for _ in 0..<180 {
            let previous = attention.angles
            playback.advance(by: 1.0 / 60, isVisible: true)
            attention.advance(by: 1.0 / 60, direction: target, poseWeight: playback.naturalPoseWeight)
            #expect(simd_distance(previous, attention.angles) <= CharacterHeadAttention.maximumSpeed / 60 + 0.000001)
        }
        #expect(attention.angles.x > 20 * .pi / 180)
    }

    private func direction(yaw: Float, pitch: Float = 0, distance: Float = 2) -> SIMD3<Float> {
        let yaw = yaw * .pi / 180
        let pitch = pitch * .pi / 180
        return SIMD3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * distance
    }
}

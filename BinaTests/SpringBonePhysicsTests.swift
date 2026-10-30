import Foundation
import simd
import Testing
@testable import Bina

@MainActor
struct SpringBonePhysicsTests {
    @Test func capsuleQueriesHandleParallelAndDegenerateSegments() {
        let capsule = SpringCapsule(start: [0,0,0], end: [0,1,0], radius: 0.1)
        #expect(simd_distance(capsule.closestPoint(to: [1,0.5,0]), [0,0.5,0]) < 0.000001)
        let pair = SpringCapsule.closestPair([0,0,0], [0,1,0], [1,0,0], [1,1,0])
        #expect(abs(simd_distance(pair.first, pair.second) - 1) < 0.000001)
        let point = SpringCapsule.closestPair(.zero, .zero, [1,0,0], [1,0,0])
        #expect(simd_distance(point.first, point.second) == 1)
        let crossing = SpringCapsule.closestPair([-1,0,0], [1,0,0], [0,-1,0], [0,1,0])
        #expect(simd_distance(crossing.first, crossing.second) < 0.000001)
        let tiny = SpringCapsule.closestPair([-0.01,0,0], [0.01,0,0], [0,-0.01,0], [0,0.01,0])
        #expect(simd_distance(tiny.first, tiny.second) < 0.000001)
    }

    @Test func stationarySpringRetainsItsAuthoredShape() {
        let tail = SIMD3<Float>(0.02, -0.12, 0.03)
        var spring = SpringBoneState(tail: tail)
        for _ in 0..<360 {
            let advanced1 = spring.advance(root: .zero, restTail: tail, step: 1.0/120, settings: settings(), colliders: [])
            #expect(advanced1)
            #expect(simd_distance(spring.tail, tail) < 0.000001)
        }
    }

    @Test func movingRootCreatesLagThenSettles() {
        var spring = SpringBoneState(tail: [0,-0.12,0])
        let root = SIMD3<Float>(0.025,0,0), rest = SIMD3<Float>(0.025,-0.12,0)
        let advanced2 = spring.advance(root: root, restTail: rest, step: 1.0/120, settings: settings(), colliders: [])
        #expect(advanced2)
        #expect(spring.tail.x < rest.x - 0.01)
        for _ in 0..<720 {
            let advanced3 = spring.advance(root: root, restTail: rest, step: 1.0/120, settings: settings(), colliders: [])
            #expect(advanced3)
            #expect(abs(simd_distance(root, spring.tail) - 0.12) < 0.000001)
        }
        #expect(simd_distance(spring.tail, rest) < 0.0001)
    }

    @Test func segmentContactIsDetectedWhenBothEndpointsAreOutside() {
        let root = SIMD3<Float>(0,0.1,0), rest = SIMD3<Float>(0,-0.1,0)
        let capsule = SpringCapsule(start: [0.015,0,0], end: [0.015,0,0], radius: 0.035)
        var spring = SpringBoneState(tail: rest)
        for _ in 0..<240 {
            let advanced4 = spring.advance(root: root, restTail: rest, step: 1.0/120, settings: settings(), colliders: [capsule])
            #expect(advanced4)
        }
        let contact = SpringCapsule.closestPair(root, spring.tail, capsule.start, capsule.end)
        #expect(simd_distance(contact.first, contact.second) > 0.039)
        #expect(abs(simd_distance(root, spring.tail) - 0.2) < 0.000001)
    }

    @Test func centeredContactsHaveAFiniteDeterministicEscape() {
        let root = SIMD3<Float>(0,0.1,0), rest = SIMD3<Float>(0,-0.1,0)
        let collider = SpringCapsule(start: .zero, end: .zero, radius: 0.025)
        var a = SpringBoneState(tail: rest), b = a
        for _ in 0..<120 {
            let advanced5 = a.advance(root: root, restTail: rest, step: 1.0/120, settings: settings(), colliders: [collider])
            #expect(advanced5)
            let advanced6 = b.advance(root: root, restTail: rest, step: 1.0/120, settings: settings(), colliders: [collider])
            #expect(advanced6)
        }
        #expect(a.tail == b.tail)
        let pair = SpringCapsule.closestPair(root, a.tail, .zero, .zero)
        #expect(simd_distance(pair.first, pair.second) > 0.029)
    }

    @Test func invalidSpringInputsDoNotPoisonState() {
        let rest = SIMD3<Float>(0,-0.1,0)
        var spring = SpringBoneState(tail: rest)
        let advanced7 = spring.advance(root: .zero, restTail: .zero, step: 1.0/120, settings: settings(), colliders: [])
        #expect(!advanced7)
        let advanced8 = spring.advance(root: [.nan,0,0], restTail: rest, step: 1.0/120, settings: settings(), colliders: [])
        #expect(!advanced8)
        let advanced9 = spring.advance(root: .zero, restTail: rest, step: 0, settings: settings(), colliders: [])
        #expect(!advanced9)
        #expect(spring.tail == rest)
    }

    @Test func unsatisfiableContactsRespectTheBendLimitWithoutAddingAnImpulse() {
        let rest = SIMD3<Float>(0,-0.12,0)
        let collider = SpringCapsule(start: [0.005,-0.06,0], end: [0.005,-0.06,0], radius: 0.06)
        var spring = SpringBoneState(tail: rest)
        let advanced = spring.advance(root: .zero, restTail: rest, step: 1.0/120, settings: settings(), colliders: [collider])
        #expect(advanced)
        let angle = acos(max(-1, min(1, simd_dot(simd_normalize(spring.tail), simd_normalize(rest)))))
        #expect(angle <= settings().maximumAngle + 0.00001)
        #expect(abs(simd_length(spring.tail) - simd_length(rest)) < 0.000001)

        let separated = spring.tail
        let released = spring.advance(root: .zero, restTail: rest, step: 1.0/120, settings: settings(), colliders: [])
        #expect(released)
        #expect(simd_distance(spring.tail, separated) < 0.002)
    }

    @Test func contactCorrectionsRespectTheConfiguredAngularSpeed() {
        let rest = SIMD3<Float>(0,-0.12,0)
        let collider = SpringCapsule(start: [0.005,-0.06,0], end: [0.005,-0.06,0], radius: 0.06)
        var configuration = settings()
        configuration.maximumChainAngle = 0.65
        configuration.maximumAngularSpeed = 2
        var spring = SpringBoneState(tail: rest)
        let initialized = spring.advance(root: .zero, restTail: rest, step: 1.0/120, settings: configuration, colliders: [])
        #expect(initialized)
        for frame in 0..<360 {
            let previous = simd_normalize(spring.tail)
            let advanced = spring.advance(root: .zero, restTail: rest, step: 1.0/120, settings: configuration,
                colliders: frame < 180 ? [collider] : [])
            #expect(advanced)
            let angle = acos(max(-1, min(1, simd_dot(previous, simd_normalize(spring.tail)))))
            #expect(angle <= 2.0/120 + 0.0001)
        }
        #expect(simd_distance(spring.tail, rest) < 0.001)
    }

    @Test func fixedClockProducesTheSameStepsAtDifferentRenderRates() {
        for fps in [30,60,90,120] {
            var clock = SpringSimulationClock(), count = 0
            for _ in 0..<fps {
                let result = clock.advance(1.0 / Double(fps))
                #expect(!result.needsReset)
                count += result.steps
            }
            #expect(count == 120)
        }
    }

    @Test func invalidTimeAndInterruptionsCannotCauseUnboundedCatchup() {
        var clock = SpringSimulationClock()
        #expect(clock.advance(0.004).steps == 0)
        for time: TimeInterval in [0,-1,.nan,.infinity] { #expect(clock.advance(time).steps == 0) }
        #expect(clock.advance(0.005).steps == 1)
        let delayed = clock.advance(10)
        #expect(delayed.needsReset && delayed.steps == 0)
        #expect(clock.advance(1.0/120).steps == 1)
        clock.reset()
        #expect(clock.advance(0.001).steps == 0)
    }

    private func settings() -> CharacterPhysicsProfile.Chain {
        .init(name: "Test lock", joints: ["Joint_0001"], tipOffset: [0,-0.1,0], radius: 0.005,
              stiffness: 180, damping: 14, gravity: [0,0,0], maximumAngle: 0.65)
    }
}

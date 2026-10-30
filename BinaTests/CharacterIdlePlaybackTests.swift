import Foundation
import Testing
@testable import Bina

@MainActor
struct CharacterIdlePlaybackTests {
    @Test func startsInTheNaturalPoseAtRestingBreath() {
        let playback = CharacterIdlePlayback()

        #expect(playback.mode == .playing)
        #expect(playback.cycleTime == 0)
        #expect(playback.naturalPoseWeight == 1)
        #expect(playback.breath == 0)
        #expect(playback.sway == 0)
    }

    @Test func producesBoundedBreathingAndSwayOverACompleteCycle() {
        var playback = CharacterIdlePlayback()

        for frame in 1...220 {
            let advanced = playback.advance(by: 0.05, isVisible: true)
            #expect(advanced)
            #expect((0..<CharacterIdlePlayback.cycleDuration).contains(playback.cycleTime))
            #expect((0...1).contains(playback.breath))
            #expect((-1...1).contains(playback.sway))
            if frame == 55 {
                #expect(abs(playback.breath - 1) < 0.000001)
                #expect(abs(playback.sway - 1) < 0.000001)
            }
        }

        #expect(abs(playback.breath) < 0.000001)
        #expect(abs(playback.sway) < 0.000001)
        #expect(playback.naturalPoseWeight == 1)
    }

    @Test func cycleWrapDoesNotIntroduceAPoseJump() {
        var playback = CharacterIdlePlayback()
        for _ in 0..<219 { playback.advance(by: 0.05, isVisible: true) }
        let breathBefore = playback.breath
        let swayBefore = playback.sway

        playback.advance(by: 0.1, isVisible: true)

        #expect(abs(playback.cycleTime - 0.05) < 0.000001)
        #expect(abs(playback.breath - breathBefore) < 0.000001)
        #expect(abs(playback.sway - swayBefore) < 0.06)
    }

    @Test func pauseAndResumePreserveTheCurrentPoseAndTransition() {
        var playback = CharacterIdlePlayback()
        playback.showNatural()
        for _ in 0..<3 { playback.advance(by: 0.1, isVisible: true) }
        let time = playback.cycleTime
        let weight = playback.naturalPoseWeight
        let breath = playback.breath
        let sway = playback.sway

        playback.pause()

        #expect(playback.mode == .paused)
        let advancedWhilePaused = playback.advance(by: 30, isVisible: true)
        #expect(!advancedWhilePaused)
        #expect(playback.cycleTime == time)
        #expect(playback.naturalPoseWeight == weight)
        #expect(playback.breath == breath)
        #expect(playback.sway == sway)

        playback.resume()

        #expect(playback.mode == .playing)
        #expect(playback.cycleTime == time)
        let advancedAfterResuming = playback.advance(by: 0.05, isVisible: true)
        #expect(advancedAfterResuming)
        #expect(abs(playback.cycleTime - time - 0.05) < 0.000001)
        #expect(playback.naturalPoseWeight > weight)
    }

    @Test func hiddenPreviewFreezesWithoutChangingPlaybackIntent() {
        var playback = CharacterIdlePlayback()
        playback.showNatural()
        playback.advance(by: 0.1, isVisible: true)
        let time = playback.cycleTime
        let weight = playback.naturalPoseWeight

        let advancedWhileHidden = playback.advance(by: 60, isVisible: false)
        #expect(!advancedWhileHidden)
        #expect(playback.mode == .playing)
        #expect(playback.cycleTime == time)
        #expect(playback.naturalPoseWeight == weight)

        playback.advance(by: 0.05, isVisible: true)
        #expect(abs(playback.cycleTime - time - 0.05) < 0.000001)
    }

    @Test func invalidFrameDurationsCannotChangeThePose() {
        var playback = CharacterIdlePlayback()
        playback.showNatural()
        playback.advance(by: 0.1, isVisible: true)
        let time = playback.cycleTime
        let weight = playback.naturalPoseWeight

        for duration: TimeInterval in [0, -1, .nan, .infinity, -.infinity] {
            let advanced = playback.advance(by: duration, isVisible: true)
            #expect(!advanced)
            #expect(playback.cycleTime == time)
            #expect(playback.naturalPoseWeight == weight)
            #expect(playback.mode == .playing)
        }
    }

    @Test func delayedFrameAdvancesByAtMostOneTenthOfASecond() {
        var playback = CharacterIdlePlayback()
        playback.showNatural()

        let advanced = playback.advance(by: 120, isVisible: true)
        #expect(advanced)
        #expect(abs(playback.cycleTime - 0.1) < 0.000001)
        #expect(playback.naturalPoseWeight > 0)
        #expect(playback.naturalPoseWeight < 0.1)
    }

    @Test func referencePoseStaysSelectedUntilNaturalPoseIsRequested() {
        var playback = CharacterIdlePlayback()
        playback.advance(by: 0.1, isVisible: true)
        playback.showReference()

        #expect(playback.mode == .reference)
        #expect(playback.cycleTime == 0)
        #expect(playback.naturalPoseWeight == 0)
        #expect(playback.breath == 0)
        #expect(playback.sway == 0)
        let advancedWhileReference = playback.advance(by: 0.1, isVisible: true)
        #expect(!advancedWhileReference)
        playback.resume()
        playback.pause()
        #expect(playback.mode == .reference)

        playback.showNatural()

        #expect(playback.mode == .playing)
        #expect(playback.cycleTime == 0)
        #expect(playback.naturalPoseWeight == 0)
        var previousWeight: Float = 0
        for _ in 0..<18 {
            playback.advance(by: 0.05, isVisible: true)
            #expect(playback.naturalPoseWeight >= previousWeight)
            #expect((0...1).contains(playback.naturalPoseWeight))
            previousWeight = playback.naturalPoseWeight
        }
        #expect(playback.naturalPoseWeight == 1)
    }
}

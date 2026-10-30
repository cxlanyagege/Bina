import Foundation
import Testing
@testable import Bina

@MainActor
struct CharacterFacePlaybackTests {
    @Test func coveredStateKeepsEyesClosedAndDoesNotBlink() {
        var playback = CharacterFacePlayback(seed: 12)
        for _ in 0..<2400 {
            playback.requestBlink()
            playback.advance(by: 1.0/120, intent: .init())
            #expect(playback.sample.channels["blink"] == 1)
            #expect(playback.sample.coveringOpacity == 1)
        }
    }

    @Test func coverTransitionsAndReversalsNeverExposeOpenEyesBehindTheCover() {
        var playback = CharacterFacePlayback()
        var intent = CharacterFacePlayback.Intent()
        intent.automaticBlink = false
        for direction in [true,false,true,false,true] {
            intent.eyeState = direction ? .uncoveredOpen : .coveredClosed
            for frame in 0..<36 {
                playback.advance(by: 1.0/120, intent: intent)
                let sample = playback.sample
                if sample.coveringOpacity > 0.00001 { #expect(sample.channels["blink"] == 1) }
                if sample.channels["blink"]! < 0.99999 { #expect(sample.coveringOpacity == 0) }
                #expect(sample.channels.values.allSatisfy { (0...1).contains($0) })
                if frame == 20 { break }
            }
        }
        for _ in 0..<60 { playback.advance(by: 1.0/120, intent: intent) }
        #expect(playback.sample.coveringOpacity == 0)
        #expect(playback.sample.channels["blink"] == 0)
    }

    @Test func manualBlinkClosesAndReopensWithoutRestoringTheCover() {
        var playback = CharacterFacePlayback()
        var intent = CharacterFacePlayback.Intent(eyeState: .uncoveredOpen, automaticBlink: false)
        for _ in 0..<60 { playback.advance(by: 1.0/120, intent: intent) }
        playback.requestBlink()
        var peak: Float = 0
        for _ in 0..<40 {
            playback.advance(by: 1.0/120, intent: intent)
            peak = max(peak, playback.sample.channels["blink"]!)
            #expect(playback.sample.coveringOpacity == 0)
        }
        #expect(peak == 1)
        #expect(playback.sample.channels["blink"] == 0)
        intent.eyeState = .coveredClosed
        for _ in 0..<60 { playback.advance(by: 1.0/120, intent: intent) }
        #expect(playback.sample.coveringOpacity == 1)
        #expect(playback.sample.channels["blink"] == 1)
    }

    @Test func automaticBlinkIntervalsVaryAndRemainBounded() {
        var playback = CharacterFacePlayback(seed: 19)
        let intent = CharacterFacePlayback.Intent(eyeState: .uncoveredOpen)
        var starts: [Double] = [], wasBlinking = false
        for frame in 0..<4800 {
            playback.advance(by: 1.0/120, intent: intent)
            let blinking = playback.sample.channels["blink"]! > 0
            if frame > 60, blinking, !wasBlinking { starts.append(Double(frame)/120) }
            wasBlinking = blinking
        }
        #expect(starts.count >= 5)
        let intervals = zip(starts, starts.dropFirst()).map { $1 - $0 }
        #expect(intervals.allSatisfy { (3.2...6.6).contains($0) })
        #expect((intervals.max()! - intervals.min()!) > 0.2)
    }

    @Test func disabledAutomaticBlinkStillAllowsManualPreview() {
        var playback = CharacterFacePlayback()
        let intent = CharacterFacePlayback.Intent(eyeState: .uncoveredOpen, automaticBlink: false)
        for frame in 0..<2400 {
            playback.advance(by: 1.0/120, intent: intent)
            if frame > 60 { #expect(playback.sample.channels["blink"] == 0) }
        }
        playback.requestBlink()
        for _ in 0..<10 { playback.advance(by: 1.0/120, intent: intent) }
        #expect(playback.sample.channels["blink"] == 1)
    }

    @Test func cancellingBlinkAndResettingClearPendingEvents() {
        var playback = CharacterFacePlayback()
        let intent = CharacterFacePlayback.Intent(eyeState: .uncoveredOpen, automaticBlink: false)
        for _ in 0..<60 { playback.advance(by: 1.0/120, intent: intent) }
        playback.requestBlink()
        playback.cancelBlink()
        playback.advance(by: 1.0/120, intent: intent)
        #expect(playback.sample.channels["blink"] == 0)
        playback.reset()
        #expect(playback.sample.coveringOpacity == 1)
        #expect(playback.sample.channels["blink"] == 1)
    }

    @Test func expressionsAndMouthPosesBlendWithinTheirCalibratedRanges() {
        var playback = CharacterFacePlayback()
        var intent = CharacterFacePlayback.Intent(expression: .gentleSmile, mouthPose: .open)
        playback.advance(by: 1.0/120, intent: intent)
        #expect(playback.sample.channels["smile"]! > 0)
        #expect(playback.sample.channels["smile"]! < 0.01)
        for _ in 0..<60 { playback.advance(by: 1.0/120, intent: intent) }
        #expect(abs(playback.sample.channels["smile"]! - 0.22) < 0.00001)
        #expect(abs(playback.sample.channels["mouthOpen"]! - 0.35) < 0.00001)
        intent.expression = .curious; intent.mouthPose = .round
        for _ in 0..<60 { playback.advance(by: 1.0/120, intent: intent) }
        #expect(playback.sample.channels["smile"] == 0)
        #expect(playback.sample.channels["browRaise"] == 0.18)
        #expect(playback.sample.channels["mouthOpen"] == 0)
        #expect(playback.sample.channels["mouthRound"] == 0.35)
        intent = .init()
        for _ in 0..<60 { playback.advance(by: 1.0/120, intent: intent) }
        #expect(playback.sample.channels.filter { $0.key != "blink" }.values.allSatisfy { $0 == 0 })
    }

    @Test func invalidTimeFreezesAndLongGapsCannotSkipTheTransition() {
        var playback = CharacterFacePlayback()
        let before = playback.sample
        let intent = CharacterFacePlayback.Intent(eyeState: .uncoveredOpen)
        for time: Double in [0,-1,.nan,.infinity] { playback.advance(by: time, intent: intent); #expect(playback.sample == before) }
        playback.advance(by: 10, intent: intent)
        #expect(playback.sample.coveringOpacity > 0)
        #expect(playback.sample.channels["blink"] == 1)
    }

    @Test func blinkAndCoverSemanticsHoldAtSupportedFrameRates() {
        for fps in [30,60,90,120] {
            var playback = CharacterFacePlayback(seed: 4)
            let intent = CharacterFacePlayback.Intent(eyeState: .uncoveredOpen, automaticBlink: false)
            for _ in 0..<fps { playback.advance(by: 1/Double(fps), intent: intent) }
            #expect(playback.sample.channels["blink"] == 0)
            playback.requestBlink()
            var peak: Float = 0
            for _ in 0..<fps {
                playback.advance(by: 1/Double(fps), intent: intent)
                peak = max(peak, playback.sample.channels["blink"]!)
                #expect(playback.sample.coveringOpacity == 0)
            }
            #expect(peak == 1)
            #expect(playback.sample.channels["blink"] == 0)
        }
    }
}

import Foundation
import Testing
@testable import Bina

@MainActor struct DialogueExpressionTests {
    @Test func intentAcceptsOnlyTheBoundedVocabularyAndExactSchema() {
        for affect in DialogueAffect.allCases {
            let data = Data("{\"affect\":\"\(affect.rawValue)\",\"continuity\":\"new\"}".utf8)
            #expect(DialogueIntent.decode(data) == .init(affect: affect, continuity: .new))
        }
        for invalid in ["null", "[]", "{}", #"{"affect":"warm","continuity":"forever"}"#,
                        #"{"affect":"warm","continuity":"new","intensity":100}"#,
                        #"{"affect":"warm","continuity":"resolve"}"#] {
            #expect(DialogueIntent.decode(Data(invalid.utf8)) == nil)
        }
    }

    @Test func continuationCarriesConcernForOnlyTwoRepliesWithDecreasingStrength() throws {
        let initial = DialogueContinuity().resolve(.init(affect: .concerned, continuity: .new), at: 10)
        #expect(initial.expression == .init(affect: .concerned))
        #expect(initial.next.context(at: 11)?.remainingReplies == 2)
        let first = initial.next.resolve(.init(affect: .concerned, continuity: .continue), at: 20)
        let second = first.next.resolve(.init(affect: .concerned, continuity: .continue), at: 30)
        #expect(first.expression.strength == 0.75)
        #expect(second.expression.strength == 0.5)
        #expect(second.next.context(at: 31) == nil)
        #expect(second.next.resolve(.init(affect: .concerned, continuity: .continue), at: 40).expression == .calm)
    }

    @Test func expiryIsNotRenewedByContinuationAndTopicResolutionIsImmediate() {
        let initial = DialogueContinuity().resolve(.init(affect: .warm, continuity: .new), at: 100).next
        let continued = initial.resolve(.init(affect: .warm, continuity: .continue), at: 399).next
        #expect(continued.context(at: 399) != nil)
        #expect(continued.context(at: 400) == nil)
        #expect(initial.resolve(.init(affect: .warm, continuity: .continue), at: 400).expression == .calm)
        let resolved = initial.resolve(.init(affect: .calm, continuity: .resolve), at: 101)
        #expect(resolved.expression == .calm)
        #expect(resolved.next.context(at: 102) == nil)
        let changed = initial.resolve(.init(affect: .curious, continuity: .new), at: 102)
        #expect(changed.next.context(at: 103)?.affect == .curious)
    }

    @Test func missingMismatchedAndInvalidTimingResolveSafely() {
        let held = DialogueContinuity().resolve(.init(affect: .concerned, continuity: .new), at: 100).next
        #expect(held.resolve(nil, at: 101).expression == .calm)
        #expect(held.resolve(.init(affect: .cheerful, continuity: .continue), at: 101).expression == .calm)
        for time: Double in [.nan, .infinity, -1] {
            #expect(held.context(at: time) == nil)
            #expect(held.resolve(.init(affect: .warm, continuity: .new), at: time).expression == .calm)
        }
        for strength: Float in [-1, .nan, .infinity] {
            #expect(DialogueExpression(affect: .warm, strength: strength).strength == 0)
        }
        #expect(DialogueExpression(affect: .warm, strength: 10).strength == 1)
    }

    @Test func visualLifetimeFollowsPlaybackThenHoldsAndFades() throws {
        var envelope = DialogueExpressionEnvelope()
        #expect(envelope.sample(at: 0) == nil)
        envelope.show(.init(affect: .cheerful), at: 10, speaking: true)
        #expect(envelope.sample(at: 100)?.strength == 1)
        envelope.release(at: 100)
        #expect(envelope.sample(at: 106)?.strength == 1)
        #expect(envelope.sample(at: 109)?.strength == 0.5)
        #expect(envelope.sample(at: 112) == nil)
        envelope.show(.init(affect: .warm, strength: 0.75), at: 200)
        #expect(envelope.sample(at: 209)?.strength == 0.375)
        envelope.clear()
        #expect(envelope.sample(at: 210) == nil)
    }

    @Test func facialStrengthBlendsWithinExistingLimitsAndRejectsNonfiniteWeights() {
        var face = CharacterFacePlayback()
        let intent = CharacterFacePlayback.Intent(expression: .gentleSmile, expressionStrength: 0.5)
        face.advance(by: 1.0 / 60, intent: intent)
        let first = face.sample.channels["smile"]!
        #expect(first > 0 && first < 0.01)
        for _ in 0..<60 { face.advance(by: 1.0 / 60, intent: intent) }
        #expect(abs(face.sample.channels["smile"]! - 0.11) < 0.000001)
        let invalid = CharacterFacePlayback.Intent(expression: .gentleSmile, expressionStrength: .nan)
        for _ in 0..<60 { face.advance(by: 1.0 / 60, intent: invalid) }
        #expect(face.sample.channels["smile"] == 0)
    }
}

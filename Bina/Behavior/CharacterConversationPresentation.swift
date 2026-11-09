import Foundation

nonisolated enum CharacterConversationCue: Equatable, Sendable {
    case idle, listening, thinking, speaking
}

/// A local presentation snapshot, independent of scene entities and provider payloads.
nonisolated struct CharacterConversationPresentation: Equatable, Sendable {
    var cue = CharacterConversationCue.idle
    var mouth: Float = 0
    var expression: DialogueExpression?
}

/// Holds a reply's expression through playback, then releases it without a persistent mood.
nonisolated struct DialogueExpressionEnvelope {
    private var expression: DialogueExpression?
    private var releasedAt: TimeInterval?

    mutating func show(_ expression: DialogueExpression, at time: TimeInterval, speaking: Bool = false) {
        self.expression = expression
        releasedAt = speaking ? nil : time
    }

    mutating func release(at time: TimeInterval) { releasedAt = time }
    mutating func clear() { self = Self() }

    func sample(at time: TimeInterval) -> DialogueExpression? {
        guard let expression, time.isFinite else { return nil }
        guard let releasedAt else { return expression }
        let elapsed = max(0, time - releasedAt)
        guard elapsed < 12 else { return nil }
        let weight = Float(min(1, (12 - elapsed) / 6))
        return .init(affect: expression.affect, strength: expression.strength * weight)
    }
}

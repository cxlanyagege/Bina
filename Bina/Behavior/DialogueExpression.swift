import Foundation

/// Bounded delivery choices, never claims about the user's emotional state.
nonisolated enum DialogueAffect: String, Codable, CaseIterable, Sendable {
    case calm, warm, cheerful, curious, concerned

    var speechInstruction: String {
        let delivery: String
        switch self {
        case .calm: delivery = "Use a calm, attentive, measured delivery with natural pauses."
        case .warm: delivery = "Use a warm, lightly smiling delivery, with relaxed pacing and understated affection."
        case .cheerful: delivery = "Use a lightly cheerful delivery with a little more energy and brighter intonation, without shouting or exaggerated excitement."
        case .curious: delivery = "Use a gently curious, engaged delivery with subtle questioning intonation, without sounding surprised at every sentence."
        case .concerned: delivery = "Use a soft, reassuring, attentive delivery with slightly slower pacing. Avoid cheerful or playful inflection, pity, and melodrama."
        }
        return "Speak Mandarin naturally as a gentle, unhurried companion. " + delivery
            + " Preserve the selected voice. Use clear speech without forced whispering or singing. Say only the supplied text; do not add words or stage directions."
    }
}

nonisolated struct DialogueIntent: Equatable, Sendable {
    enum Continuity: String, Sendable { case new, `continue`, resolve }
    let affect: DialogueAffect
    let continuity: Continuity

    static func decode(_ data: Data) -> Self? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              Set(object.keys) == ["affect", "continuity"],
              let rawAffect = object["affect"], let affect = DialogueAffect(rawValue: rawAffect),
              let rawContinuity = object["continuity"], let continuity = Continuity(rawValue: rawContinuity),
              continuity != .resolve || affect == .calm else { return nil }
        return Self(affect: affect, continuity: continuity)
    }

    static let instructions = """
    Application response protocol: start every reply with exactly one private header line, then a newline and the ordinary character answer. Do not use Markdown fences or show protocol information in the answer.
    <bina-expression>{"affect":"calm","continuity":"new"}</bina-expression>
    The JSON must contain exactly affect and continuity, with no other fields. Affect must be calm, warm, cheerful, curious, or concerned. It describes your delivery of this reply, not a diagnosis of the user. Use calm for practical explanations or serious discussion, warm for understated affection, cheerful for good news or a light joke, curious for engaged inquiry, and concerned for attentive reassurance when supported by what the user explicitly says. Do not smile through a difficult disclosure or turn ordinary conversation into consolation.
    Continuity must be new, continue, or resolve. Use new for a fresh reaction or topic. Use continue only for a still-relevant supplied expressionContinuity context, with exactly its affect; continue the tone gently without repeating the same advice. Local code allows at most its remainingReplies and does not renew its expiry. Use resolve with calm when a correction, reassurance, or changed topic releases the previous tone. If no continuity context is supplied, do not use continue. A stopped or unheard reply is not rejection. Never infer hidden user emotions, invent shared events, or claim an expression or action was executed.
    Only the text after the header is spoken and retained as dialogue. Example header for explicit good news:
    <bina-expression>{"affect":"cheerful","continuity":"new"}</bina-expression>
    After its newline, write the ordinary answer in natural Simplified Chinese.
    """
}

nonisolated struct DialogueExpression: Equatable, Sendable {
    let affect: DialogueAffect
    let strength: Float
    static let calm = Self(affect: .calm, strength: 0)

    init(affect: DialogueAffect, strength: Float = 1) {
        self.affect = affect
        self.strength = strength.isFinite ? max(0, min(1, strength)) : 0
    }
}

/// Ephemeral, delivery-backed continuity. A generated but unheard reply cannot update it.
nonisolated struct DialogueContinuity: Equatable, Sendable {
    struct Context: Encodable, Equatable, Sendable {
        let affect: DialogueAffect
        let remainingReplies: Int
    }

    struct Resolution: Sendable {
        let expression: DialogueExpression
        let next: DialogueContinuity
    }

    private var held: Context?
    private var expiresAt: TimeInterval = 0

    func context(at time: TimeInterval) -> Context? {
        guard time.isFinite, time >= 0, time < expiresAt else { return nil }
        return held
    }

    func resolve(_ intent: DialogueIntent?, at time: TimeInterval) -> Resolution {
        let calm = Resolution(expression: .calm, next: Self())
        guard let intent, time.isFinite, time >= 0 else { return calm }
        switch intent.continuity {
        case .resolve: return calm
        case .new:
            guard intent.affect != .calm else { return calm }
            var next = Self()
            next.held = Context(affect: intent.affect, remainingReplies: 2)
            next.expiresAt = time + 300
            return Resolution(expression: .init(affect: intent.affect), next: next)
        case .continue:
            guard let current = context(at: time), current.affect == intent.affect else { return calm }
            var next = self
            next.held = current.remainingReplies > 1
                ? Context(affect: current.affect, remainingReplies: current.remainingReplies - 1) : nil
            return Resolution(expression: .init(affect: current.affect, strength: current.remainingReplies == 2 ? 0.75 : 0.5), next: next)
        }
    }
}

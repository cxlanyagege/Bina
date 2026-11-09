# Dialogue Expression and Short-Term Continuity

Status: implemented and verified by the complete 277-test visionOS Simulator 27.2 suite, a 41-case focused run on visionOS 27.0, and both SDK builds on 2026-11-03. Headset naturalness, actual cloud-generated prosody, and persona evaluation remain open. This increment adds dialogue-driven facial expression, coordinated vocal delivery, and bounded emotional continuity within the current conversation. It does not add episodic memory or persist emotional state.

## Ownership and Data Flow

The existing dialogue request proposes a small expression intent alongside the answer. There is no second appraisal request. `ConversationModel` validates the response, resolves the intent against local short-term continuity, and associates the result with the originating turn. `SpeechSession` coordinates its visible lifetime with actual text delivery or audio playback. The existing face writer blends the selected expression and playback-energy jaw motion; it never accepts model-authored joints, weights, eye forms, or timing.

The private first-line protocol is `<bina-expression>{"affect":"warm","continuity":"new"}</bina-expression>`, followed by a newline and the ordinary character answer. Allowed affects are `calm`, `warm`, `cheerful`, `curious`, and `concerned`. Allowed continuity decisions are `new`, `continue`, and `resolve`. `resolve` requires `calm`. The incremental decoder bounds the header to 512 bytes and leading whitespace to 32 bytes. It handles split delimiters, JSON whitespace, and LF/CRLF, and removes the header before text reaches chat, subtitles, history, memory extraction, or TTS. Plain text without a header remains usable with calm delivery. Invalid intent in a closed header uses calm delivery; an oversized, unfinished, or improperly delimited header fails without displaying protocol content.

An expression intent describes Columbina's delivery of her answer. It is not evidence of the user's hidden feelings, a saved memory, or permission to perform an action. Requests include only a small local continuity context in addition to the existing bounded dialogue and confirmed memory excerpts. The persona remains authoritative for character behavior.

## Local Continuity

A delivered `new` intent replaces the current expressive context. A matching `continue` intent can carry it across at most two subsequent delivered replies, with decreasing strength. Continuation does not renew its five-minute lifetime. A topic change or clarification can `resolve` it immediately. Missing, invalid, mismatched, or expired continuation falls back to calm. Only completed text-only replies or fully played spoken replies update continuity; interrupted generation, unheard audio, failed synthesis, and obsolete callbacks cannot commit it.

New chat, settings/context replacement, and memory mutation clear continuity. Stopping an interaction clears its visible expression and returns to the existing activity cues without interpreting interruption as rejection. Previously delivered context may still inform the next turn until its bounded expiry. State is held in memory only and is lost when the app restarts.

## Facial and Vocal Presentation

The initial mapping reuses the existing neutral, gentle-smile, and curious shapes. Warm and cheerful delivery use different restrained smile strengths. Curiosity uses a restrained brow raise. Concern uses a near-neutral face with a small brow adjustment and no forced smile; no unsupported sad-face deformation is introduced. Eye covering, open/closed eye choice, and blinking remain independent. A user control selects automatic dialogue expression or manual previews. Reference and pause remain authoritative.

Text-only expression begins after a complete reply. Spoken expression begins when playback actually starts, rather than during synthesis. After delivery it holds for six seconds and fades over six more seconds toward the neutral baseline. The existing facial clock smooths transitions and freezes them with the character. Listening and thinking cues take priority during the next interaction; the mouth still follows played PCM energy. Switching back to automatic expression does not resurrect a retained manual smile.

The same locally resolved affect selects one fixed TTS instruction: calm and measured, warm and lightly smiling, cheerful with modest energy, gently curious, or soft and reassuring. The selected preset voice and answer text are unchanged. The application forwards no free-form style metadata from the model. MiMo documents natural-language style control in a `user` message and synthesis text in an `assistant` message; this is a capability contract, not a guarantee of perceptual quality on the headset. Source: [MiMo V2.5 TTS style control](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/speech-synthesis-v2.5), checked 2026-11-03.

## Verification and Headset Acceptance

Automated checks must cover split and malformed protocol headers, strict intent validation, bounded continuation and expiry, delivery-dependent commits, context reset, obsolete-result rejection, preset/text preservation, all fixed vocal styles, facial smoothing and limits, both eye forms, manual override, interruption, and reference restoration. Run the existing spatial, mesh, physics, dialogue, memory, and voice regression suites and both SDK builds.

On the headset, compare a practical explanation, good news, a curious question, and a conversation about a difficult day. Continue the last topic for several turns, then explicitly change topics. Verify that voice and face feel compatible, concern does not produce an inappropriate smile, the transition is restrained, interruption returns to listening promptly, and both eye forms and manual preview still work. Automated protocol tests cannot establish naturalness, persona quality, or actual cloud-generated prosody.

## Automated Delivery Record

At expression delivery: Xcode 27.2 (27B52), SDK 27.2, minimum deployment target 27.0. The full suite retains all 251 preceding cases and adds 26: five decoder cases, six continuity/envelope/math cases, seven dialogue integrations, five voice integrations, one all-style request check, and two native character checks. Services use scripted/intercepted responses and synthetic audio; no paid API call or real microphone capture was made.

The user subsequently raised the minimum to 27.2 on 2026-11-03. The 27.0 run and bundled minimum values below remain historical records of the expression delivery; future routine checks use 27.2 only. See the [current platform baseline](platform-capabilities.md#local-project-baseline).

| Check | Result |
| --- | --- |
| Complete visionOS Simulator 27.2 suite | 277 passed, zero failures/skips or reported runtime warnings. `/private/tmp/Bina-Dialogue-Expression-Full.xcresult`. |
| Independent visionOS Simulator 27.0 compatibility | 41 focused cases passed, zero failures/skips or reported runtime warnings. Includes all 26 new cases, the preceding facial cases, and speech-service contracts. `/private/tmp/Bina-Dialogue-Expression-27_0.xcresult`. This is not a second full suite. |
| Simulator test build | Passed with normal ad-hoc identity. `/private/tmp/Bina-Dialogue-Expression-Final-build.log`. |
| Generic visionOS device SDK build | Passed with signing disabled. `/private/tmp/Bina-Dialogue-Expression-Device.log`. This is not a physical-device installation or run. |
| Bundled resources | All six character resources match the source in both apps. Microphone/world-sensing descriptions and minimum target 27.0 are retained. `LocalAssets/DialogueExpression/2026-11-03/resource-verification.json`. |

The standard AppIntents metadata-extraction warning remains because this app has no AppIntents dependency. It is separate from the empty runtime-warning list. Headless Simulator service messages do not establish headset visual or acoustic quality. Result summaries and Swift-source fingerprints are retained under `LocalAssets/DialogueExpression/2026-11-03/`.

# Bina

Bina includes a native macOS toolbox and a companion app for Apple Vision Pro. The visionOS app aims to create a character who appears to share the user's physical space, responds naturally, and remembers meaningful experiences across sessions.

The first character is **Columbina from Genshin Impact**, retaining her character identity and personality. Bina is the application name. A local USDZ model and paired pose data support a character preview; the original and generated character assets are excluded from the repository.

## macOS toolbox

Keep Awake provides separate controls for display sleep and idle system sleep in the main window and Control menu. Control Center can toggle Keep Display Awake directly. Application Management lets you browse local apps and inspect their version, location, and bundle identifier. See the [macOS guide](docs/macos/README.md) for installation, offline help, and development.

## visionOS project status

The spatial prototype supports mixed immersive entry, classified-floor placement with preview and confirmation, manual-height fallback, saved-world-anchor restoration, recovery, and explicit forgetting. Grounded placements use calibrated sole contact through scale and heading changes. The user reported the original placeholder's four basic feature groups working on a physical headset on 2026-10-29; this predates the character and floor increments. Build and automated-test evidence are recorded in the [verification record](docs/spatial-prototype.md#automated-verification), alongside the [device feedback](docs/spatial-prototype.md#initial-device-feedback).

The current preview implements relaxed stance, procedural idle, bounded head attention, selected hair physics, two eye states, natural blinking, restrained expressions, mouth previews, and pause/reference controls. Covered eyes remain closed; uncovered eyes blink naturally. Facial targets were repaired without re-exporting base geometry, skinning, materials, or textures. The user reported no major issue in the latest hair check and found the facial preview natural. These are preliminary passes; measured performance and broader costume checks remain open. See [Floor placement](docs/floor-placement.md), [Facial presentation](docs/facial-presentation.md), [Secondary motion](docs/secondary-motion.md), [head attention](docs/head-attention.md), and the [model intake](docs/characters/columbina-model.md).

On 2026-11-02 the user reported that the existing spatial features and new text/memory functions work on the headset. This is a preliminary functional pass; detailed floor detection/recovery, measured accuracy, structured persona evaluation, and sustained performance remain open. Environment occlusion, walking, foot IK, phoneme synchronization, and durable emotional behavior remain unimplemented. M1 is partially implemented, not complete.

The first text conversation and confirmed local-memory loop is implemented with ordinary Xiaomi MiMo pay-as-you-go API access. The default conversation tab streams Columbina's replies, supports cancellation, and provides explicit memory extraction, review, confirmation, correction, and deletion. A separate tab preserves the spatial controls. Configure the developer's own key through the settings sheet; it stays in this device's Keychain. Chat turns are ephemeral; confirmed records persist locally and relevant excerpts are sent for recall. See [Text conversation and local memory](docs/text-conversation.md).

The first [push-to-talk voice loop](docs/voice-conversation.md) adds bounded recording, editable transcript review, MiMo speech recognition and preset synthesis, character-position/window playback, subtitles, and shared cancellation. Listening/thinking cues and approximate playback-energy jaw motion preserve the selected eye form. Ordinary typed replies remain silent unless automatic reading is enabled. On 2026-11-03 the user reported that basic functionality works. This is a preliminary pass; detailed gesture, voice-quality, spatial-acoustic, latency, and recovery checks remain open.

[Dialogue expression](docs/dialogue-expression.md) now connects completed replies to restrained facial expression and a matching fixed vocal style. Local short-term continuity carries a delivered tone across at most two follow-up replies, expires after five minutes, and can resolve with a topic change. It does not persist emotions or infer the user's hidden feelings. Automatic expression is enabled by default; the face controls retain a manual override. This increment needs its own headset evaluation.

The current visionOS Simulator 27.2 suite passes all 277 tests with zero failures/skips or reported runtime warnings, retaining the preceding 251 cases and adding 26 expression/continuity cases. Simulator and generic device SDK builds pass. See the [expression verification record](docs/dialogue-expression.md#automated-delivery-record) and preceding [voice record](docs/voice-conversation.md#automated-delivery-record). The prior [footwear correction](docs/footwear-mesh-investigation.md) removes runtime reconstruction of the imported mesh and retains fixed stances/contact measurements for both forms. Spatial, text/memory, and basic voice behavior have preliminary user-reported passes; the new dialogue-expression increment needs independent device evaluation. Simulator results do not establish real-room floor accuracy, acoustic quality, or expressive naturalness.

The current toolchain is Xcode 27.2 with SDK and Simulator 27.2, matching the user-reported headset version. On 2026-11-03 the user selected visionOS 27.2 as the minimum deployment target for this personal-use project. Debug, Release, the app, and tests share that minimum. Routine build and runtime verification now use 27.2 only; earlier 27.0 results remain historical evidence.

The app currently supports Simplified Chinese only, with `zh-Hans` as the development language.

## Documentation

Start with the [documentation guide](docs/README.md). The main documents are:

- [Spatial prototype](docs/spatial-prototype.md): run instructions, controls, persistence behavior, and device checklist.
- [Floor placement](docs/floor-placement.md): classified-floor evidence, landing preview, sole calibration, fallback, and device checks.
- [Footwear and sole contact](docs/footwear.md): water heels, calibrated barefoot stance, preview lifecycle, and matching ground contact.
- [Head attention](docs/head-attention.md): bounded head/neck turns, target validity, preview controls, and verification.
- [Product vision](docs/product-vision.md): confirmed goals, first experience, and scope.
- [Columbina character profile](docs/characters/columbina.md): source-derived personality, relationship premise, and adaptation boundaries.
- [Platform capabilities](docs/platform-capabilities.md): verified Apple API boundaries and research options.
- [Character assets](docs/character-assets.md): model intake, rigging, expressions, materials, and validation.
- [Columbina model intake](docs/characters/columbina-model.md): local source, conversion, attribution, and asset-use boundaries.
- [Memory and emotion](docs/memory-and-emotion.md): character continuity, shared memories, and emotional behavior.
- [Text conversation and local memory](docs/text-conversation.md): API setup, streaming, confirmed facts, privacy, failure behavior, and verification.
- [Push-to-talk conversation](docs/voice-conversation.md): microphone controls, transcript review, voice audition, playback, interruption, and device acceptance.
- [Dialogue expression](docs/dialogue-expression.md): validated delivery intent, facial and vocal coordination, short-term continuity, and acceptance scenarios.
- [Architecture](docs/architecture.md): responsibilities, data flow, and execution contracts.
- [Milestones](docs/milestones.md): experiments, acceptance criteria, and open decisions.

The supplied OpenClaw identity and personality files have been reviewed and adapted into character documentation and a versioned text-runtime persona. The original files are not imported as executable instructions, and their game lore has not been independently verified.

## Local character preview

The runtime asset must exist at `Bina/Resources/Characters/Columbina.usdz` before building a character-enabled preview. Natural stance/idle require `ColumbinaIdlePose.json`; hair physics requires `ColumbinaPhysics.json`, and facial controls require `ColumbinaFace.json`. Foot-form selection additionally requires `ColumbinaBarefoot.usdc` and `ColumbinaFootwear.json`; follow the [footwear preparation](docs/footwear.md#reproduce-the-native-variant). The derived layer references the original USDZ without copying its textures. All six generated resources are intentionally ignored by Git and must be paired to the exact model. A clone without the model keeps the placeholder and offers a retry. Invalid pose data retains the static model; invalid physics, face, or footwear data retains primary motion and reports that feature as unavailable. See the [model intake](docs/characters/columbina-model.md), [physics preparation](docs/secondary-motion.md#reproduce-the-local-profile), and [facial repair instructions](docs/facial-presentation.md#reproduce-the-local-repair). The repository's software license does not cover these character assets; do not redistribute them.

Development proceeds through focused device experiments. The first complete product milestone combines spatial presence, interruptible conversation, one prepared physical object, and a confirmed memory restored across sessions.

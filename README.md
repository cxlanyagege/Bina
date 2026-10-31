# Bina

Bina is a long-term visionOS companion project for Apple Vision Pro. Its goal is to create a character who appears to share the user's physical space, responds naturally, and remembers meaningful experiences across sessions.

The first character is **Columbina from Genshin Impact**, retaining her character identity and personality. Bina is the application name. A local USDZ model and paired pose data support a character preview; the original and generated character assets are excluded from the repository.

## Project status

The spatial prototype supports mixed immersive entry, classified-floor placement with preview and confirmation, manual-height fallback, saved-world-anchor restoration, recovery, and explicit forgetting. Grounded placements use calibrated sole contact through scale and heading changes. The user reported the original placeholder's four basic feature groups working on a physical headset on 2026-10-29; this predates the character and floor increments. Build and automated-test evidence are recorded in the [verification record](docs/spatial-prototype.md#automated-verification), alongside the [device feedback](docs/spatial-prototype.md#initial-device-feedback).

The current preview implements relaxed stance, procedural idle, bounded head attention, selected hair physics, two eye states, natural blinking, restrained expressions, mouth previews, and pause/reference controls. Covered eyes remain closed; uncovered eyes blink naturally. Facial targets were repaired without re-exporting base geometry, skinning, materials, or textures. The user reported no major issue in the latest hair check and found the facial preview natural. These are preliminary passes; measured performance and broader costume checks remain open. See [Floor placement](docs/floor-placement.md), [Facial presentation](docs/facial-presentation.md), [Secondary motion](docs/secondary-motion.md), [head attention](docs/head-attention.md), and the [model intake](docs/characters/columbina-model.md).

The latest foot-form/contact presentation has a preliminary user-reported headset pass. Detailed floor detection/recovery, measured accuracy, and sustained performance remain open. Environment occlusion, walking, foot IK, speech synchronization, voice, conversation, personal memory, and emotional behavior remain unimplemented. Facial labels are manual previews. M1 is partially implemented, not complete.

The current full suite passes 151 tests on visionOS Simulator 27.2, and the device SDK build passes. Water-heel/barefoot selection uses fixed stances and separate contact measurements; see [Footwear and sole contact](docs/footwear.md) and the [verification record](docs/spatial-prototype.md#footwear-verification). Simulator results do not establish real-room floor accuracy.

The current toolchain is Xcode 27.2 with SDK and Simulator 27.2, matching the user-reported headset version. The Xcode project keeps its visionOS 27.0 minimum deployment target.

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
- [Architecture](docs/architecture.md): responsibilities, data flow, and execution contracts.
- [Milestones](docs/milestones.md): experiments, acceptance criteria, and open decisions.

The supplied OpenClaw identity and personality files have been reviewed and adapted into character documentation. The adaptation is a design draft; it is not a runtime import or an independent verification of game lore.

## Local character preview

The runtime asset must exist at `Bina/Resources/Characters/Columbina.usdz` before building a character-enabled preview. Natural stance/idle require `ColumbinaIdlePose.json`; hair physics requires `ColumbinaPhysics.json`, and facial controls require `ColumbinaFace.json`. All four generated resources are intentionally ignored by Git and must be paired to the exact model. A clone without the model keeps the placeholder and offers a retry. Invalid pose data retains the static model; invalid physics or face data retains primary motion and reports that feature as unavailable. See the [model intake](docs/characters/columbina-model.md), [physics preparation](docs/secondary-motion.md#reproduce-the-local-profile), and [facial repair instructions](docs/facial-presentation.md#reproduce-the-local-repair). The repository's software license does not cover these character assets; do not redistribute them.

Development proceeds through focused device experiments. The first complete product milestone combines spatial presence, interruptible conversation, one prepared physical object, and a confirmed memory restored across sessions.

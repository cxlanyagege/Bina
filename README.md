# Bina

Bina is a long-term visionOS companion project for Apple Vision Pro. Its goal is to create a character who appears to share the user's physical space, responds naturally, and remembers meaningful experiences across sessions.

The first character is **Columbina from Genshin Impact**, retaining her character identity and personality. Bina is the application name. A local USDZ model and paired pose data support a character preview; the original and generated character assets are excluded from the repository.

## Project status

The spatial prototype supports mixed immersive entry, manual character placement, saved-world-anchor restoration, recovery, and explicit forgetting. The user reported the original placeholder's four basic feature groups working on a physical headset on 2026-10-29; this predates the character integration. Build and automated-test evidence are recorded in the [verification record](docs/spatial-prototype.md#automated-verification), alongside the [device feedback](docs/spatial-prototype.md#initial-device-feedback).

The current preview implements relaxed stance, procedural idle, bounded head attention, selected hair physics, and pause/reference controls. After the user's hair/collar defect report, four hair chains now have damped spring motion and body/collar collision proxies. Physics and debug toggles support comparison, and a timing button records recent CPU costs. All 90 simulator tests pass, including actual skinned hair/collar and cuff regressions. This is a selected-region correction awaiting headset quality/performance acceptance, not full-garment cloth simulation. The original model and pose data remain unchanged. See [Secondary motion](docs/secondary-motion.md), [head attention](docs/head-attention.md), and the [model intake](docs/characters/columbina-model.md).

Automatic ground detection, environment occlusion, facial animation, voice, conversation, personal memory, and emotional behavior remain unimplemented. M1 is partially implemented, not complete.

The current Xcode project has a visionOS 27.0 minimum deployment target.

## Documentation

Start with the [documentation guide](docs/README.md). The main documents are:

- [Spatial prototype](docs/spatial-prototype.md): run instructions, controls, persistence behavior, and device checklist.
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

The runtime asset must exist at `Bina/Resources/Characters/Columbina.usdz` before building a character-enabled preview. Natural stance/idle require `ColumbinaIdlePose.json`; selected hair physics also requires the asset-paired `ColumbinaPhysics.json`. All three generated character resources are intentionally ignored by Git. A clone without the model keeps the placeholder and offers a retry. Invalid pose data retains the static model; invalid physics data retains primary stance/idle/attention and reports physics as unavailable. See the [model intake](docs/characters/columbina-model.md) and [physics preparation instructions](docs/secondary-motion.md#reproduce-the-local-profile). The repository's software license does not cover these character assets; do not redistribute them.

Development proceeds through focused device experiments. The first complete product milestone combines spatial presence, interruptible conversation, one prepared physical object, and a confirmed memory restored across sessions.

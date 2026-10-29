# Bina

Bina is a long-term visionOS companion project for Apple Vision Pro. Its goal is to create a character who appears to share the user's physical space, responds naturally, and remembers meaningful experiences across sessions.

The first character is **Columbina from Genshin Impact**, retaining her character identity and personality. Bina is the application name. A local model has been converted to USDZ for a static character preview; its source and converted asset are excluded from the repository.

## Project status

The spatial prototype supports mixed immersive entry, manual character placement, saved-world-anchor restoration, recovery, and explicit forgetting. Current Device and Simulator SDK builds pass, and 39 automated tests pass on visionOS Simulator 27.0. The user reported the original placeholder's four basic feature groups working on a physical headset on 2026-10-29; this predates the character integration. See the [device feedback](docs/spatial-prototype.md#initial-device-feedback) and [verification record](docs/spatial-prototype.md#automated-verification).

The current increment replaces the placeholder with the locally converted Columbina asset after asynchronous loading. Headset testing identified angle-dependent eye rendering and missing clothing backfaces. The corrected export and runtime material policy pass USDZ validation, regression tests, and macOS RealityKit comparisons. On 2026-10-30 the user reported no obvious remaining visual issues in a preliminary headset inspection. Motion validation and sustained performance remain open; see the [model intake](docs/characters/columbina-model.md).

Automatic ground detection, environment occlusion, idle animation, voice, conversation, personal memory, and emotional behavior remain unimplemented. M1 is partially implemented, not complete.

The current Xcode project has a visionOS 27.0 minimum deployment target.

## Documentation

Start with the [documentation guide](docs/README.md). The main documents are:

- [Spatial prototype](docs/spatial-prototype.md): run instructions, controls, persistence behavior, and device checklist.
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

The runtime asset must exist at `Bina/Resources/Characters/Columbina.usdz` before building a character-enabled preview. It is present in this working checkout but intentionally ignored by Git. A fresh clone does not include it: the app keeps the placeholder, reports the missing model, and offers a retry. See the [model intake and conversion instructions](docs/characters/columbina-model.md) for local preparation. The repository's software license does not cover the character asset; do not redistribute the original or converted model.

Development proceeds through focused device experiments. The first complete product milestone combines spatial presence, interruptible conversation, one prepared physical object, and a confirmed memory restored across sessions.

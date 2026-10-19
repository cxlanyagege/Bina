# Bina

Bina is a long-term visionOS companion project for Apple Vision Pro. Its goal is to create a character who appears to share the user's physical space, responds naturally, and remembers meaningful experiences across sessions.

The first character is **Columbina from Genshin Impact**, retaining her character identity and personality. Bina is the application name. A suitable model has not yet been obtained or validated.

## Project status

The repository currently contains an unmodified visionOS starter application and a planning baseline. Character rendering, spatial sensing, conversation, memory, and emotional behavior are not implemented.

The current Xcode project has a visionOS 27.0 minimum deployment target. The user has an Apple Vision Pro available for device testing; its installed system version still needs to be recorded.

## Documentation

Start with the [documentation guide](docs/README.md). The main documents are:

- [Product vision](docs/product-vision.md): confirmed goals, first experience, and scope.
- [Columbina character profile](docs/characters/columbina.md): source-derived personality, relationship premise, and adaptation boundaries.
- [Platform capabilities](docs/platform-capabilities.md): verified Apple API boundaries and research options.
- [Character assets](docs/character-assets.md): model intake, rigging, expressions, materials, and validation.
- [Memory and emotion](docs/memory-and-emotion.md): character continuity, shared memories, and emotional behavior.
- [Architecture](docs/architecture.md): responsibilities, data flow, and execution contracts.
- [Milestones](docs/milestones.md): experiments, acceptance criteria, and open decisions.

The supplied OpenClaw identity and personality files have been reviewed and adapted into character documentation. The adaptation is a design draft; it is not a runtime import or an independent verification of game lore.

Development begins with documentation and focused device experiments. The first product milestone combines spatial presence, interruptible conversation, one prepared physical object, and a confirmed memory restored across sessions.

## Development conventions

Keep developer-facing documentation and code comments in English. Prefer focused changes, clear interfaces, observable behavior, and verification appropriate to each change. Never commit service credentials or private conversation records.

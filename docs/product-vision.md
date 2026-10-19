# Product Vision

Status: confirmed product direction with proposed first-release scope. Last updated: 2026-10-19.

## Purpose

Bina is a companion and interaction experience for Apple Vision Pro. The character should feel present in the user's physical surroundings, respond as a coherent individual, and develop continuity through remembered shared experiences.

Believability depends on spatial stability, response timing, personality, expressive behavior, and memory working together. Visual detail alone is insufficient.

## Confirmed direction

- Companionship and interaction are the primary purposes.
- The first character is Columbina from Genshin Impact. Her original identity and personality should be retained, rather than using only her appearance for a new persona.
- Bina is the application name; character identity and application identity are distinct.
- Remembering past events and expressing humanlike emotion are central product requirements.
- The initial experience should include spatial presence, interruptible conversation, one prepared real-world object, and continuity across launches.
- An Apple Vision Pro is available for on-device experiments.
- The user's OpenClaw `IDENTITY.md` and `SOUL.md` have been supplied and reviewed. Their adaptation is recorded in the [Columbina character profile](characters/columbina.md); runtime integration is not implemented.
- Engineering documents precede feature implementation. Developer-facing documentation is in English.

## First complete experience

1. The user opens Bina and enters a mixed immersive experience while retaining a view of the real room.
2. The character appears at a user-confirmed, credible location. When an earlier anchor is unavailable, Bina offers placement rather than assuming a valid position.
3. The character turns toward the user and responds through coordinated speech, expression, and a small set of motions.
4. The user can interrupt speech. Playback, pending response work, and related speaking behavior stop or transition together.
5. The character can refer to and point toward one prepared physical object whose position is currently known.
6. The user explicitly confirms one personal preference for persistent memory. Richer shared-event storage follows after the initial persistence path is reliable.
7. On a later launch in the same location, Bina attempts to restore placement and recalls the confirmed memory when relevant. The character acknowledges missing spatial information or uncertain recollection.

This is the first complete product milestone, not the first code change. Earlier experiments can use a placeholder model, scripted dialogue, or manual placement to isolate uncertainty.

## Believability requirements

| Dimension | Intended observable behavior |
| --- | --- |
| Presence | The character stays in a credible place and reacts appropriately when tracking is lost. |
| Attention | Head orientation, explicit input, and conversation guide attention without claiming access to private gaze data. |
| Conversation | Responses acknowledge the user's latest turn; interruptions do not leave stale speech playing. |
| Personality | Wording, choices, emotional expression, and gestures follow the curated Columbina character profile. |
| Memory | Shared events are recalled from evidence, corrected when necessary, and distinguished from fictional background. |
| Emotion | Affect carries across turns and changes for understandable reasons rather than resetting with each model response. |
| Agency | Intentions lead to executable actions and observable outcomes. Failed actions are acknowledged. |

The character's fictional background, configured relationship premise, and actual interaction history with the user must remain distinguishable. The supplied persona starts from a close family and travel-companion relationship. This explicit premise permits familiarity from the first session, but does not establish specific previous conversations, outings, or promises.

Source-derived dialogue default: Simplified Chinese with gentle, clear, unhurried speech and a wider emotional range than constant serenity. The user-authored profile preserves curiosity, playfulness, vulnerability, and independent judgment. These details are available for review; game lore has not been independently verified.

## Initial scope

Proposed baseline: one local user, one room at a time, one active character, user-started sessions, a small action vocabulary, and one prepared reference object. Persistent memory should start locally unless a later decision establishes a concrete need for remote storage.

The production baseline must remain useful without enterprise camera approval. Broader sensing can be researched behind a separate capability path.

The first release does not require autonomous room-scale walking, arbitrary object understanding, physical manipulation, whole-system background presence, multi-user synchronization, or a large catalog of characters.

## Open product decisions

- Does the [source-derived character profile](characters/columbina.md) faithfully preserve the intended portrayal, timeline, and initial relationship? Which lore details require independent source review?
- What is the initial character scale and preferred interaction distance?
- What voice and delivery best express the source-derived Simplified Chinese dialogue style?
- What degree of proactive interaction feels appropriate, and under what observable conditions?
- Is the near-term distribution goal a personal prototype or a broader consumer application?

These choices should be resolved when they affect the next milestone. They do not justify delaying independent documentation or technical experiments.

## Related documents

See [memory and emotion](memory-and-emotion.md) for continuity, [character assets](character-assets.md) for visual embodiment, and [milestones](milestones.md) for acceptance evidence.

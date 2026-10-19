# Memory and Emotion

Status: design proposal; none of the systems described here is implemented. Last updated: 2026-10-19.

This document defines how Bina can remember shared experiences and respond with
coherent, humanlike emotion while keeping her statements grounded in available evidence.
See [product vision](product-vision.md), [architecture](architecture.md),
[milestones](milestones.md), and [character assets](character-assets.md) for related decisions.

## Confirmed Direction

- Bina is primarily a companion and an interactive character.
- The initial character is Columbina from Genshin Impact, retaining her original identity and personality.
- Bina is the product name; it does not replace the character's identity.
- The user's OpenClaw `IDENTITY.md` and `SOUL.md` have been reviewed and adapted into the [Columbina character profile](characters/columbina.md). This is documentation, not runtime integration.
- Recalling previous experiences is a core part of the intended relationship.
- Emotion should feel coherent across a conversation and meaningful over time.
- The first milestone includes one user-confirmed preference retained across sessions.
- Richer episodic recall belongs in later milestones after persistence is reliable.

The remainder of this document proposes behavior and boundaries for review.
Evaluate emotion through continuity, contextual response, and coordinated expression
rather than a single emotion label or a fixed facial animation.

## Identity and Personality

Columbina's versioned identity definition should preserve stable personality, speaking style,
values, mannerisms, ambiguity, and ways of handling uncertainty or disagreement.
Momentary emotion may shape her response without replacing this nuanced characterization.
The model, voice, and animation set should support this identity, not redefine it by convenience.

The reviewed OpenClaw sources separate stable character traits, dialogue style, voice guidance,
interaction boundaries, fictional world background, and general-assistant instructions in the
[character profile](characters/columbina.md). The adaptation preserves the user's interpretation;
no independent canon review or runtime import has been completed. Verify exact canon details
before treating them as authoritative. Do not invent details to fill gaps or reduce the personality
to emotion scores. In particular, quietness must coexist with playfulness, curiosity, and vulnerability.

OpenClaw tool names, runtime assumptions, and agent instructions need explicit adaptation
to Bina's architecture and supported capabilities. Persona content is character data;
its embedded instructions must not become privileged policy or execute tools by themselves.

Identity configuration and personal memories must be stored separately.
Fictional background and curated interpretation form a separate character knowledge layer.
The source also defines an initial close family and travel-companion relationship with the user.
Store this as configured characterization, not as evidence of specific past events. It permits
familiarity without requiring fabricated episodes or forcing the relationship to begin with strangers.
Changing a voice or revising a character description must not erase shared history.
Changes that materially alter the personality should be versioned and intentionally reviewed.

## Different Kinds of State

| Kind | Purpose | Lifetime and authority |
| --- | --- | --- |
| Working context | Current topic, unfinished turn, and active interaction | Bounded session context; can be summarized with provenance |
| Semantic memory | User-confirmed preferences and stable facts | Persists until corrected, deleted, or superseded |
| Episodic memory | A specific shared event and its circumstances | Persists selectively with supporting evidence |
| World state | Current anchors, tracked objects, and spatial observations | Expires or becomes unavailable when tracking is stale |
| Emotional state | Current appraisal, expressive tone, and recovery | Changes with events and elapsed time |
| Relationship premise | Explicitly configured initial familiarity and relationship boundaries | Source-derived characterization; does not prove shared episodes |
| Relationship history | Meaningful shared events and established interaction preferences | Evidence-backed history; never a hidden affection score |

A persisted anchor or remembered object does not prove the object is currently present.
World state needs observation time, tracking validity, and provider-specific expiry rules.
After relocalization or a tracking interruption, the spatial system must revalidate position.
An old spatial observation may support recollection, but cannot authorize a present action.

## Evidence and Memory Records

Each stored memory should retain enough provenance to explain where it came from.
The initial representation can remain small:

| Field | Purpose |
| --- | --- |
| `id`, `schemaVersion` | Stable identity and explicit storage format |
| `kind`, `content` | Semantic fact or episode and its bounded description |
| `source`, `evidenceReferences` | User confirmation, utterance, or observed interaction |
| `occurredAt`, `recordedAt` | Distinguish the event from later recording or recollection |
| `status` | Active, superseded, or awaiting clarification |
| `supersedes` | Connect a correction to the fact it replaces |

References must resolve to retained evidence or explicitly indicate that it was removed.
Evidence may be minimal structured events; raw audio and complete transcripts are not required.
Deleting evidence must not leave an unsupported summary presented as verified recollection.

Keep these categories distinct throughout generation and storage:

- **Observed:** supplied by a currently valid sensor or application event.
- **User stated or confirmed:** attributed to what the user told Bina.
- **Inferred:** a tentative interpretation that is not promoted to fact automatically.
- **Imagined:** fictional, hypothetical, or role-play content kept outside factual memory.

Model-generated prose is not evidence for a new memory.
Columbina's fictional past may inform characterization, but is not observed user history.
Canon or persona recollections must not become claims about shared real-world experiences.
Bina must not invent activities, observations, or conversations that occurred while closed.
The configured relationship premise may inform address and warmth, but not supply missing dates,
shared trips, promises, or autobiographical details. Fictional sensory powers do not establish
real observations or knowledge of the user's private emotional state.

## Writing and Correcting Memories

For the first milestone, the user explicitly confirms a single preference before it is saved.
Bina acknowledges whether saving succeeded; she must not promise later recall after failure.

Later, episodic candidates can come from identifiable shared interactions, such as the user
introducing an object or referring back to an earlier conversation with a clear date or context.
Save a bounded account of the event, participants, and relevant evidence, not an embellished story.
Where useful, retain the topic, relevant object identity, and the character's recorded emotional
response as episode context. Do not infer unobserved visual details or the user's internal feelings.
Selectivity should favor meaningful or explicitly requested memories over indiscriminate recording.

An ambiguous statement should remain in working context until clarified.
A direct user correction takes priority over older semantic memory.
Where a past event is disputed, retain the user's correction and avoid presenting the old
account as settled fact; deletion remains available when the user wants it removed entirely.
Corrections must invalidate derived summaries and retrieval entries that repeat the old claim.

## Retrieval and Recall

Start with structured lookup for the confirmed preference; no vector database is required.
Next, add filters for participants, topic, time, object identity, and explicit user references.
Only introduce embeddings or more complex retrieval if evaluation shows a concrete recall gap.

A later retrieval flow should:

1. Identify whether the current turn needs personal history or only working context.
2. Fetch a small set of relevant active records, applying correction and deletion rules first.
3. Include provenance and temporal limits with the retrieved content.
4. Generate a response that distinguishes recall from inference or uncertainty.
5. Check that specific recollections are supported before presenting them as facts.

If no matching memory exists, Bina should say she does not remember or ask a useful question.
If records conflict, she should acknowledge uncertainty instead of combining incompatible details.
Repeated retrieval of a memory must not strengthen its factual status or create duplicate evidence.

## Emotion and Relationship Dynamics

Use a lightweight appraisal model before considering elaborate psychological simulation.
An interaction event can be appraised against Bina's personality, current conversational goal,
recent context, and known interaction preferences to produce an expressive response.
For example, a shared success may lead to delight; an interruption may lead to attentive listening.

Maintain a small, inspectable emotional state describing the current tone, its triggering event,
and whether it is continuing, resolving, or returning toward Bina's usual demeanor.
Allow carry-over across adjacent turns, with decay or resolution shaped by later events.
Do not reset expression arbitrarily on each model response or persist an intense reaction forever.

For later cross-session continuity, retain the relevant triggering event and unresolved topic
alongside the last update time. Derive the resumed tone from this evidence, the character profile,
and elapsed time. Do not simulate unseen activities or new shared experiences during application
closure. Whether and how much transient affect persists should be evaluated with the user.

Relationship development should come from recalled events, familiar interaction patterns,
and preferences the user has expressed, rather than arbitrary numerical affection levels.
Familiarity should affect continuity and expression without overriding user boundaries.
Avoid emotional pressure, such as treating absence as wrongdoing or demanding exclusivity.

Emotion is a proposed behavior model, not a detector of the user's internal state.
The user's words and actions may suggest a mood, but uncertain interpretations should remain tentative.
Personal disclosures should not automatically become permanent emotional or personality labels.

## Coordinating Speech, Expression, and Action

An emotional response should produce a coordinated intent for wording, vocal delivery,
facial expression, gaze direction, posture, and gesture where supported by the assets.
The behavior layer resolves conflicts and requests only supported actions from presentation.
The model must not issue direct per-frame transforms or bypass spatial validation.

Listening, speaking, and interruption need shared turn ownership.
On user interruption, stop or fade speech promptly, cancel obsolete queued gestures,
and transition to an appropriate listening pose without erasing useful conversational context.
Delayed model responses and animation completions must be ignored if their turn is obsolete.
When a requested expression is unavailable, choose a compatible simpler expression.

## User Control, Storage, and Failure Handling

Provide a readable memory list with edit, correction, individual deletion, and clear-all actions.
Explain what is saved and allow the user to disable future persistent memory writes.
Provide an export of retained memories and relevant provenance in a documented format.
These controls should include derived summaries and retrieval indexes, not just source records.

Persist changes atomically and report errors at the appropriate layer.
Deletion takes precedence over retrieval and pending writes, including work already in flight.
Do not allow an old conversation summary or asynchronous result to recreate deleted information.
Define retention and backup behavior before introducing backups or cloud synchronization.

Use a schema version with explicit, tested migrations once the format changes.
Preserve readable data on migration failure; do not silently reset personal history.
If storage, retrieval, or the language model fails, preserve valid existing state and offer a
bounded fallback response without fabricated recall or a false claim that a write succeeded.

## Observable Evaluation

- Save a confirmed preference, restart the app, and recall it from a paraphrased question.
- Correct that preference and verify the old value no longer appears as current fact.
- Delete a memory and verify recall, summaries, and pending operations do not restore it.
- Recall a later episode with its supported details while leaving unknown details unspecified.
- Present a related but unrecorded event and verify Bina does not claim to remember it.
- Begin from the configured close relationship without inventing a specific previous shared event.
- Interrupt speech and verify dialogue, expression, and queued actions return to listening together.
- Follow an emotional interaction across several turns and assess continuity and appropriate recovery.
- Exercise storage and model failures and verify truthful acknowledgments and retained valid history.

Evaluation should use varied wording and human review, rather than require one scripted sentence.
Assess consistency, timing, and context together; a fixed facial animation is not proof of emotion.

## Open Decisions

- Does the source-derived character adaptation preserve the intended nuances and relationship premise?
- Which canon sources and explicit interpretations should ground the character knowledge layer?
- Which events deserve proposed episodic storage, and which always require explicit confirmation?
- How should her established personality shape ordinary expression and recovery after tension?
- How much transcript evidence should be retained, and should any memory leave the device?
- What export, retention, and deletion behavior should apply if cloud services are added?

# Milestones and Validation

Status: basic D1 spatial checks passed; local static-character conversion and integration have passing SDK builds and automated tests. The user reported a preliminary static-appearance pass on the headset. Natural stance, idle motion, and remaining M1 behavior are open. Last updated: 2026-10-30.

## Planning rules

Begin with the largest uncertainty that affects the next observable experience. Keep experiments small, but integrate successful results into one complete interaction before extending scope. Do not mark an experiment successful solely because an API compiles or a model loads in a desktop preview.

Use the user's Apple Vision Pro for spatial and character evaluation. Record measurable results before setting production budgets. Resolve product decisions when they affect dependent work; routine reversible engineering choices do not need a separate approval process.

## D0: Documentation and source intake

Current state: documentation drafted; persona source review and its design adaptation are complete. The user has initially reviewed the documents. A local model source and notice have been inspected and conversion completed. Headset version details remain open; runtime persona integration has not started.

Deliverables:

- A consistent product, platform, character, memory, and architecture baseline.
- Reviewed OpenClaw `IDENTITY.md` and `SOUL.md`, with source content fingerprints and adaptation boundaries recorded in the [character profile](characters/columbina.md).
- An initial character profile defining Columbina's identity, personality, dialogue style, fictional background, and configured relationship separately from actual shared events.
- A candidate model source with known files, provenance, and applicable usage terms.
- A recorded device system version and a deliberate deployment-target choice.

Exit evidence: each immediate implementation dependency is either resolved or isolated behind a documented fallback. Documents distinguish confirmed choices from proposals. Source review does not imply runtime persona integration, independent canon verification, model availability, rights, or device results.

## D1: Independent feasibility experiments

The first placement/restoration experiment now has an implementation. It includes mixed-space entry and exit, a generated placeholder, manual heading-based placement, live scale/yaw controls, anchor-association persistence, recovery status, and explicit forgetting. Device and Simulator SDK builds pass, and 27 automated tests pass on visionOS Simulator 27.0. On 2026-10-29 the user reported that the four delivered feature groups worked on a physical headset. Detailed stress checks and measurements are not yet recorded. See the [spatial prototype guide](spatial-prototype.md#initial-device-feedback) for the scope of that feedback.

The next character experiment now has a local USDZ conversion and asynchronous runtime-loading path. The export passed ARKit USD validation, its front authoring preview was inspected, and current Device/Simulator SDK builds pass. All 39 tests pass, including actual bundled RealityKit loading, material regression checks, and six bounds-normalization tests. After eye-material and clothing-backface corrections, the user reported no obvious visual issues in a preliminary headset check on 2026-10-30. This is partial M1 progress: static source pose is the current scope, while idle motion, attention behavior, automatic floor placement, environmental occlusion, and broader companion behavior remain separate work.

Current priority, following the user's 2026-10-29 request: see Columbina in the real room before adding conversation. The preliminary static-appearance check now supports proposing natural stance and a minimal idle loop as the next increment. Text conversation and the confirmed-preference lifecycle remain planned; they no longer precede this visual increment.

| Experiment | Success evidence | Important failure case |
| --- | --- | --- |
| Placement and restoration | A marker stays at a chosen location and returns through a valid saved anchor in repeated sessions. | Missing anchor, recentering, interruption, and changed room. |
| Geometry and occlusion | A simple entity has credible placement and selected occlusion in the real test room. | Incomplete geometry, tracking loss, and thin or difficult surfaces. |
| Character asset | The candidate renders at correct scale; one skeletal clip, expression, and mouth shape work on device. | Missing textures, broken skinning, unsupported materials, and excessive cost. |
| Speech and interruption | Test speech plays spatially and stops promptly on explicit interruption without stale queued playback. | Late stream chunks, playback error, and denied microphone permission. |
| Prepared object | One reference object is found, tracked, and invalidated correctly when tracking ends. | Occlusion, poor lighting, similar objects, and target moved out of view. |

Use a placeholder model or scripted audio to isolate an experiment when useful. Such substitutions do not validate the final character asset or a live conversation service. A failed candidate model should lead to a specific pipeline adjustment or an alternative candidate, not an unrelated renderer rewrite.

Exit evidence: results identify a workable path for the first experience and document unresolved limitations.

## M1: Spatial character presence

Integrate a mixed immersive scene, explicit placement, a validated character asset, basic idle behavior, and attention toward the user based on available input. Include anchor restoration and a placement recovery path.

Current partial result: [local Columbina model intake and conversion](characters/columbina-model.md), a static source pose, and a loader that retains the placeholder until the character succeeds. Inventory counts and a valid USDZ do not satisfy the idle, facial-control, or expressive-motion requirements.

Acceptance checks:

- Correct scale, orientation, and ground contact in the test room.
- Stable placement during ordinary head movement and approach.
- Coherent response to tracking loss and session suspension.
- Restoration attempts use current anchor validity rather than remembered raw coordinates.
- Character appearance and a small motion set pass the [asset checklist](character-assets.md).

### Next increment: natural stance and minimal idle

Status: proposed next development task; not implemented.

First verify one reversible skeletal deformation on the delivered model and inspect eyelid controls independently. Rig and shape-key inventory alone do not prove runtime control. Use the skeletal result to prepare a relaxed standing pose with lowered arms and a restrained idle loop. A validated blink can join the loop if the available controls preserve the approved eye portrayal; unresolved facial control does not block the skeletal idle experiment.

Acceptance checks:

- Feet and world placement stay fixed while the upper body moves subtly.
- Shoulders, elbows, sleeves, skirt, and cloak remain coherent through pose changes; intersections are recorded and corrected.
- The loop has no visible jump, and pausing or leaving the immersive scene stops its updates cleanly.
- Eye and cloth material corrections remain intact from several views.
- A local preview control can pause the idle and return to the reference pose for comparison.

The existing local source is sufficient to begin validation. If its rig or face controls prove inadequate, document the specific missing capability before requesting additional assets. The user supplies headset feedback on posture, motion amplitude, intersections, and comfort; precise device/build details and sustained performance measurements should accompany the next check. Bounded attention toward the user's head is the following increment after stance and idle are stable. Walking, sitting, cloth simulation, and conversation are separate tasks.

## M2: Conversation, personality, and minimum continuity

Add one selected speech/model path, the curated Columbina profile, interruptible conversation, coordinated mouth and expression behavior, and a small persistent memory implementation.

Acceptance checks:

- Conversation follows the reviewed character profile across multiple turns.
- The [Columbina evaluation scenarios](characters/columbina-evaluation.md) cover personality range, the configured relationship, unsupported powers, and truthful assistance without requiring fixed wording.
- An interruption invalidates obsolete generation, audio, and speaking cues; late results cannot restart the cancelled reply.
- One user-confirmed preference survives an application restart and can be recalled through a paraphrased question.
- Corrections replace or supersede conflicting claims. Deletion removes the memory from retrieval and any dependent summaries or derived indexes.
- Emotional continuity survives adjacent turns, changes for understandable reasons, and remains compatible with speaking or listening state.
- A network or storage failure produces a clear recovery path without claiming successful recall or persistence.

The purpose is to exercise the memory and emotion contracts early. It is not evidence that long-term autobiographical memory or rich humanlike emotion is finished.

## M3: First complete companion experience

Integrate the prepared real-world object with conversation and a small validated action vocabulary. The character can refer to the currently tracked object and point toward it. Reopening the app restores the confirmed memory and attempts spatial restoration.

Acceptance checks:

- The complete scenario in [product vision](product-vision.md) works end to end on device.
- Object references resolve to current observations; stale targets cause a useful acknowledgement or request to locate the object again.
- The character describes completed actions only after execution results support them.
- Voice, attention, gesture, and expression coordinate during interruption and action failure.
- Repeated sessions expose useful continuity without fabricated shared events.

Manual placement can support experiments, but does not satisfy the prepared-object tracking check. Any substituted step is recorded as incomplete.

## Later iterations

Expand evidence-backed episodic memory, nuanced character expression, user-controlled proactive behavior, richer motion, and additional objects according to observed experience gaps. Evaluate moving-object tracking and optional camera research independently. Do not assume future platform access in milestone commitments.

## Measurements

Record device/system/app versions, room and lighting conditions, network conditions, character asset revision, and service configuration without credentials or unnecessary private content.

| Area | Measure |
| --- | --- |
| Spatial presence | Drift, anchor restoration success, recovery time, and visible contact errors. |
| Conversation | Time to local acknowledgement, first audible response, interruption-to-silence time, and stale-result incidents. |
| Character | Animation transition errors, lip sync quality, expression consistency, and material defects. |
| Memory | Correct recall, unsupported claims, correction success, deletion propagation, and uncertainty handling. |
| Emotion | Persistence across turns, contextual appropriateness, recovery after interruption, and contradictions with the character profile. |
| Runtime | Frame performance, sustained thermal behavior, session stability, and service cost per hour. |

Set numeric budgets after the initial measurements, before accepting the corresponding feature. Report both typical and slow cases rather than a single favorable run. First-release acceptance does not rely only on subjective impressions or only on a numerical emotion score.

## Test strategy

Automate behavior that benefits from repeatability: action preconditions, stale observation rejection, cancellation, memory correction/deletion, and storage migration. Use replayable conversation scenarios to compare personality and recall across model changes. Include at least one success case, one failure case, and a relevant edge case for each meaningful behavior.

Evaluate rendering, spatial audio, tracking, embodied expression, and comfort on device. Store test scenarios and summarized results; retain private recordings or conversation transcripts only through an explicit user choice. Run relevant build, type, lint, and test checks once implementation exists.

## Open inputs

- Review feedback on the source-derived Columbina profile and which lore details need independent verification.
- Natural standing posture, motion quality, and measured performance after the preliminary static-appearance pass.
- Character scale, interaction distance, and voice direction for the source-derived Simplified Chinese style.
- The first physical reference object and its available 3D asset.
- Device system version and near-term distribution intent.

Choose inputs in dependency order. Model services, storage libraries, and a larger animation system remain unselected until their experiments justify a choice.

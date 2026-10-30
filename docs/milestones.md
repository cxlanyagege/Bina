# Milestones and Validation

Status: D1 spatial checks and preliminary appearance have user-reported passes. Stance/idle, head attention, selected hair physics, two eye states, blinking, and facial previews are implemented. All 115 tests pass. The latest hair check has a preliminary pass; facial headset acceptance and sustained performance remain open. Last updated: 2026-10-30.

## Planning rules

Begin with the largest uncertainty that affects the next observable experience. Keep experiments small, but integrate successful results into one complete interaction before extending scope. Do not mark an experiment successful solely because an API compiles or a model loads in a desktop preview.

Use the user's Apple Vision Pro for spatial and character evaluation. Record measurable results before setting production budgets. Resolve product decisions when they affect dependent work; routine reversible engineering choices do not need a separate approval process.

## D0: Documentation and source intake

Current state: documentation drafted; persona source review and its design adaptation are complete. The user has initially reviewed the documents. A local model source and notice have been inspected and conversion completed. The user reported visionOS 27.2 on 2026-10-30; the project still targets 27.0. Runtime persona integration has not started.

Deliverables:

- A consistent product, platform, character, memory, and architecture baseline.
- Reviewed OpenClaw `IDENTITY.md` and `SOUL.md`, with source content fingerprints and adaptation boundaries recorded in the [character profile](characters/columbina.md).
- An initial character profile defining Columbina's identity, personality, dialogue style, fictional background, and configured relationship separately from actual shared events.
- A candidate model source with known files, provenance, and applicable usage terms.
- A recorded device system version and a deliberate deployment-target choice.

Exit evidence: each immediate implementation dependency is either resolved or isolated behind a documented fallback. Documents distinguish confirmed choices from proposals. Source review does not imply runtime persona integration, independent canon verification, model availability, rights, or device results.

## D1: Independent feasibility experiments

The first placement/restoration experiment now has an implementation. It includes mixed-space entry and exit, a generated placeholder, manual heading-based placement, live scale/yaw controls, anchor-association persistence, recovery status, and explicit forgetting. Device and Simulator SDK builds pass, and 27 automated tests pass on visionOS Simulator 27.0. On 2026-10-29 the user reported that the four delivered feature groups worked on a physical headset. Detailed stress checks and measurements are not yet recorded. See the [spatial prototype guide](spatial-prototype.md#initial-device-feedback) for the scope of that feedback.

The character experiment has a local USDZ conversion and asynchronous runtime-loading path. The preceding static preview passed ARKit USD validation, SDK builds, and 39 tests, including actual bundled loading, materials, and bounds normalization. After eye-material and clothing-backface corrections, the user reported no obvious visual issues in a preliminary headset check on 2026-10-30. Natural stance and restrained procedural idle are now implemented, including pause/resume and source-pose comparison. The user found posture and motion generally acceptable, then reported cuff penetration even while paused. After pose calibration and an actual imported hand/cuff geometry regression, the user confirmed the issue resolved. Bounded head attention is now implemented with separate headset acceptance pending; current evidence belongs in the [verification record](spatial-prototype.md#automated-verification). This remains partial M1 progress: automatic floor placement, environmental occlusion, measured performance, and broader companion behavior are separate work.

Current priority, following the user's 2026-10-29 request: see Columbina in the real room before adding conversation. On 2026-10-30 the user requested implementation of natural stance, minimal idle, and comparison controls. Text conversation and the confirmed-preference lifecycle remain planned; they no longer precede this visual increment.

| Experiment | Success evidence | Important failure case |
| --- | --- | --- |
| Placement and restoration | A marker stays at a chosen location and returns through a valid saved anchor in repeated sessions. | Missing anchor, recentering, interruption, and changed room. |
| Geometry and occlusion | A simple entity has credible placement and selected occlusion in the real test room. | Incomplete geometry, tracking loss, and thin or difficult surfaces. |
| Character asset | The candidate renders at correct scale; controlled skeletal motion, an expression, and a mouth shape work on device. | Missing textures, broken skinning, unsupported materials, and excessive cost. |
| Speech and interruption | Test speech plays spatially and stops promptly on explicit interruption without stale queued playback. | Late stream chunks, playback error, and denied microphone permission. |
| Prepared object | One reference object is found, tracked, and invalidated correctly when tracking ends. | Occlusion, poor lighting, similar objects, and target moved out of view. |

Use a placeholder model or scripted audio to isolate an experiment when useful. Such substitutions do not validate the final character asset or a live conversation service. A failed candidate model should lead to a specific pipeline adjustment or an alternative candidate, not an unrelated renderer rewrite.

Exit evidence: results identify a workable path for the first experience and document unresolved limitations.

## M1: Spatial character presence

Integrate a mixed immersive scene, explicit placement, a validated character asset, basic idle behavior, and attention toward the user based on available input. Include anchor restoration and a placement recovery path.

Current partial result: [local model intake](characters/columbina-model.md), stance/idle, head attention, selected hair physics, two eye states, blinking, manual facial previews, and a loader retaining the placeholder until success. The user found stance/idle acceptable, confirmed the cuff correction, and reported no major issue in the latest rear-hair check. Facial acceptance, conversational expressive behavior, broader costume validation, and measured performance remain open.

Acceptance checks:

- Correct scale, orientation, and ground contact in the test room.
- Stable placement during ordinary head movement and approach.
- Coherent response to tracking loss and session suspension.
- Restoration attempts use current anchor validity rather than remembered raw coordinates.
- Character appearance and a small motion set pass the [asset checklist](character-assets.md).

### Next increment: natural stance and minimal idle

Status: implemented; posture and motion are generally acceptable in user feedback, and the user confirmed the calibrated pose resolved the reported cuff defect. Measured performance and broader costume validation remain open.

Unique ASCII bone names repair the prior export's ambiguous joint paths. Paired pose metadata applies a relaxed standing target and defines upper-body idle roles without changing the feet or world placement. The procedural controller samples reference transforms, freezes when paused or hidden, and provides source-pose comparison with a smooth return to natural idle. Eyelid controls remain a separate capability to validate; this increment adds no blink or user-following head behavior.

The cuff correction retains 26-degree upper-arm lowering, removes the added elbow bend, and adducts each thumb by 6 degrees. Authoring validation records zero hand/main-cuff crossings in the natural pose, and a native regression checks the actual imported skinned geometry at sampled idle phases. This is a calibrated pose correction, not a cloth simulation system. Earlier full-body comparisons missed the close-up defect; the later explicit user feedback establishes the user-reported cuff-fix pass.

Acceptance checks:

- Feet and world placement stay fixed while the upper body moves subtly.
- Shoulders, elbows, sleeves, skirt, and cloak remain coherent through pose changes; intersections are recorded and corrected.
- The loop has no visible jump, and pausing or leaving the immersive scene stops its updates cleanly.
- Eye and cloth material corrections remain intact from several views.
- A local preview control can pause the idle and return to the reference pose for comparison.

The existing local source supplied the model and pose data; no external motion pack or service is required. Preserve the cuff regressions and recheck affected costume regions when extending motion. Record the installed app revision and full system build with future headset checks. Blinking, walking, sitting, cloth simulation, and conversation are separate tasks.

### Bounded head attention

Status: implemented after the user-reported cuff-fix pass; automated and native rendering evidence are recorded in [Head attention](head-attention.md). Subsequent headset feedback reports hair/collar penetration, so dynamic costume acceptance is not achieved.

Use the active world-tracking session's current, valid device pose as a target for the character's head and neck. Apple documents [DeviceAnchor](https://developer.apple.com/documentation/arkit/deviceanchor) as the position and orientation of Apple Vision Pro, obtained through `WorldTrackingProvider.queryDeviceAnchor(atTimestamp:)`. The current placement code already uses that provider. Device position supplies an approximate user head target, not eye-gaze or emotion evidence.

The implemented experience is a gentle, bounded turn as the user moves nearby, with a small dead zone and smooth settling. Targets outside the supported forward range, extremely close targets, and unavailable tracking lead toward a neutral orientation. Feet, root placement, and the accepted arm/thumb stance remain fixed. Attention and existing idle compose through one joint-presentation owner. A preview toggle is available; pause freezes the complete pose, and reference selection clears attention and restores the imported source pose.

Acceptance checks:

- Sideways and vertical movement produces restrained head/neck motion without jitter or abrupt snapping.
- Passing behind or very close to the character never causes extreme neck angles or a sudden body turn.
- Tracking loss, scene exit, and re-entry cannot reuse a stale target or apply a pose jump.
- Pause/reference controls have clear behavior, and existing idle, fixed-foot, and cuff regressions continue to pass.
- Close-up headset checks inspect hair, face, neck, and collar deformation at the permitted limits.

### Selected hair secondary motion and collision

The source audit found 607 rigid bodies, 956 spring joints, and mappings for all 593 physics-linked source bones. This increment does not replay that full graph: four hair chains/22 bones now use calibrated springs and eight body/collar capsules. It retains the native app, unchanged model/stance resources, and one final joint writer. The installed SDK's native cloth API probe remains separate from this custom spring integration.

The user confirmed improved cheek locks but found rear hair twitching during head turns and model rotation. The subsequent correction adds primary-pose chain guides, valid hard quaternion limits, non-impulsive contact correction, angular-speed bounds, and yaw-preserving history. The [secondary-motion contract](secondary-motion.md) records the solver, profile, controls, debug geometry, CPU timing snapshot, 95-test pass, and native mesh/motion comparisons. Selected collar-region and continuity checks pass on desktop; the next gate is a new headset check of rear-hair stability, natural lag/settling, pause/re-entry/scale behavior, and measured device cost. After that gate, expand selected accessories or evaluate a native cloth panel. Authored clearance, weights, and fitted collar deformation remain part of the broader solution.

The subsequent user report found no major issue in the rear-hair correction. Record a preliminary stability pass while retaining the broader costume/performance checks.

### Facial channels and eye-state presentation

The facial increment repairs the source export's blend-shape naming collisions, validates six semantic controls, and adds covered/closed versus uncovered/open presentation. The cover fades before eyes open and returns after they close. Uncovered eyes blink naturally. Neutral/smile/curiosity and relaxed/open/round mouth shapes are manual previews. Playback gating, reference restore, safe replacement, primary-motion fallback, and per-frame skeleton/material ownership are tested.

The [facial contract](facial-presentation.md) records 115 passing tests, repaired/paired resources, native renders, and pending device review. After that gate, prioritize the M2 text-personality and confirmed-memory loop before voice and synchronized mouth motion. Those conversational capabilities remain proposals.

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
- Facial presentation on the headset, broader transition/costume quality, and measured performance. The cuff issue has a user-reported pass, and the latest rear-hair check has a preliminary stability pass.
- Character scale, interaction distance, and voice direction for the source-derived Simplified Chinese style.
- The first physical reference object and its available 3D asset.
- Full device system build and near-term distribution intent; the user-reported system version is 27.2.

Choose inputs in dependency order. Model services, storage libraries, and a larger animation system remain unselected until their experiments justify a choice.

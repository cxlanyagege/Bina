# Spatial Prototype

Status: classified-floor preview/confirmation, calibrated sole contact, manual-height fallback, stance/idle, head attention, selected hair physics, and facial previews are implemented. The user reported preliminary hair stability and natural facial presentation. Floor contact, sensing/recovery behavior, and sustained performance require headset checks on visionOS 27.2. Updated: 2026-10-31.

## Scope

The app opens a mixed `ImmersiveSpace`, places a character using ARKit world tracking, and attempts to restore the selected anchor across sessions. It asynchronously loads the locally converted Columbina USDZ, retaining the generated humanoid placeholder while loading or on failure. Both use a 1.6-meter reference height before the user changes scale.

This does not complete M1. The [floor workflow](floor-placement.md) requires stable, classified floor coverage and explicit confirmation, then uses the existing world-anchor path. Environment occlusion/collision avoidance, walking, foot IK, conversational behavior, and personal memory remain unimplemented. Facial controls are manual previews. The real room remains visible through passthrough.

## Local Columbina preview

The current preview adds relaxed stance, idle, neck/head attention, selected hair dynamics, and manually selected eye/expression/mouth states. Unique ASCII joint and facial names repair the original export's identifier collisions. Pose, physics, and face metadata are paired to the exact USDZ. Attention reuses the existing tracking provider; hair proxies describe the character rather than the room. Original toon/sphere effects, lip sync, voice, and full garment cloth remain unimplemented.

The files `Columbina.usdz`, `ColumbinaIdlePose.json`, `ColumbinaPhysics.json`, and `ColumbinaFace.json` under `Bina/Resources/Characters/` exist locally and are ignored by Git. A clone does not contain them. All metadata must match the exact model. Keep generated assets local under the source notice; the [model intake](characters/columbina-model.md) records provenance, hashes, reproduction, and limits.

The control window distinguishes model loading, success, and failure. A missing or unreadable model leaves the spatial placeholder available, shows an explicit explanation, and offers a model-load retry. Missing, invalid, or mismatched idle data keeps the loaded static model and explains why stance/idle controls are unavailable. Do not interpret a visible placeholder as a successful Columbina preview.

## Local developer tools

The user identifies Device Hub as the current developer GUI entry point, with the reported path `/Applications/Xcode.app/Contents/Developer/Applications/Device Hub.app`. Device Hub was resolved through bundle identifier `com.apple.dt.Devices`; opening it, starting the simulator, and reading its GUI succeeded. Prefer desktop app discovery instead of assuming `Simulator.app`. Clicking visionOS app content failed through the current UI tool, so no completed interactive visual walkthrough is claimed. This environment note does not change the `xcodebuild` test commands below.

## Run on Apple Vision Pro

1. Record the headset system build and Xcode versions. The user reports visionOS 27.2 as of 2026-10-30; the project still requires 27.0 or later.
2. Open `Bina.xcodeproj` in Xcode and select the shared `Bina` scheme.
3. Select the paired headset as the run destination. Confirm the signing team and normal device-development setup for this installation.
4. For a character-enabled build with motion and facial controls, confirm all four matching local resources exist at the paths above. Build and run while wearing the headset.
5. Check model status in the control window. Wait for successful loading; a failure offers retry and leaves the placeholder available for spatial checks.
6. Use the enter-space button, allow the system world-sensing request for floor detection, and wait for tracking. Denied or unsupported plane sensing leaves manual-height placement available; no simulated floor is substituted.
7. Select stand-on-floor, slowly inspect the real floor, and wait for stable-floor status. Face the desired direction, choose the horizontal distance, then preview. Inspect the green foot-range disk and confirm placement/save. If no suitable floor is found, adjust distance/direction or switch to manual height and choose the headset-to-feet offset before place-and-save.
8. Adjust scale and yaw. Grounded placements retain the same sole contact point; legacy/manual placements retain their original pivot. Placement-distance and manual foot-offset changes apply to the next request. Appearance changes cancel an unconfirmed floor preview. Natural stance is selected by default, and idle advances only while the character is visible.
9. With attention enabled, move sideways, sit/stand, approach, and pass behind the character. Compare with attention disabled. Pause/resume and compare the reference pose with the natural stance. Inspect neck, hair, collar, feet, shoulders, sleeves, skirt/cloak, eyes, and transparency. Record deformation differences and any motion jump.
10. In the facial group, compare covered/closed with uncovered/open. Inspect automatic and manual blinks, reverse an eye-state transition, preview neutral/smile/curiosity and mouth shapes, then check pause/reference/re-entry. Review both close facial views and conversational distance.
11. Exit and reenter, then relaunch in the same room. Observe whether the saved anchor returns and idle updates restart while preserving the selected in-process pause/reference mode. If the anchor is unavailable, wait at the original location or explicitly place again.

The interface is in Simplified Chinese. The control names below describe their meaning in English.

## Controls and placement semantics

| Control | Behavior |
| --- | --- |
| Enter/exit space | Opens or dismisses the mixed immersive scene. Transitions prevent duplicate open/close requests. |
| Model status and retry | Reports whether Columbina loaded; retries a failed or missing local asset without changing saved placement. |
| Placement mode | Stand-on-floor is the default; manual height remains available when floor sensing is denied, unavailable, or insufficient. |
| Horizontal distance | 0.75–3.0 meters; initially 2.0. Applies to the next placement. |
| Preview floor placement | Uses fresh device heading and stable classified floor coverage to freeze a world-space green disk. Re-preview replaces it; head movement does not make it follow. |
| Confirm floor placement and save | Revalidates the preview, settings, tracking, and floor support before committing a sole-aligned world anchor. Cancellation leaves the saved placement untouched. |
| Retry floor detection | Creates fresh tracking/plane providers after a floor denial or failure, retaining saved placement. Allow system permission first when needed. |
| Feet below headset | Manual-height mode only: 0–2.0 meters, initially 1.4. A manual vertical offset, not measured floor height. |
| Manual place/re-place and save | Uses current valid device pose, projected horizontal heading, and the chosen offsets. The character initially faces back toward the user. |
| Height | 0.4–1.9 meters; initially 1.6. Changes visible character scale without moving its anchor; grounded records retain the sole pivot. |
| Heading adjustment | Local yaw from -180 to 180 degrees. It does not make the character continuously turn toward the user. |
| Pause/resume idle | Freezes the complete current pose, including attention and cycle phase, then continues from that pose. Toggle changes take effect on resume. Unavailable in reference mode or when idle preparation fails. |
| Look toward me | Enabled by default; gently turns neck/head toward a fresh tracked device position. Rear, near, invalid, or missing targets return toward neutral. Disabling blends toward neutral during playback. |
| Hair physics | Enabled by default when its profile is valid. Four selected chains bend/settle and avoid body/collar proxies. On/off comparison blends over 0.25 seconds; a paused action change waits for resume. |
| Show physics debug | Hidden by default. Green chain segments/cyan tips and orange collision capsules help inspect contact; changing debug visibility does not advance the pose. Hidden in reference mode. |
| Record physics CPU time | Captures recent average/peak costs from at most 600 physics updates. This includes solver/binding and optional debug updates, not GPU rendering or total app frame time. |
| Eye state and natural blink | Defaults to covered/closed. Uncovering hides the cover before opening the lids; returning closes the lids first. Automatic blinking is active only when uncovered. |
| Facial and mouth previews | Neutral/smile/curiosity and relaxed/open/round mouth controls are manual previews. Blink preview and reset are available during playback; reference restores source facial data. |
| Reference/natural comparison | Restores the original source pose and clears attention; returning blends the natural stance over 0.9 seconds and reacquires attention smoothly. The placement anchor is unchanged. |
| Retry tracking | Available after tracking failure; creates a fresh session/provider while retaining placement metadata. |
| Forget saved position | Requires confirmation, clears only the prototype's placement association, and hides the placeholder. Placement can then start again. |

The heading helper ignores head pitch and roll so the character stays upright. Looking nearly straight up or down provides no usable horizontal heading and prompts another placement attempt. Floor mode solves height from a classified mesh, checks complete foot-range coverage, and keeps a frozen preview until confirmation or invalidation. Confirmed placement does not resnap as planes refine. Manual mode still depends on the chosen head-relative offset. See the [floor contract](floor-placement.md) for thresholds, calibration, and limitations on slopes/uneven ground.

Appearance and placement controls survive leaving and reentering the immersive space within the same process. They reset to defaults after application restart. Only the saved anchor association persists; the prior scale and yaw are not restored.

Idle repeats on an 11-second cycle with 5.5-second breathing, using small upper-body joint rotations. The pelvis, legs, feet, character pivot, and world anchor remain fixed. User pause preserves phase; tracking loss, scene inactivity, or hidden content also freezes time without changing playback intent. Exiting the immersive view cancels its render-update subscription and invalidates the callback token. Playback mode and phase are in-memory preview state and are not persisted across process restarts.

Attention uses approximate device position, not eye gaze. It adds bounded neck/head rotation through the same joint controller and respects current placement rotation and scale. Inactive content clears target hysteresis while retaining its displayed pose; visibility recovery supplies a new target and interpolates from the retained orientation. Attention preference is also in-memory state. See the [head-attention contract](head-attention.md) for limits and coordinate handling.

Hair physics is an independent preparation/failure boundary within that presentation controller. Invalid physics data retains primary motion. Hidden scenes, reference transitions, significant translation/scale changes, and frame gaps over 0.05 seconds reset stored kinetic history; the heading slider preserves it. Rear locks have primary-pose bend/twist and angular-speed bounds. Pause freezes the displayed hair pose. Physics preferences and velocity are not persisted. See [Secondary motion](secondary-motion.md) for its normalized coordinates, constraint priorities, selected-region coverage, and local profile generation.

Face playback shares playing/visible gating, but owns only blend weights and the eye-cover material. Imported facial data is captured before preview changes. Pause/hidden content freezes timers; reference restores original weights/material and clears pending blinks. Returning starts covered/closed before reacquiring the selected preferences. Invalid face data retains primary motion with an explanation. See [facial presentation](facial-presentation.md) for channel repair, timing, and acceptance limits.

## Persistence and recovery

ARKit owns world-anchor persistence. Bina writes `Application Support/Bina/spatial-placement.json` inside its application container, with schema version, anchor UUID, creation date, and optional `soleContact` alignment. Existing schema-1 records without alignment retain their original model-origin semantics. Loading does not rewrite them. Plane meshes/IDs and raw world coordinates are not stored as restoration authority. [Apple world-anchor guidance](https://developer.apple.com/documentation/visionos/tracking-points-in-world-space)

- The placeholder is hidden whenever the scene is inactive, the provider is not running, or device/anchor tracking is invalid. Scene inactivity, provider pauses, and device-tracking loss invalidate cached anchor observations. Resuming first refreshes current anchors before rendering; the old pose is not reused as evidence of recovery.
- Session-generation and anchor-revision checks reject snapshots that became obsolete during an asynchronous read, as well as late results from previous sessions. Current valid updates can make the placeholder visible again.
- After eight seconds without a tracked saved anchor, the message explains recovery options. This is an informational wait, not a deletion deadline. A later valid update can still restore the position.
- Replacing a position selects the newly added and saved association before attempting to remove the previous anchor. Late updates for replaced anchors and stopped sessions cannot select the old placement again.
- If adding or saving a new position fails, the prior association is retained. A cleanup failure is reported; an unused ARKit anchor may remain, but it is not selected as the character's location.
- On entry/device recovery, the prototype reconciles app-owned anchors against its single selected placement and any pending replacement. Unexpected added anchors are also considered for serialized cleanup. Failed cleanup can be retried through reconciliation in a later session; the current or pending placement is protected.
- Corrupt or unsupported placement JSON is retained and reported. Placement is blocked until the user explicitly chooses forget-saved-position and confirms, then places again. There is no silent reset or overwrite.
- Automatic anchor cleanup is disabled while metadata needs an explicit reset. This avoids removing an anchor whose association cannot currently be read. After reset, a later entry/device recovery can reconcile remaining anchors.
- Forgetting removes the local association first and attempts ARKit cleanup when a provider is available. If forgotten while the space is closed, cleanup is deferred to later reconciliation. No conversation or character data is affected.

The cleanup policy assumes this prototype is the application's only world-anchor owner. Add explicit ownership rules before other features begin storing anchors; do not reuse the single-placement policy unchanged for multiple independent spatial features.

World tracking itself does not require user authorization. Floor detection additionally requests world-sensing authorization with a purpose string in `Info.plist`. The prototype does not request camera, hand, or scene-reconstruction data. Support, authorization, and individual provider state are checked. See [platform capabilities](platform-capabilities.md).

## Device acceptance checklist

Record each case as pass, fail, or unassessed, with reproduction steps for failures.

| Case | Expected observation |
| --- | --- |
| First launch and placement | Floor preview needs active tracking and stable floor coverage; confirmation places at the inspected green disk. Manual-height fallback uses its chosen offsets. |
| Floor permission/fallback | Allowed permission enables classification; denial/revocation hides the preview while retaining manual mode and valid saved-world placement. |
| Ground contact and preview | Inspect seated/standing placement, all supported heights, and several headings. Both feet fit the disk and meet the real floor; head movement leaves the preview frozen. Tables/unknown planes cannot substitute for the floor. |
| Floor evidence changes | Loss of tracking/support cancels the unconfirmed preview. Confirmed placements remain tied to the saved world anchor through later plane refinements. |
| Local character load | Status reports success and Columbina replaces the placeholder at the same placement, scale, and heading. |
| Missing or invalid local model | Status reports failure; the placeholder remains usable and retry does not reset placement. |
| Missing or mismatched idle data | The static model remains available, the idle explanation is visible, and no incorrect skeleton mapping is applied. |
| Character visual review | Check the static pose, face, hair, eye covering, clothing, feet, texture completeness, and transparency from several angles. Inspect both sides of front and rear cloth panels. Record material differences and performance. |
| Natural stance and idle | Arms and shoulders look relaxed; subtle motion loops without a jump, fixed feet remain planted, and sleeves/skirt/cloak do not show new intersections. |
| Pause/resume and reference comparison | Pause freezes the current pose; resume continues its phase. Reference restores the source pose, then natural idle returns smoothly without moving placement. |
| Head attention | Lateral and vertical movement produces restrained neck/head turns. Small movements remain stable; rear and close targets lead toward neutral. Toggle, pause, reference, and re-entry preserve clear behavior. Inspect hair and collar at the permitted limits. |
| Selected hair physics | Compare on/off while turning, looking down/up, and changing direction. Hair shows restrained lag/settling and avoids the selected collar region. Check pause/reference, re-entry, re-placement, and scale changes; record CPU timing with debug off and separately inspect debug proxies. |
| Eye states and facial previews | Covered eyes remain closed; uncovered eyes blink without the cover reappearing. Reversals keep the cover/lid ordering. Check expressions, mouth previews, pause/reference, tracking interruption, and preserved eye materials from above/level/below. |
| Movement and head tilt | The placeholder remains at its world anchor rather than following head movement; its upright orientation is maintained. |
| Scale and yaw | Changes are visible immediately while the anchor stays fixed. Next-placement settings do not move the current anchor. |
| Repeated entry/exit | Scene, tracking, and render-update subscription restart without duplicate content or stale callbacks. Natural idle resumes when visible; a user pause or reference selection stays selected within the same process. |
| App restart in the same room | Restoration is attempted through the saved UUID. Record actual success and time rather than assuming it. |
| Missing location or different room | No guessed placement appears. Waiting beyond eight seconds retains the saved association and offers re-placement. |
| Recenter with Digital Crown | The current anchor transform updates while the physical placement remains credible. Record any discontinuity. |
| Session inactivity or tracking loss | The placeholder hides, then returns only when current tracking is valid. Record device-dependent interruption behavior. |
| Pause, recenter, and resume | Suspend or interrupt the experience, change position or recenter where supported, then resume. The placeholder stays hidden until fresh anchor observations are available; no stale pre-interruption pose flashes into view. |
| Re-place while old updates arrive | The new association remains authoritative; old-anchor updates do not revive the prior location. |
| Exit during placement | Late work cannot display content from the ended session. Reentry remains usable. |
| Forget and relaunch | After confirmation, there is no selected saved placement; the user can place again. |
| Forget while the space is closed | Place, exit the space, forget in the control window, then reenter. The old placeholder does not return; reconciliation attempts to remove leftover app-owned anchors. Record cleanup warnings and inspect anchor diagnostics when available rather than treating hidden content as proof of removal. |
| Damaged metadata | In a controlled development container, corrupt test metadata is reported and preserved until explicit reset. Never modify unrelated app data. |
| Cleanup after metadata reset | While the record is unreadable, confirm no automatic cleanup is attempted. Explicitly forget it, then reenter; stale app-owned anchors can be reconciled without reviving an old placement. |

Spatial stability, restoration rate, visual comfort, and sustained performance require the headset. Simulator and automated tests do not establish these results.

## Initial device feedback

On 2026-10-29, the user reported testing the four delivered feature groups on a physical Apple Vision Pro with no problems:

| Feature group | Evidence |
| --- | --- |
| Mixed immersive entry and exit | User-reported pass. |
| Placeholder placement, distance, height, scale, and orientation controls | User-reported pass. |
| Saved-anchor restoration after reopening or restarting | User-reported pass. |
| Invalid-tracking hiding, re-placement, and forgetting | User-reported pass. |

This feedback predates the local Columbina integration. It is sufficient to proceed with the visual increment, but is not character appearance acceptance, an independently reproduced result, or a pass for every edge case. The headset system version, tested app revision, room conditions, repeat counts, measured drift, restoration timing, and specific stress cases were not supplied. Keep untested cases open and collect those details during later device sessions.

Subsequent Columbina headset testing found view-dependent eye defects: correct rendering from above, white eye surfaces at eye level, and missing layers with exposed stars from below. The material export has been corrected and passes three-angle comparisons in macOS RealityKit. See the [eye-material correction](characters/columbina-model.md#eye-material-correction) for the diagnosis and local evidence.

The user also reported that front cloth disappeared when viewed from behind, and rear cloth disappeared when viewed from the front. The loaded materials were culling their backfaces. The loader now restores the source's double-sided surfaces, retaining the single-sided shoes and existing opacity.

On 2026-10-30, the user reported no obvious remaining visual issues in a preliminary naked-eye headset check. This is an initial static-appearance pass after the material corrections. The feedback does not establish animation quality or sustained performance; a detailed checklist and measured results were not supplied. Recheck material appearance as natural stance and motion are introduced.

The user subsequently reported visionOS 27.2 and requested the natural-stance/idle increment. After trying it, the user found posture and motion generally acceptable but reported severe cuff penetration that persisted while paused. On 2026-10-30, after testing the calibrated pose, the user confirmed that the issue was resolved. This is a user-reported cuff-fix pass, separate from the earlier static-appearance feedback; no detailed checklist or performance measurements accompanied it.

Subsequent user feedback reported no major issue with the corrected rear hair and found the facial presentation natural. These are preliminary stability/naturalness passes without a complete visual checklist or sustained measurements. The user then chose the first real-floor placement increment before walking animations. No physical-device floor result is recorded yet.

## Automated verification

The shared `Bina` scheme includes `BinaTests`. Geometry tests exercise heading, offsets, and invalid input; storage tests exercise metadata round-trips, corruption, schema handling, and clearing. Controller-state tests exercise open/close transitions, cancellation, metadata loading, and explicit reset with a fake store.

Verification recorded on 2026-10-26 with Xcode 27.1 (27A9275):

| Check | Recorded result |
| --- | --- |
| Generic visionOS Simulator build | Passed for arm64 and x86_64. |
| Generic visionOS device build | Passed with code signing disabled; not an installation or headset run. |
| visionOS Simulator 27.0 tests | 27 passed, zero failures, zero skips; 8 geometry, 7 storage, and 12 controller-state cases. |
| Interactive Simulator walkthrough | Not recorded; the Simulator GUI was unavailable through the UI tool. |
| Physical-device checks | Four basic feature groups passed according to user feedback on 2026-10-29; detailed checklist and measurements remain open. |

The test report is `Bina-SpatialPrototype-Tests-2.xcresult`, generated in the local temporary directory. Automated cases do not start a live ARKit session or establish spatial stability. Pause/recenter/resume and unused-anchor cleanup still require the device checks above.

Preceding static/material-correction verification recorded on 2026-10-30:

| Check | Recorded result |
| --- | --- |
| Device and Simulator SDK builds | Passed; both built app bundles contain the corrected 26,560,808-byte local character asset with the recorded SHA-256. The device build is not a headset run. |
| visionOS Simulator 27.0 tests | 39 passed, zero failures, zero skips: the previous 27 cases plus six bounds-normalization cases, four actual bundled-asset cases, and two material-policy cases. |
| Actual RealityKit asset loading | Passed with normalized 1.6-meter reference height, feet placement, centering, and nonempty geometry. |
| ARKit USD validation | `usdchecker --arkit` passed. |
| Authoring preview | Front render inspected; this is not a headset render or proof of exact material fidelity. |
| Eye-material regression | The old export fails all six opaque eye/face assertions; the corrected export passes. Continuous eye-covering/hair transparency and effective shoe opacity are preserved. |
| Surface-sidedness regression | The source's 25 double-sided PBR materials retain both faces; shoes retain back-face culling. Nested material configuration preserves opacity and other material types. |
| macOS RealityKit visual comparison | Matching above/level/below views reproduce white eyes, stars, and exposed layers in the old export; both purple irises remain visible in the corrected export. |
| Clothing visual comparison | Matching front/rear/oblique and isolated cloth views using the actual runtime helper restore missing backfaces. Three additional eye views preserve the earlier eye correction. These are macOS renders, not headset captures. |
| Device Hub interaction | GUI discovery, opening, simulator start, and reading succeeded; app-content clicking was unavailable, so the interactive visual walkthrough is incomplete. |
| Columbina on a physical headset | On 2026-10-30 the user reported no obvious visual issues after the corrections. Preliminary static-appearance pass; motion and measured performance remain open. |

That baseline result bundle is `Bina-Cloth-Culling-Tests.xcresult` in the local temporary directory. Its asset hash was unchanged by the runtime sidedness correction. The new skeletal export has a separate paired pose file and intake record.

Historical stance/idle verification before the cuff correction, recorded on 2026-10-30:

| Check | Recorded result |
| --- | --- |
| Device and Simulator SDK builds | Passed; both app bundles contain the matching model and pose file from the new export. The device SDK build is not a headset run. |
| visionOS Simulator 27.0 tests | 56 passed, zero failures, zero skips: the preceding 39 cases plus eight playback cases, five pose-validation/pairing cases, and four bundled skeleton/motion cases. |
| USD and skeletal import | `usdchecker --arkit` passed; RealityKit imports 790 uniquely named joints. |
| Native macOS pose/motion comparison | Thirty broad views cover reference and natural poses at 0, 2.75, 6, and 11 seconds across six viewing directions. These missed the cuff penetration subsequently reported on the headset. |
| Native motion invariants | Fixed-foot world transforms and model-root matrices remain unchanged. Pause and hidden updates preserve phase; resume advances; reference restoration is exact. |
| Headset stance/idle feedback | Posture and motion were generally acceptable to the user on visionOS 27.2, but severe cuff penetration remained visible even while paused. This was not an appearance acceptance. |

The result bundle is `Bina-Idle-Tests-2.xcresult` in the local temporary directory. Runtime evidence is retained in `LocalAssets/Columbina/idle-diagnostics/`, including `runtime-verification.json`. Exact asset hashes and preparation instructions belong in the [model intake](characters/columbina-model.md).

The cuff correction retains the relaxed arm lowering, removes the added elbow bend, and gently adducts the thumbs. The exact source reference retains its tiny original intersection; this calibration is not a general cloth collision solver. The user has confirmed the reported issue resolved. Preserve the cuff regressions and repeat relevant close-up checks when adding further motion.

Current cuff-correction verification, recorded on 2026-10-30:

| Check | Recorded result |
| --- | --- |
| Authoring geometry | Zero strict hand/main-cuff crossings on both sides in the natural pose; zero movement across 10,870 lower-body vertices; source pose bases restored exactly. |
| visionOS Simulator 27.0 tests | 57 passed, zero failures, zero skips, including the new actual-mesh cuff regression at 0, 2.75, 6, and 11 seconds. Result bundle: `/private/tmp/Bina-Cuff-Fix-Tests.xcresult`. |
| USD and SDK builds | `usdchecker --arkit`, Simulator test build, and generic visionOS device build passed. Both app bundles contain the exact current paired model and pose resources. |
| Native close-up comparison | 84 final-resource RealityRenderer captures cover seven stages, two wrists, and six directions. They are byte-identical to the reviewed corrected candidate; the large thumb penetration and small front-view sliver are removed in the natural pose. |
| Corrected-build headset feedback | User-reported cuff-fix pass on 2026-10-30, using the previously reported visionOS 27.2 headset. No detailed checklist was supplied; scene comfort and sustained performance remain unmeasured. |

The close-ups and transition captures are retained in `LocalAssets/Columbina/sleeve-diagnostics/production-final/`. Exact fingerprints, regression scope, and source-reference limitations are recorded in the [model intake](characters/columbina-model.md#cuff-penetration-correction).

Head-attention verification before the hair correction, recorded on 2026-10-30:

| Check | Recorded result |
| --- | --- |
| visionOS Simulator 27.0 tests | 73 passed, zero failures, zero skips: the preceding 57 cases plus 11 pure attention cases and five bundled attention cases. Result bundle: `/private/tmp/Bina-Head-Attention-Tests-4.xcresult`. |
| SDK builds and resources | Simulator test build and generic visionOS device build passed; both retain the exact cuff-fix USDZ and paired JSON. No asset re-export was required. |
| Native head/neck comparison | 52 captures cover 13 target/control stages from four views, including hair/collar close-ups, combined turns, rear/near targets, pause, and target loss. Reviewed views show no obvious new gross head/collar defects. |
| Motion invariants | Zero ankle world-position component change, zero paused-pose error, byte-identical paused captures despite a changed target, and exact reference restoration. Actual-rig tests cover rotated/scaled placement and unchanged arm/thumb poses. |
| Headset attention feedback | The user reports hair/collar penetration and rigid accessory behavior. Dynamic costume acceptance has not passed. The cuff-fix pass remains scoped to the earlier hand/cuff issue; comfort and sustained performance remain unmeasured. |

The [head-attention contract](head-attention.md) records calibration, ownership, lifecycle behavior, and native evidence paths.

Current selected-hair verification, recorded on 2026-10-30:

| Check | Recorded result |
| --- | --- |
| Simulator tests | 95 passed, zero failures/skips: the preceding 73 plus ten pure spring/geometry/clock tests, five profile tests, and seven actual-asset physics tests. Result: `/private/tmp/Bina-Rear-Hair-Regression-Tests-3.xcresult`. |
| SDK builds/resources | Simulator test build and generic visionOS device build passed with the unchanged model/stance resources and generated physics profile. |
| Actual skinned-mesh regression | Both hair layers show zero strict crossings against selected body/collar surfaces at seven settled target poses. The cuff regression now has attention and hair physics enabled. |
| Lifecycle/failure behavior | Tests pass for protected primary joints, full-pose pause, exact reference restore, hidden/re-entry history, placement/scale changes, frame gaps, invalid replacement, and primary-motion fallback. |
| Native sweep and visual review | Corrected captures include full rear/side views; 24 bounds-normalized mesh snapshots cover an 11-second sweep. The selected collar region has zero crossings. Motion tests cover 30/60/90/120 FPS and repeated five-degree heading changes; full costume and arbitrary motions are outside this result. |
| Subsequent headset feedback | Cheek locks improved, but rear hair jerked upward during head turns and model rotation. The correction adds primary-pose chain guides, valid quaternion limits, non-impulsive contact correction, angular-speed bounds, and yaw-preserving history. This correction needs a new device check. |
| Headset acceptance | Pending on the user's visionOS 27.2 headset, including physical appearance, naturalness, total CPU/GPU/frame cost, and sustained thermal behavior. |

The [secondary-motion contract](secondary-motion.md) records calibration, evidence paths, CPU snapshot scope, and garment work. The native cloth API probe is still compile-only. The user subsequently reported no major issue in the rear-hair check, a preliminary stability pass without a sustained-performance measurement.

Current facial verification, recorded on 2026-10-30:

| Check | Recorded result |
| --- | --- |
| Full simulator suite | 115 passed, zero failures/skips/warnings: the preceding 95 plus nine playback, four profile, and seven bundled facial tests. Result: `/private/tmp/Bina-Facial-States-Tests.xcresult`. |
| Per-frame ownership supplement | One strengthened ownership test passed at `/private/tmp/Bina-Facial-Ownership-Tests.xcresult`, including every frame of cover-opacity changes. |
| SDK builds/resources | Simulator and generic visionOS device builds pass; all four bundled resources match the local source bytes. Facial repair retains base geometry, skinning, material data, and texture bytes. |
| Native rendering | Nine facial/control states from front, quarter, above, and below views demonstrate covered closure, uncovered opening/blinking, expressions, mouth shapes, return, and reference. |
| Subsequent device feedback | The user found the facial presentation natural. Detailed transition/rendering checks, frame cost, and sustained thermal behavior remain open on visionOS 27.2. |

The [facial contract](facial-presentation.md) records exact resources, source backup, repair commands, lifecycle, and preview scope.

### Floor placement verification

Verification recorded on 2026-10-31:

| Check | Recorded result |
| --- | --- |
| Full visionOS Simulator 27.0 suite | 145 passed, zero failures/skips, no reported runtime warnings. The preceding 115 cases plus seven surface, fourteen floor-evidence/preview, three persistence, three controller-state, and three actual-foot cases. Final result after contact-calibration observability correction: `/private/tmp/Bina-Floor-Placement-Final-Tests.xcresult`. |
| SDK builds and bundled resources | Simulator test build and generic visionOS device build passed with Xcode 27.1 (27A9275), signing disabled. Both app bundles retain all four exact character resources, the world-sensing purpose string, and the 27.0 minimum target. This is not a headset installation or sensor run. |
| Actual foot contact and coverage | Independent CPU skinning includes exposed foot skin and shoe ornaments. Contact and complete disk coverage pass at character heights 0.4, 1.6, and 1.9 meters and headings 0, 90, and -180 degrees. Saved sole alignment preserves the foot pivot; legacy records retain their origin without a load-time save. |
| Calibration measurement | At the normalized 1.6-meter reference, contact center is approximately `(0, 0, -0.162226)` meters and the conservative radius is `0.126108` meters, before the 3-centimeter placement margin. This is geometry measurement, not observed room contact error. |
| Interactive Simulator UI | The screenshot request did not produce an image and was cancelled. No completed visual walkthrough of the new controls/marker is claimed. |
| Live sensing and physical contact | Not yet assessed on the user's headset. Authorization UI, actual classified-plane delivery, detection delay, recentering, visible contact accuracy, drift, and sustained cost require the physical test. |

The [floor contract](floor-placement.md) owns the physical-headset checklist. Local evidence is retained in `LocalAssets/Columbina/floor-diagnostics/`; no character resource is rewritten by this increment.

Select an available visionOS Simulator identifier with `xcrun simctl list devices available`, then run:

```sh
xcodebuild -project Bina.xcodeproj -scheme Bina \
  -destination 'platform=visionOS Simulator,id=<SIMULATOR_UDID>' test
```

Replace the placeholder identifier with an actual available device. No passing result is implied by this command or by the presence of test sources.

## Result record

```text
Date / app revision:
Xcode version / build:
Device model / visionOS version:
Room and lighting conditions:
Placement mode / distance / manual foot offset / height / yaw:
Floor authorization / detection delay / visible sole error:
Build result:
Automated test result / result bundle:
Device checklist results:
Anchor restoration attempts / successes / observed times:
Visible drift or discontinuities:
Interruption and recovery behavior:
Remaining limitations / next experiment:
```

Record the first device result here or in a linked follow-up record. Keep failed and unassessed cases visible; do not mark the full character or companion milestones complete from this experiment alone.

# Spatial Prototype

Status: local static Columbina preview integrated with passing SDK builds and 34 automated tests, including actual asset loading. User-reported device checks cover the earlier placeholder; character device appearance remains open. Updated: 2026-10-29.

## Scope

The app opens a mixed `ImmersiveSpace`, places a character using ARKit world tracking, and attempts to restore the selected anchor across sessions. It asynchronously loads the locally converted Columbina USDZ, retaining the generated humanoid placeholder while loading or on failure. Both use a 1.6-meter reference height before the user changes scale.

This does not complete M1. There is no automatic floor detection, surface snapping, occlusion, collision avoidance, character animation, conversation, or personal memory. The real room remains visible through passthrough.

## Local Columbina preview

The current asset is a static source pose with portable material adaptation. The export passed `usdchecker --arkit`, a front authoring preview was inspected, and an automated test loaded the actual bundled USDZ through RealityKit. These checks do not establish exact material fidelity or headset appearance. Original toon and sphere effects, idle motion, expression control, lip sync, voice, and hair/clothing physics are not implemented.

The file `Bina/Resources/Characters/Columbina.usdz` exists in this working checkout and is intentionally ignored by Git. A clone does not automatically contain it. Keep the original and converted assets local under the source notice; the [model intake record](characters/columbina-model.md) provides provenance, hashes, reproduction instructions, and current validation limits.

The control window distinguishes model loading, success, and failure. A missing or unreadable asset leaves the spatial placeholder available, shows an explicit explanation, and offers a model-load retry. Do not interpret a visible placeholder as a successful Columbina preview.

## Local developer tools

The user identifies Device Hub as the current developer GUI entry point, with the reported path `/Applications/Xcode.app/Contents/Developer/Applications/Device Hub.app`. Device Hub was resolved through bundle identifier `com.apple.dt.Devices`; opening it, starting the simulator, and reading its GUI succeeded. Prefer desktop app discovery instead of assuming `Simulator.app`. Clicking visionOS app content failed through the current UI tool, so no completed interactive visual walkthrough is claimed. This environment note does not change the `xcodebuild` test commands below.

## Run on Apple Vision Pro

1. Record the headset system and Xcode versions. The project currently requires visionOS 27.0 or later.
2. Open `Bina.xcodeproj` in Xcode and select the shared `Bina` scheme.
3. Select the paired headset as the run destination. Confirm the signing team and normal device-development setup for this installation.
4. For a character-enabled build, confirm the ignored local USDZ exists at the path above before building. Build and run while wearing the headset.
5. Check model status in the control window. Wait for successful loading; a failure offers retry and leaves the placeholder available for spatial checks.
6. Use the enter-space button and wait for world tracking to become available. An unsupported environment shows a message; it does not perform fake placement.
7. Look approximately horizontally toward the desired location. Set the horizontal distance and the distance from the headset down to the character's feet, then choose place-and-save.
8. Adjust scale and yaw. These appearance changes are live; placement-distance and foot-offset changes apply when the next placement is requested. The source pose remains static.
9. Inspect face, eye covering, hair, clothing, footwear, textures, and transparency from the front, sides, and back. Record differences from the authoring preview.
10. Exit and reenter, then relaunch in the same room. Observe whether the saved anchor returns. If unavailable, wait at the original location or explicitly place again.

The interface is in Simplified Chinese. The control names below describe their meaning in English.

## Controls and placement semantics

| Control | Behavior |
| --- | --- |
| Enter/exit space | Opens or dismisses the mixed immersive scene. Transitions prevent duplicate open/close requests. |
| Model status and retry | Reports whether Columbina loaded; retries a failed or missing local asset without changing saved placement. |
| Horizontal distance | 0.75–3.0 meters; initially 2.0. Applies to the next placement. |
| Feet below headset | 0–2.0 meters; initially 1.4. A manual vertical offset, not measured floor height. |
| Place/re-place and save | Uses current valid device pose, projected horizontal heading, and the chosen offsets. The character initially faces back toward the user. |
| Height | 0.4–1.9 meters; initially 1.6. Changes visible character scale without moving its anchor. |
| Heading adjustment | Local yaw from -180 to 180 degrees. It does not make the character continuously turn toward the user. |
| Retry tracking | Available after tracking failure; creates a fresh session/provider while retaining placement metadata. |
| Forget saved position | Requires confirmation, clears only the prototype's placement association, and hides the placeholder. Placement can then start again. |

The geometry helper ignores head pitch and roll so the placeholder stays upright. Looking nearly straight up or down provides no usable horizontal heading and prompts another placement attempt. Physical floor contact depends on the manually chosen foot offset; leaning or changing head height before placement changes that reference.

Appearance and placement controls survive leaving and reentering the immersive space within the same process. They reset to defaults after application restart. Only the saved anchor association persists; the prior scale and yaw are not restored.

## Persistence and recovery

ARKit owns world-anchor persistence. Bina writes `Application Support/Bina/spatial-placement.json` inside its application container, with schema version, anchor UUID, and creation date. It does not restore from cached world coordinates. [Apple world-anchor guidance](https://developer.apple.com/documentation/visionos/tracking-points-in-world-space)

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

This prototype does not request camera, hand, plane, or scene-reconstruction data. World tracking itself does not require user authorization; support and session validity are still checked. See [platform capabilities](platform-capabilities.md).

## Device acceptance checklist

Record each case as pass, fail, or unassessed, with reproduction steps for failures.

| Case | Expected observation |
| --- | --- |
| First launch and placement | Controls become usable only with active tracking; the placeholder appears at the requested heading and offsets. |
| Local character load | Status reports success and Columbina replaces the placeholder at the same placement, scale, and heading. |
| Missing or invalid local model | Status reports failure; the placeholder remains usable and retry does not reset placement. |
| Character visual review | Check the static pose, face, hair, eye covering, clothing, feet, texture completeness, and transparency from several angles. Record material differences and performance. |
| Movement and head tilt | The placeholder remains at its world anchor rather than following head movement; its upright orientation is maintained. |
| Scale and yaw | Changes are visible immediately while the anchor stays fixed. Next-placement settings do not move the current anchor. |
| Repeated entry/exit | Scene and tracking restart without duplicate content or a stale visible placeholder. |
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

Current character-integration verification recorded on 2026-10-29:

| Check | Recorded result |
| --- | --- |
| Device and Simulator SDK builds | Passed; both built app bundles contain the 26,560,949-byte local character asset. The device build is not a headset run. |
| visionOS Simulator 27.0 tests | 34 passed, zero failures, zero skips: the previous 27 cases plus six bounds-normalization cases and one actual bundled-asset load case. |
| Actual RealityKit asset loading | Passed with normalized 1.6-meter reference height, feet placement, centering, and nonempty geometry. |
| ARKit USD validation | `usdchecker --arkit` passed. |
| Authoring preview | Front render inspected; this is not a headset render or proof of exact material fidelity. |
| Device Hub interaction | GUI discovery, opening, simulator start, and reading succeeded; app-content clicking was unavailable, so the interactive visual walkthrough is incomplete. |
| Columbina on a physical headset | Not yet tested. Earlier user-reported spatial checks used the placeholder. |

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
Placement distance / foot offset / height / yaw:
Build result:
Automated test result / result bundle:
Device checklist results:
Anchor restoration attempts / successes / observed times:
Visible drift or discontinuities:
Interruption and recovery behavior:
Remaining limitations / next experiment:
```

Record the first device result here or in a linked follow-up record. Keep failed and unassessed cases visible; do not mark the full character or companion milestones complete from this experiment alone.

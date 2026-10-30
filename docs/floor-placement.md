# Floor Placement

Status: the first floor-placement workflow is implemented. Live classified floor detection, a frozen landing preview, explicit confirmation, sole alignment, and manual-height fallback are present. Physical-room acceptance remains pending on the user's visionOS 27.2 headset. Updated: 2026-10-31.

## User workflow

1. Enter the mixed immersive space and allow the system's world-sensing permission request.
2. Select **Stand on floor**, then slowly inspect the floor ahead. Wait for the stable-floor status.
3. Face the intended direction, choose a horizontal distance, and select **Preview floor placement**. The target uses the horizontal component of the current headset heading; it is not an eye-gaze or pinch raycast.
4. Inspect the green disk in the room. It marks the calibrated foot range plus a small margin. White foot symbols indicate facing direction; they are illustrative rather than a rendering of the character's feet.
5. Select **Confirm placement and save**. The character moves only after a valid world anchor has been added and the replacement association has been saved.
6. Adjust height or heading. Grounded placements pivot around the same sole contact point. Exit/reenter or relaunch to exercise the existing world-anchor restoration path.

A preview remains at its captured world location while the user looks around. **Preview again** captures a new target; **Cancel preview** leaves the saved placement untouched. Changing distance, character height, heading, or placement mode cancels the pending preview. Loading a replacement character also cancels it.

If permission is denied, the provider is unsupported, or no suitable floor covers the target, select **Manual height**. The existing headset-relative height controls remain available when world tracking is valid. **Retry floor detection** creates fresh providers after a denial or failure; permission must first be allowed in system settings when required.

## Responsibility boundaries

| Module | Responsibility |
| --- | --- |
| `FloorDetection` | World-sensing authorization, horizontal plane-provider lifecycle, safe copying of mesh buffers, provider-specific events, and current-plane reconciliation. |
| `FloorSurface` | Framework-independent, immutable geometry validation, world/plane coordinate conversion, mesh containment, boundary clearance, and stability comparisons. |
| `FloorPlacement` | Live floor evidence, stability interval, candidate selection, frozen preview identity, and confirmation validity. It never creates or persists world anchors. |
| `FloorPlacementMarker` | A separate RealityKit preview entity; it never moves the currently saved character. |
| `CharacterGroundContact` | Asset-specific, one-time measurement of the imported feet and the scale/yaw correction for their contact point. |
| `SpatialPrototype` | The shared ARKit session, world tracking, character presentation, and the existing transactional anchor replacement and restoration flow. |

The mixed space runs `WorldTrackingProvider` alongside an authorized `PlaneDetectionProvider(alignments: [.horizontal])`. Plane data requires `NSWorldSensingUsageDescription` and an allowed `.worldSensing` authorization. No camera, hand, scene-reconstruction, or enterprise API is introduced. Support and authorization are checked at runtime.

Plane-provider events are filtered by provider identity. A plane failure does not itself mark world tracking failed. If the initial combined session cannot start, the controller makes one attempt with a fresh world-only session and providers, retaining manual placement and saved metadata. Stopped providers are never reused.

## Evidence and geometry rules

The first version accepts only `PlaneAnchor.surfaceClassification == .floor` and planes within three degrees of horizontal. Unknown horizontal surfaces and tables are not substituted for floors. The selected height comes from the plane equation in the current world frame; world `y == 0` is never assumed to be the floor.

ARKit's vertex and triangle buffers are copied before use. The adapter checks formats, shared CPU-readable storage, sizes, offsets, strides, index widths, and bounded counts. Packed float3 vertices are read as three scalar values, avoiding SIMD3's alignment/padding assumptions. The value model rejects invalid transforms, nonfinite or nonplanar vertices, bad indices, empty/degenerate coverage, and nonmanifold edges.

Candidate selection requires:

- An open, active immersive scene, a running world provider, and a freshly tracked device pose.
- At least 0.4 seconds of live, stable floor evidence. Stability is measured against a fixed reference snapshot, preventing cumulative small changes from being treated as stable indefinitely.
- Height changes no greater than 1 centimeter, anchor-origin changes no greater than 2 centimeters, and normal/local-axis changes no greater than 1 degree during that interval. Significant frame corrections require a fresh preview even if floor height is unchanged.
- A target 0.75–3 meters horizontally ahead and a floor 0.25–3 meters below the current headset. Sitting/standing changes the heading reference, not the measured floor height.
- Coverage for the entire calibrated foot disk plus 3 centimeters of margin, after character scaling. Checks use the triangle union and its outer/hole boundaries rather than the plane's rectangular extent. Concavities and holes cannot support a preview simply because their bounding box contains it.

When multiple eligible floor meshes overlap, the highest valid floor is selected. The character remains upright; the first version has no foot IK or independent foot rotation to match sloped or uneven terrain.

## Sole calibration and persistence

The current Columbina export separates shoe ornaments (`CharacterMaterial_19`) from exposed feet (`CharacterMaterial_00`). Before attachment or idle preparation, CPU skinning measures the imported shoe geometry and the skin within 8 centimeters of its base in the normalized 1.6-meter character frame. Their combined horizontal bounds define a conservative disk; their minimum height defines contact. Missing or invalid geometry explicitly disables calibrated floor placement for that model and leaves manual height available.

The contact correction on the presentation parent is:

```text
translation = -yawRotation(contactCenter * characterScale)
```

This keeps the same contact point under height and heading changes without moving the world anchor or editing authored joint transforms. Idle, attention, hair physics, and facial ownership are unchanged. Walking, broad cloth simulation, environment collision avoidance, and shadows are outside this increment.

Confirmed floor placements add optional `alignment: "soleContact"` to the existing schema-1 anchor record. Older records with no alignment retain their original presentation-origin semantics. Manual placements continue using that legacy origin. No automatic migration or rewrite occurs merely because a saved record is loaded. Scale and heading remain in-process preferences and still reset after app restart.

Plane identifiers, room meshes, preview transforms, and raw world coordinates are not persisted. The saved world anchor remains restoration authority. Once confirmed, a placement is not continually snapped to refinements or removed floor meshes; later plane evidence is used for the next placement. Ordinary ARKit updates to the selected world anchor still apply.

## Interruption and failure behavior

- Losing device/world tracking, scene inactivity, a plane pause/failure, or authorization revocation clears floor evidence and the unconfirmed preview. Resuming requires fresh stable evidence.
- Static planes need not emit another event after recovery, so the adapter reconciles current `allAnchors` snapshots at most twice per second while running and tracked.
- A preview is invalidated if its supporting floor disappears, changes classification, moves significantly, or no longer covers its foot disk. Small refinements do not move the frozen preview. Confirmation also requires current support within 1.5 centimeters of its captured height.
- Preview UUID, settings, session generation, current tracking, and floor support are rechecked after asynchronous anchor creation. An obsolete request removes its newly added anchor and retains the previous association.
- Adding or saving a replacement must succeed before the previous anchor is removed. A failure preserves the old saved placement; cleanup failures are reported through the existing spatial status.
- Exiting the immersive space cancels plane tasks and resets evidence. Late events cannot repopulate a stopped or replaced run. Corrupt placement metadata retains the existing explicit-reset behavior.

## Verification and device gate

Automated tests cover actual mesh containment, internal triangle edges, concavities, holes, transformed and sloped planes, malformed data, stable evidence, negative world-floor height, sitting/standing head heights, cumulative drift, frame corrections, tracking recovery, provider routing, obsolete runs/previews, settings changes, and legacy/new persistence. Imported-foot tests independently skin actual exposed feet and shoes, verify ground contact and complete disk coverage across three heights and three headings, and preserve legacy placement semantics.

All 145 tests pass on visionOS Simulator 27.0 with zero failures/skips and no reported runtime warnings. The generic visionOS device SDK build also passes with signing disabled. Both app bundles retain the four exact character resources and the world-sensing purpose string. Detailed results are recorded in the [spatial verification record](spatial-prototype.md#floor-placement-verification); local diagnostics are retained under `LocalAssets/Columbina/floor-diagnostics/`.

On the physical headset, record pass/fail/unassessed for:

| Check | Expected result |
| --- | --- |
| Permission allowed | Stable floor becomes available in a normally lit room after inspecting the floor. |
| Permission denied/revoked | Preview/confirmation are unavailable; manual height and valid saved-world placement remain usable. |
| Target coverage | A preview appears only with enough floor around the complete foot range; an unsupported target gives an actionable explanation. |
| Floor versus table | A table or unknown horizontal surface cannot be selected in place of a classified floor. |
| Sole contact | At seated and standing head heights, both feet meet the real floor. Inspect at character heights 0.4, 1.6, and 1.9 meters and several headings. |
| Preview movement | Looking or walking around leaves the pending disk fixed; re-preview captures a new location. Significant detection/frame changes cancel it. |
| Confirmation/refinement | Confirmed placement stays tied to its world anchor while the detector refines the floor; no continual resnapping occurs. |
| Interruption/re-entry | Tracking loss clears the preview; a new preview needs recovered evidence. Exit during confirmation cannot commit a stale request. |
| Saved placement compatibility | Existing manual records keep their position; newly confirmed floor placements restore through their world-anchor UUID. |
| Character regressions | Idle, attention, rear hair, eye states/blinking, and sleeve clearance remain coherent after placement, scaling, yaw, and re-entry. |

Record actual visible contact error, detection delay, anchor restoration, drift, frame cost, and sustained behavior. Simulator tests and SDK builds do not establish those sensor and comfort results.

## Platform references

- [Apple: Placing content on detected planes](https://developer.apple.com/documentation/visionos/placing-content-on-detected-planes).
- [Apple: PlaneAnchor](https://developer.apple.com/documentation/arkit/planeanchor).
- [Apple: Tracking specific points in world space](https://developer.apple.com/documentation/visionos/tracking-points-in-world-space).

The used signatures and availability were also checked against the installed XROS 27.0 ARKit Swift interface.

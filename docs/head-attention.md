# Bounded Head Attention

Status: implemented. Subsequent hair/collar feedback led to selected hair physics/collision and a rear-lock stability correction, now covered by the 95-test suite. The corrected dynamic costume still awaits headset acceptance on visionOS 27.2. Updated: 2026-10-30.

## Experience and scope

The character gently turns her neck and head toward the current device position while retaining her accepted stance and procedural idle. Device position is an approximation for the user's head location, not eye-gaze or emotion evidence. Apple demonstrates per-scene-update device queries in [Placing entities using head and device transform](https://developer.apple.com/documentation/visionos/placing-entities-using-head-and-device-transform).

The combined attention limits are 25 degrees of yaw, 12 degrees upward, and 10 degrees downward. Yaw attention fades between 55 and 80 degrees from forward; vertical attention fades between 35 and 60 degrees. Physical target distance fades between 0.45 and 0.7 meters, independent of preview scale. Targets outside those ranges lead toward neutral. A 1.5-degree angular dead zone, exponential response of 0.35 seconds when following and 0.45 seconds when returning, and a combined 30-degree-per-second angular speed limit suppress jitter and abrupt turns. Frame steps are capped at 0.1 seconds. These are initial calibration values for headset evaluation.

Feet, world placement, the accepted arm/thumb pose, and body heading remain unchanged. Attention does not rotate the whole character or move the eyeballs independently.

## Ownership and data flow

`SpatialPrototype` queries the existing running `WorldTrackingProvider` during scene updates. It passes only a fresh tracked device position to the character presentation controller. Positions are not persisted or retained as a fallback across tracking runs.

`CharacterHeadAttention` owns platform-independent angle selection and smoothing. `CharacterAttentionBinding` maps those angles into the imported neck/head parent spaces, preserving the asset's authored joint axes. The direction is measured from the reference head joint in the character's upright negative-Z-forward frame; current placement rotation and physical scale are accounted for. This avoids using an already-turned head to recalculate its own neutral target. The binding validates skeleton correspondence and parent ordering and requires the head to descend from the neck.

`CharacterIdleMotion` remains the single writer of joint transforms: reference baseline, natural stance, idle, then attention. The neck receives 35 percent of the turn; the head receives the residual quaternion so their combined rotation equals the intended character-frame turn. The natural-stance transition scales the desired target before smoothing, so blending cannot amplify the displayed turn beyond the filter's speed limit. Only those two local rotations change for attention. Per-frame filter state is excluded from SwiftUI observation.

## Preview and lifecycle contract

- The attention toggle defaults to enabled and remains available with valid idle data. Disabling it blends toward neutral while playback is running.
- Pause freezes the entire displayed pose, including attention. Toggle changes take effect on resume.
- Reference selection restores the exact imported pose and clears attention state. Returning to natural idle starts attention from neutral and blends it with the existing stance transition.
- Hidden/inactive content freezes the displayed pose and clears the held attention target. A new visible frame must supply a fresh target; the current orientation interpolates without snapping.
- Missing, invalid, very close, or rear targets lead smoothly toward neutral. Stopped tracking hides the character through the existing visibility policy.

## Verification

Eleven pure tests cover target directions, limits, dead-zone behavior, distance/cone fading, invalid inputs, smoothing, timestep handling, and speed limits through the stance transition. Five bundled tests cover actual joint-axis composition, translated/rotated/scaled placement, fixed feet and arms, pause/reference controls, source-pose restoration, missing targets, and invalid hierarchy rejection. The existing lifecycle regression now explicitly restores scene activity before simulating tracked visibility on re-entry, and asserts that a new callback cannot advance an inactive scene. The cuff regression supplies an active attention target through its sampled idle phases.

The independent final suite passed all 73 tests on visionOS Simulator 27.0, with zero failures and zero skips. Its result bundle is `/private/tmp/Bina-Head-Attention-Tests-4.xcresult`. The generic visionOS device build also passes; it is not a headset run. Both app bundles retain the exact cuff-fix model and paired pose resources.

Fifty-two actual macOS RealityRenderer captures in `LocalAssets/Columbina/attention-diagnostics/captures/` cover 13 stages from front, quarter, rear-quarter, and full-body views. They include neutral, left/right, high/low, combined extreme, near/rear, paused, and missing-target samples. Reviewed close-ups show coherent head/neck turns without obvious new gross hair/collar intersections. The images retain the existing purple irises and clothing material policy. The exact USDZ and pose file are unchanged from the cuff-fix pair.

Subsequent headset feedback found hair/collar intersections and rigid accessory motion despite those desktop checks. The earlier pose snapshots did not establish collision clearance. A selected spring stage now drives four hair chains after attention, with calibrated neck/collar/body proxies and actual skinned-mesh regressions. It does not replay the entire source MMD simulation or add garment cloth. The [secondary-motion contract](secondary-motion.md) records the correction, controls, asset profile, source audit, and remaining headset acceptance.

`runtime-verification.json` records zero ankle world-position component change, zero joint-transform error while paused, byte-identical paused captures despite a changed target, and exact source-pose restoration. `attention-comparison.png` and `head-extremes-contact.png` assemble actual captures without retouching or generated content.

Desktop checks do not establish headset naturalness, comfort, or sustained performance. On visionOS 27.2, test lateral movement, sitting/standing, passing behind, close approach, the attention toggle, pause/reference, and scene exit/re-entry. Inspect the neck, collar, hair, eyes, fixed feet, and cuffs throughout.

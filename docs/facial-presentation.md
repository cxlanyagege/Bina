# Facial Presentation and Eye States

Status: the two eye states, natural blinking, restrained expression previews, and mouth previews are implemented. The facial baseline passed 115 simulator tests, a supplemental per-frame ownership check, and both SDK builds. Native renders were reviewed, and subsequent user feedback found the headset preview natural. Detailed transition/rendering checks and sustained performance remain open. Updated: 2026-10-31.

## Scope and portrayal

The user specified two normal eye states:

| State | Cover | Eyelids | Automatic blinking |
| --- | --- | --- | --- |
| `coveredClosed` | Visible, with the source texture transparency | Fully closed | Inactive |
| `uncoveredOpen` | Hidden | Open except during a blink | Enabled by default |

The initial state is `coveredClosed`. Eye-state selection is a manual preview preference, retained within the running character controller. This increment does not infer emotions, select eye states from dialogue, track eye gaze, or provide speech synchronization.

Eye-state transitions take approximately 0.4 seconds. During uncovering, the cover fades out before the lids open. Reversing the transition closes the lids before the cover fades in. The two stages share reversible progress, so rapid changes cannot produce open eyes behind a visible cover during normal playback. The material's source opacity texture remains intact.

Uncovered blinking uses a 0.07-second close, 0.04-second hold, and 0.13-second reopening. Automatic intervals vary between 3.2 and 6.2 seconds after the preceding blink; time starts accumulating only after the uncovered state is reached. An explicit preview can trigger a blink with automatic blinking disabled. Hidden and paused scenes do not advance timers. Individual updates are capped at 0.05 seconds, preventing a long interruption from fast-forwarding an entire transition.

Expression previews provide neutral, gentle smile, and curiosity. Calibrated maximum weights are 0.22 for the smile, 0.15 for its brow support, and 0.18 for brow raising. Expression intent blends over 0.3 seconds. Mouth previews provide relaxed, open, and round shapes, with 0.35 maximum weights and 0.18-second blending. These are manual channel checks, not lip sync or proof of an emotional system.

## Asset findings and repair

The retained Blender file contains 60 source shape keys. The preceding USDZ stored 60 blend-shape names but only seven target prims: sanitizing the original names caused identifier collisions. RealityKit imported no usable facial mapping from that package. A count of source keys therefore did not establish runtime facial capability.

`scripts/prepare-columbina-face.py` reads the retained authoring file and the exact delivered USDZ. It first requires an exact match of source basis coordinates and delivered vertex order, then rebuilds 60 sparse targets named `Face_0000` through `Face_0059`. The runtime profile selects six semantic controls:

| Semantic channel | Delivered target | Use |
| --- | --- | --- |
| `blink` | `Face_0021` | Full bilateral eyelid closure |
| `smile` | `Face_0005` | Restrained mouth-corner expression |
| `browSmile` | `Face_0040` | Gentle brow support |
| `browRaise` | `Face_0043` | Small curiosity preview |
| `mouthOpen` | `Face_0000` | Open-mouth preview |
| `mouthRound` | `Face_0004` | Rounded-mouth preview |

The repair modifies facial targets and binding names without re-exporting the mesh, skeleton, skin weights, UVs, base normals, materials, or textures. The authoring tool compares non-facial USD attributes before and after the edit and verifies packaged texture hashes. Facial targets currently carry positional offsets, using the existing surface shading data. Additional shading corrections would need independent visual validation.

The eye-cover material is `CharacterMaterial_12`. Only its opacity scale changes; the original continuous-alpha texture and culling policy are preserved. Iris/eye/face materials retain the preceding opaque-eye correction. The existing skeleton still has 790 unique imported joints, and the accepted stance and hair physics parameters retain their numeric values.

The facial candidate is SHA-256 `5b35b6406d1f2962ca1860a947ab969e70b27e72d12965d2a5835fbd454cc806`. The original model and its paired pose/physics metadata are retained at `LocalAssets/Columbina/facial-audit/before-face/`. Original model SHA-256: `778f6a594d04ef61e7fd733682dd1ed2755b0631c61546678e7843c76029eb22`.

Four generated resources must be bundled together and remain excluded from Git:

- `Bina/Resources/Characters/Columbina.usdz`
- `Bina/Resources/Characters/ColumbinaIdlePose.json`
- `Bina/Resources/Characters/ColumbinaPhysics.json`
- `Bina/Resources/Characters/ColumbinaFace.json`

The pose and physics JSONs are re-paired to the repaired model hash. Their settings and matrices are unchanged. A clean checkout without local assets remains buildable and reports unavailable character features.

## Runtime ownership

`CharacterFacePlayback` contains framework-independent intent, blink scheduling, reversible eye-state progress, and bounded scalar channels. Its randomness is seedable for repeatable tests. It has no system-clock, rendering, network, or storage dependency.

`CharacterFaceProfile` validates the schema, exact model hash, complete semantic mapping, unique safe names, and the source-specific covering material. Hashing/decoding runs away from the main actor. `CharacterFaceBinding` validates the imported weight sets and binds each semantic name exactly once. It owns blend weights and the cover material only; it never changes skeletal transforms.

`CharacterFaceMotion` exposes observable preview preferences and keeps per-frame state outside SwiftUI observation. `CharacterIdleMotion` remains the sole skeleton writer and gates face advancement through the existing playing/visible lifecycle. `CharacterAsset` prepares face data as a separate failure boundary after primary motion and hair physics. Missing, mismatched, or invalid facial resources retain the loaded character and primary motion with a localized explanation.

Imported facial weights and materials are captured before any preview change. Invalid replacement cannot displace a working binding. A valid replacement and any fallback restore that original baseline, rather than treating the last preview as a new reference. Material updates preserve the optional hair-debug opacity component and all other material owners.

## Controls and lifecycle

The control window adds a facial group with eye-state selection, natural-blink preference, expression selection, mouth-shape selection, blink preview, and reset. Facial controls are available during normal playback. Blink controls are inactive in the covered state.

- Pause freezes the displayed facial state, including an in-progress transition or blink.
- Hidden/inactive content freezes facial time; visibility recovery advances from the retained state with a bounded step.
- Reference mode restores the exact imported weights and cover material, clears pending blink events, and freezes presentation. This diagnostic view can show the original source's open eyes behind its cover; it is not a third normal eye state.
- Returning to natural playback starts from the canonical covered/closed state and smoothly reacquires the selected facial preferences. Body stance continues its existing reference-to-natural transition independently.
- Reset restores covered/closed, neutral, relaxed mouth, and automatic blinking through the normal transition rules.
- A facial failure restores source appearance and leaves body idle, head attention, and hair physics available.

## Reproduce the local repair

Generate a separate candidate with Blender's bundled USD Python modules:

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --disable-autoexec --offline-mode \
  --python scripts/prepare-columbina-face.py -- \
  --authoring LocalAssets/Columbina/sleeve-fix/Columbina.blend \
  --input Bina/Resources/Characters/Columbina.usdz \
  --output LocalAssets/Columbina/facial-candidate/Columbina.usdz
```

The tool produces the candidate USDZ, face profile, re-paired pose/physics metadata, and preparation report in the output directory. Validate the native import, visual results, and all regressions before promoting the four files together. Keep the previous resources as a local backup. The tool rejects repairing a model in place and rejects an authoring file with incompatible basis coordinates.

The installed Blender used for this repair is 5.2.3 LTS. It reads the retained 4.5.15 authoring file; it does not re-run that version's mesh/material exporter. Runtime APIs were checked against the installed XROS 27.0 SDK and [Apple's blend-shape component documentation](https://developer.apple.com/documentation/realitykit/blendshapeweightscomponent).

## Verification and remaining acceptance

The automated coverage includes seeded blink timing, transition reversals, cover/lid ordering, frame-rate variation, invalid/delayed time, expression/mouth bounds, metadata validation, exact model pairing, actual imported channels, material preservation, pause/hide/reference, failed replacement, fallback, and independent body/hair ownership.

Native RealityRenderer captures under `LocalAssets/Columbina/facial-audit/candidate-captures/` cover nine states from four views: covered/closed, uncovered/open, complete blink, gentle smile, curiosity, open mouth, round mouth, covered return, and source reference. Front, quarter, above, and below views have been reviewed for eye-layer exposure and covering behavior. These are macOS captures, not headset screenshots.

All 115 tests pass with zero failures/skips and no runtime warnings at `/private/tmp/Bina-Facial-States-Tests.xcresult`: the preceding 95 plus nine playback, four profile, and seven actual-asset facial cases. A strengthened ownership test checks every frame of opacity transitions and passes separately at `/private/tmp/Bina-Facial-Ownership-Tests.xcresult`. The generic visionOS device SDK build passes with signing disabled. Both app bundles contain all four exact source resources. Local fingerprints, invariants, native capture counts, and acceptance limits are recorded in `LocalAssets/Columbina/facial-audit/verification-manifest.json`.

The user subsequently found the facial preview natural on the reported visionOS 27.2 headset. Record a preliminary naturalness pass; no detailed blink/transition checklist, frame costs, or sustained measurements accompanied it. The earlier rear-hair report remains a separately scoped preliminary stability pass.

The user next chose [real-floor placement](floor-placement.md) before walking animations. The documented text-personality and confirmed-memory loop remains future work before speech playback and synchronized mouth motion. Facial preview labels do not replace that behavior or emotional-continuity design.

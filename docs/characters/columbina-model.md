# Columbina Model Intake

Status: selected hair physics, two eye states, natural blinking, restrained facial previews, and calibrated real-floor placement are implemented. Facial targets were repaired without changing base geometry, skinning, or material data; paired metadata hashes were updated. The user reported preliminary hair stability and natural facial presentation. Floor acceptance and sustained performance remain open. Reviewed: 2026-10-31.

## Source and identity

The local candidate is the Columbina model archive linked from the model-download component of the [official Luna VIII Bilibili activity page](https://www.bilibili.com/blackboard/era/pwamk8wIpoip4GFN.html).

- Distributor archive: [YlYG9eCBu8.zip](https://i0.hdslb.com/bfs/activity-plat/static/8201/10377/11850/20260629/d32c2bb79f59192cb072d7bf79b61c6d/YlYG9eCBu8.zip).
- Local original archive: `LocalAssets/Columbina/source.zip`.
- Verified SHA-256: `27203622f2b2828fb9191b9a1b2494a97fc75a24fdba2ddf72b8999d8f8c59c8`.
- Extracted source: `LocalAssets/Columbina/source/`; original filenames and the supplied notice are retained locally.
- The notice credits miHoYo for the model and GuanHai for modification, identifying the modifier's Bilibili account as GuanghaiZi.

The original activity-page HTML was checked for the archive URL. Third-party indexes were discovery leads, not the downloaded source. A later distribution date does not establish which model details changed from earlier packages.

## Inspected contents

The archive contains one PMX model, a supplied readme, and texture/support files for the body, face, hair, eyes, eye covering, dress, shoes, toon shading, and sphere effects. Original PMX and notice filenames remain unchanged in the local source directory.

No separate second PMX file was found for open-eye versus closed-eye presentation. The same retained mesh now supports covered/closed and uncovered/open states through a repaired eyelid target and source-cover opacity. See [facial presentation](../facial-presentation.md) for verified mappings and remaining visual/device checks.

## Supplied notice

The original notice decodes as UTF-8 with an optional byte-order mark. It is retained unchanged with the source package. Its stated conditions include:

- Physics improvements and fixes to skin weights, expressions, and related bugs are allowed.
- Recoloring, moderate outfit changes, and adding sphere or toon effects are allowed.
- Redistribution and taking components to modify other models are prohibited.
- Commercial use is prohibited.
- Adult-only works, extreme religious propaganda, graphic horror or grotesque material, and personal attacks are prohibited uses.
- The notice attributes responsibility for misuse to the user and reserves final interpretation to miHoYo.

This is an intake summary of the supplied notice, not a legal conclusion or a grant of application-distribution rights. Keep the original notice and attribution alongside local working files.

## Local-only asset policy

This candidate is being evaluated for a private, local Vision Pro preview. Neither public application distribution nor redistribution of the original or converted model is part of this intake.

`LocalAssets/` and the runtime outputs `Columbina.usdz`, `ColumbinaIdlePose.json`, `ColumbinaPhysics.json`, and `ColumbinaFace.json` under `Bina/Resources/Characters/` are excluded by `.gitignore`. Do not commit or upload the archive, textures, authoring project, converted character asset, or derived metadata. A clone without the USDZ retains the placeholder. Invalid pose data retains a static model; invalid physics or face data retains primary motion and reports that feature separately.

Revisit the asset source and applicable permissions before any public build, shared asset package, or commercial distribution. The repository's own software license does not extend to this model.

## Conversion and current evidence

The selected tools are Blender 4.5.15 and MMD Tools 4.5.14, obtained for isolated conversion work with package checksums verified during preparation. References: [Blender 4.5 LTS](https://www.blender.org/download/lts/4-5/), [MMD Tools extension](https://extensions.blender.org/add-ons/mmd-tools/), and [MMD Tools upstream](https://github.com/MMD-Blender/blender_mmd_tools).

PMX import and USDZ export completed with Y-up orientation and a 180-degree source-front correction. Materials were deliberately adapted to portable Principled/USD Preview Surface shading; original toon and sphere effects were not retained. The importer warned that shared `toon01.bmp` was missing; that reference is unused after adaptation.

The facially repaired runtime file is 26,931,049 bytes, SHA-256 `5b35b6406d1f2962ca1860a947ab969e70b27e72d12965d2a5835fbd454cc806`. Its paired `ColumbinaIdlePose.json` is 3,754 bytes, SHA-256 `f1ab63a2840d6f39122910451e92ce7bcd6a5816d6d696e35bf838d6c3c31558`; only the embedded model hash and serialization changed. The original conversion records 55,943 vertices, 80,794 triangles, 26 materials, 10 textures, one armature, and 60 source shape keys. The facial repair preserves non-facial USD data and texture bytes, rebuilds unique facial targets, and validates six semantic channels. Original pre-face resources remain in `LocalAssets/Columbina/facial-audit/before-face/`.

The initial conversion passed `usdchecker --arkit`, device and Simulator SDK builds, and bundled RealityKit loading checks for normalized height, feet placement, centering, and nonempty geometry. Its authoring project, front preview, and report remain in `LocalAssets/Columbina/converted/`. The historical eye-corrected static asset and working files remain in `LocalAssets/Columbina/eye-fix/`; that asset is 26,560,808 bytes with SHA-256 `18f7c1e1c13abb985a595747283ccc431add227219c4e967eac4c06f37a308ce`. The pre-eye-correction asset remains at `LocalAssets/Columbina/diagnostics/eyes-before.usdz`. The first skeletal export and pose remain in `LocalAssets/Columbina/idle/`; the cuff correction, authoring project, and conversion report are in `LocalAssets/Columbina/sleeve-fix/`. Every USDZ entry's uncompressed payload is byte-identical between those two skeletal exports; archive metadata changes the container hash. The cuff correction changes pose metadata, not mesh, weights, textures, or materials.

The application loads the asset asynchronously and normalizes its reference pose to 1.6 meters through parent entities, preserving authored rig transforms. The placeholder is replaced only after a valid model loads. Calibrated joint deltas and small upper-body motion are independent of saved world placement. [Floor placement](../floor-placement.md) additionally measures shoe ornaments (material 19) and exposed foot skin (material 00) before attachment/idle, then corrects the presentation parent around their sole contact point. It does not rewrite the four asset files. Older manual placements retain their original pivot.

### Eye material correction

Physical headset testing found that eyes appeared correctly from above, became white at eye level, and exposed internal star-shaped geometry from below. The converter had connected texture alpha whenever Blender reported four image channels, including RGB images with no transparency. RealityKit consequently imported the six eye and face materials (`09`, `10`, `11`, `13`, `20`, and `21`) as transparent, allowing their overlapping surfaces to sort incorrectly.

The converter now respects disabled image alpha and caches the actual pixel alpha range, omitting the opacity connection for fully opaque textures. The six affected materials import as opaque. Genuine partial transparency in the eye covering and hair detail remains continuous, without a cutout threshold; the source shoe opacity is also retained. The original source, texture pixels, geometry, skin weights, and default shape-key values are unchanged.

The new RealityKit opacity regression failed all six material assertions against the previous asset and passes against the correction. Historical eye-correction validation passed all 36 simulator tests with no failures or skips, `usdchecker --arkit`, and the generic visionOS device build. At that stage both built app bundles contained the 26,560,808-byte eye-corrected static asset. RealityKit represents the shoe opacity through base-color tint alpha `0.75`, with opacity scale `1` and no opacity texture; the regression checks their product.

Matching-angle offscreen RealityRenderer captures on macOS 27.2 reproduce the old white eyes and exposed star geometry, while the correction retains both purple irises from above, level, and below without changing culling. Before and after captures are retained in `LocalAssets/Columbina/diagnostics/realitykit-before/` and `realitykit-after/`, with `eye-comparison.png` in the diagnostics directory. These renders verify RealityKit behavior on macOS; subsequent user-reported headset feedback is recorded below. Exact material fidelity, animation, facial control, physics, voice, and memory remain outside this result.

### Clothing culling correction

Further headset testing found that front clothing disappeared when viewed from behind, and rear clothing disappeared from the front. The source PMX marks 25 of its 26 materials as double-sided, including sleeves, skirt, shoulder cape, and cloak. Shoes (`CharacterMaterial_19`) are the single-sided exception. The exported USD mesh has `doubleSided = true`, but the local RealityKit import produced PBR materials with `.back` culling. This is an observed result for this asset and import path, not a claim about every RealityKit importer.

`CharacterAsset.configureMaterials(in:)` now visits the loaded hierarchy and restores the source policy: `.none` for double-sided surfaces and `.back` for shoes. It changes only PBR face culling; opacity, other material properties, and non-PBR materials remain intact. Apple documents that [PBR face culling defaults to `.back`](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial/faceculling-swift.property) and that [`.none` disables polygon culling](https://developer.apple.com/documentation/realitykit/materialparametertypes/faceculling/none). Rendering both sides adds work, so headset performance still requires checking.

The culling correction itself required no USD re-export or duplicated geometry; the eye-corrected static asset was unchanged at that stage. An initial all-surfaces culling probe logged 26 assertion failures before the runtime adjustment, confirming the imported `.back` settings. Its stalled log-finalization process was stopped, so it is not a completed test report. The independent historical run passed all 39 simulator tests with no failures or skips, including two synthetic policy tests and the bundled sidedness regression that preserves the source shoe exception. The generic visionOS device build also passed.

Thirty macOS RealityRenderer captures compare the exact runtime helper against the previous culling settings. Full-model front and rear views retain the clothing, while an isolated cloak view changes from thin edges to the complete blue cape when viewed from its reverse side. Captures are retained under `LocalAssets/Columbina/diagnostics/cloth-culling/{before,after}/{all,cape07,skirt18}/`. Isolated mesh-part captures are diagnostics only; the application retains the complete original geometry. The accompanying `LocalAssets/Columbina/diagnostics/cloth-culling/eyes-after/{above,level,below}.png` captures retain both purple irises with the culling correction applied.

The cloth diagnostics directory also retains `cloth-comparison.png`, `diagnostics.json`, and the linked runtime-helper snapshot `CharacterAsset.verified.swift` for reviewing and reproducing the comparison.

### Preliminary headset appearance feedback

On 2026-10-30, after the material corrections, the user reported that the character looked acceptable to the naked eye for now. Record this as a preliminary static-appearance pass. The user subsequently reported visionOS 27.2 while authorizing the natural-stance and idle increment. No detailed view checklist, app revision, frame-time measurements, or sustained-session results accompanied the appearance feedback. That feedback predates the new skeleton and motion implementation; moving-clothing intersections and motion quality require a new headset check. See [milestones](../milestones.md#next-increment-natural-stance-and-minimal-idle).

### Unique skeleton paths and paired pose data

The earlier export stored 790 joint paths but only 514 unique paths: non-ASCII source names collapsed into repeated underscore identifiers. In the inspected RealityKit import, the visible mesh loaded while the runtime joint and skeleton arrays were empty. Static appearance therefore did not establish usable skinning.

`prepare_skeleton` now assigns deterministic `Joint_0000`-style ASCII leaf names through a temporary rename pass before export, and names the armature `ColumbinaSkeleton`. The local conversion report retains the original-name mapping. The final generated resource imports with 790 runtime joints and one skeletal pose in the actual macOS RealityKit diagnostic. The original PMX, source notice, geometry, and material policy remain the source of this local conversion.

`scripts/columbina_idle_pose.py` evaluates the reference and relaxed poses through Blender before exporting parent-local matrix deltas. The selected stance lowers each upper arm an additional 26 degrees, retains the reference elbow extension, and adducts each thumb base 6 degrees toward the index/palm. Only four local joint deltas are required: the two upper arms and two thumb bases. Evaluation confirmed zero movement across 10,870 lower-body vertices and exact restoration of all authoring pose bases before the reference asset is exported.

The paired JSON records schema version 1, four column-major joint-delta matrices, spine/chest/neck/head roles, fixed ankle/toe joints, and the exact exported model hash. `CharacterIdlePose` validates the schema and verifies the model SHA-256 before `CharacterIdleMotion` uses the data. Keep the USDZ and JSON from the same conversion together when building or replacing local assets.

### Natural stance and idle preview

`CharacterIdleMotion` derives every frame from the imported reference joint transforms. It composes the four natural-stance deltas with that baseline, then adds restrained spine, chest, neck, and head rotations. `CharacterIdlePlayback` uses an 11-second periodic cycle containing a 5.5-second breathing wave, with a smooth 0.9-second return from the reference pose. The pelvis, leg joints, model pivot, and world anchor are not animated by this controller.

The preview supports pausing in the current pose, resuming from the same phase, showing the exact imported reference pose, and returning smoothly to the natural stance. Hidden or inactive characters retain their phase; delayed frames are clamped rather than fast-forwarding primary motion. Attention, selected hair dynamics, and blinking were added separately after this original idle increment. Walking, lip sync, and broad garment cloth remain unimplemented.

The preceding idle implementation passed all 56 simulator tests with no failures or skips; its historical result bundle is `Bina-Idle-Tests-2.xcresult` in the local temporary directory. The generic visionOS device build also passed. That run predates the cuff calibration and geometric regression.

Thirty historical macOS RealityKit captures under `LocalAssets/Columbina/idle-diagnostics/` exercise the actual runtime implementation: the reference pose and natural idle at 0, 2.75, 6, and 11 seconds, each from front, quarter, side, rear, eye, and cloth views. They preserve purple irises and two-sided clothing, but their broad views missed the cuff penetration subsequently reported on the headset. `runtime-verification.json` records zero fixed ankle/toe world-position movement and zero model-world-matrix change in every sampled pose. Pausing and hiding preserve the pose and phase, resuming advances again, and reference restoration is exact. Returning toward the natural stance starts within approximately `2e-7` of the reference and then advances smoothly.

The same directory retains `stance-comparison.png`, the native validation script, runtime source copies, and `diagnostics.json` with asset fingerprints. The comparison uses identical crops and resizing of actual captures, with no retouching or generated imagery.

### Cuff penetration correction

The user subsequently found posture and motion generally acceptable but reported severe clothing penetration, especially at the cuffs. It remained visible when idle was paused. Matching wrist close-ups reproduced thumb skin crossing the main sleeve surface. Export and runtime audits found matching mesh positions and skin influences; this was a pose-clearance defect. The earlier additional 7-degree elbow bend increased strict hand/cuff triangle crossings from 32 pairs per side in the reference pose to 228 per side. Removing that bend and gently adducting the thumbs reduces the settled natural pose to zero crossings on both sides.

`scripts/columbina_cuff_clearance.py` now checks evaluated hand surfaces (`CharacterMaterial_00`, `_14`, `_15`) against the nearby main sleeve (`_16`) during pose authoring and rejects intersecting natural poses. The metadata records reference and natural counts. `BundledCuffClearanceTests` independently skins the actual RealityKit mesh using its imported influences and bind matrices, then checks both hands at 0, 2.75, 6, and 11 seconds. Strict crossings exclude coincident endpoints; sampled vertex distance is diagnostic, not a guaranteed minimum surface separation. This asset-specific check does not implement cloth physics or cover every costume layer.

The source reference pose intentionally remains exact and retains its tiny original thumb intersection. During the short return from reference, that source detail can remain briefly visible; the settled natural pose removes it. Wrist-relative desktop captures in `LocalAssets/Columbina/sleeve-diagnostics/` compare the old stance, candidate calibrations, paused idle peak, and intermediate return poses from six directions for each hand. The six-degree thumb candidate also removes the small white sliver beside the crescent cuff decoration in the reviewed front views.

At the cuff-correction stage, the final generated pair passed `usdchecker --arkit`, all 57 visionOS Simulator 27.0 tests with zero failures or skips, and the generic visionOS device build. The result bundle is `/private/tmp/Bina-Cuff-Fix-Tests.xcresult`. Both built app bundles contained the exact current USDZ and paired JSON with the hashes recorded above. Eighty-four final-resource RealityRenderer close-ups in `sleeve-diagnostics/production-final/` are byte-identical to the reviewed six-degree-thumb candidate captures: seven stages, two wrists, and six angles. These are desktop renderer and automated checks.

On 2026-10-30, the user tested the corrected build and reported that the cuff issue was resolved. Record this as a user-reported cuff-fix pass on the previously reported visionOS 27.2 headset. No detailed angle checklist, installed revision, full system build, or performance measurements accompanied that feedback. Broader costume behavior, scene comfort, and sustained performance remain open; this result does not validate head attention or other future motion.

### Bounded head attention

The attention increment adds restrained neck/head turns toward fresh device positions without changing or re-exporting either local resource. Character-frame rotations are converted into the imported parent-local axes; feet, root placement, and accepted arm/thumb deltas stay fixed. Pause freezes the whole displayed pose, and reference selection restores the imported pose exactly. The preview has an attention toggle enabled by default.

All 73 simulator tests and both SDK builds pass, including imported-rig attention checks and the cuff geometry regression with an active target. Fifty-two actual native RealityKit captures under `LocalAssets/Columbina/attention-diagnostics/captures/` cover 13 target/control stages from four views. Reviewed face, neck, hair, and collar views show no obvious new gross intersections; pause and reference restoration errors are zero. These results do not replace a fresh headset attention review. Limits, lifecycle rules, result bundle, and reproduction evidence are recorded in [Head attention](../head-attention.md).

Subsequent headset testing found hair/collar penetration and rigid accessory behavior. Dynamic costume acceptance has not passed. A read-only audit found 607 rigid bodies and 956 spring joints in the original PMX. All 593 physics-linked source bone names map to the exported rig inventory, including 83 dynamically linked bones influencing the source hair layers. The current conversion excludes the importer's separate physics category and the application does not simulate those constraints. The original data is retained locally; [Secondary motion](../secondary-motion.md) records the inventory, coordinate-conversion requirements, native cloth API probe, and proposed hair/collar validation task.

### Selected hair physics and collision

Four selected chains now use spring dynamics: side locks `Joint_0054...0056` and `Joint_0057...0059`, and upper rear locks `Joint_0070...0077` and `Joint_0107...0114`. The solver changes only those 22 local rotations, sharing one skeletal driver between both hair layers. Eight capsule proxies follow the primary neck/chest pose. The model, skin weights, textures, material policy, and accepted arm/thumb deltas are unchanged; this is not a full replay of the original MMD physics graph.

The current local `ColumbinaPhysics.json` is 4,151 bytes, SHA-256 `592b517b008c4ccb4728796986ac498ee5e4d9ae5005da46ed558caeafa18098`. Facial preparation updated its model hash and serialization while retaining all numerical settings. Bundle all four resources. Older physics profiles need the rear-chain angle and speed limits. Missing/invalid physics data retains primary motion and reports the unavailable feature. The [secondary-motion contract](../secondary-motion.md#reproduce-the-local-profile) records generation, controls, reset policy, and device checks.

The user subsequently confirmed improved cheek locks but reported rear-hair twitching during head turns and model rotation. Rear locks now evaluate rest direction/twist against the complete primary pose, with 0.65-radian shape and 2-radian/second motion limits. The solver uses explicit quaternion identity, avoids converting contact correction into velocity, and preserves history through ordinary yaw.

The preceding rear-lock correction passed 95 tests at `/private/tmp/Bina-Rear-Hair-Regression-Tests-3.xcresult`. Imported-mesh checks cover both hair layers against selected collar surfaces at seven settled targets; motion tests cover 30/60/90/120 FPS and heading changes. Its normalized sweep had zero selected-region crossings across 24 samples. The user subsequently reported no major issue in that headset check, a preliminary stability pass without sustained performance measurements. The current facial suite retains all those automated regressions.

### Facial targets, eye states, and previews

The original export had 60 facial names but only seven target prims because of sanitized-name collisions; RealityKit imported no usable facial mapping. The local repair reconstructs 60 unique sparse targets from the retained basis-matched Blender mesh. Base geometry, skeleton, weights, UVs, materials, and texture bytes remain unchanged. The face profile selects eyelid closure, smile, two brow controls, and two mouth controls.

Normal playback defaults to visible eye covering with closed eyes. Uncovering fades the covering before opening the eyes; covering reverses that order. Only the uncovered state schedules natural blinking. Neutral, gentle smile, curiosity, and relaxed/open/round mouth previews are manually selectable. Pause, visibility gating, exact source reference, replacement, and fallback are covered independently from skeleton ownership.

`ColumbinaFace.json` is 349 bytes, SHA-256 `4543fb045c0c4ec06c97691188b975e18d44a8d613f8698fd785ae7c7ae8363f`. The facial baseline passed all 115 tests at `/private/tmp/Bina-Facial-States-Tests.xcresult`; a supplemental per-frame ownership test passed at `/private/tmp/Bina-Facial-Ownership-Tests.xcresult`. Native renders cover nine facial states from four views. Subsequent user feedback found the preview natural, without detailed performance measurements. See [facial presentation](../facial-presentation.md) for preparation, channels, lifecycle, and remaining acceptance. Facial preview labels do not implement emotion, conversation, or lip sync.

## Reproduce locally

Use the retained original PMX file and a locally obtained MMD Tools directory. Replace the example executable and input paths below; no original binary or texture is supplied by the repository.

```sh
/path/to/blender --background --factory-startup --disable-autoexec --offline-mode \
  --python-exit-code 1 --python scripts/convert-columbina.py -- \
  --source /path/to/original-model.pmx --addon /path/to/mmd_tools \
  --output Bina/Resources/Characters/Columbina.usdz \
  --working LocalAssets/Columbina/sleeve-fix --turn-around
```

The converter writes the base USDZ and `ColumbinaIdlePose.json`. Generate its paired physics profile using the [physics preparation instructions](../secondary-motion.md#reproduce-the-local-profile), then run the [facial repair](../facial-presentation.md#reproduce-the-local-repair) and bundle the four repaired resources together. On the headset, compare natural/reference poses, pause/resume, both eye states, blinking, mouth/expression previews, and moving costume surfaces. Continue checking textures, scale, upright orientation, fixed feet, re-entry, and frame stability. Record differences rather than treating adapted shading as an exact reproduction.

See the [character asset specification](../character-assets.md) for the general asset contract and the [character profile](columbina.md) for portrayal requirements.

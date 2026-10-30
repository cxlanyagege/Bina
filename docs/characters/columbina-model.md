# Columbina Model Intake

Status: the user found posture and motion generally acceptable and confirmed that the calibrated pose resolved the reported cuff penetration on visionOS 27.2. It passes all 57 simulator tests, visionOS SDK builds, USD validation, and actual macOS RealityKit close-up checks. Broader costume validation and measured performance remain open. Reviewed: 2026-10-30.

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

No separate second PMX file was found for open-eye versus closed-eye presentation. Eye controls, morph behavior, skeleton quality, and texture interpretation still need authoring and runtime inspection; filenames alone do not establish those capabilities.

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

`LocalAssets/` and the runtime outputs `Bina/Resources/Characters/Columbina.usdz` and `ColumbinaIdlePose.json` are excluded by `.gitignore`. Do not commit or upload the archive, extracted textures, editable authoring project, converted character asset, or derived pose data. The application source and this metadata document remain separate from those local assets. A clone without the local USDZ reports a missing asset and retains the placeholder. A valid static model can still load if motion preparation fails; the application reports the motion error separately.

Revisit the asset source and applicable permissions before any public build, shared asset package, or commercial distribution. The repository's own software license does not extend to this model.

## Conversion and current evidence

The selected tools are Blender 4.5.15 and MMD Tools 4.5.14, obtained for isolated conversion work with package checksums verified during preparation. References: [Blender 4.5 LTS](https://www.blender.org/download/lts/4-5/), [MMD Tools extension](https://extensions.blender.org/add-ons/mmd-tools/), and [MMD Tools upstream](https://github.com/MMD-Blender/blender_mmd_tools).

PMX import and USDZ export completed with Y-up orientation and a 180-degree source-front correction. Materials were deliberately adapted to portable Principled/USD Preview Surface shading; original toon and sphere effects were not retained. The importer warned that shared `toon01.bmp` was missing; that reference is unused after adaptation.

The current runtime file is 26,565,047 bytes, with verified SHA-256 `778f6a594d04ef61e7fd733682dd1ed2755b0631c61546678e7843c76029eb22`. Its paired `ColumbinaIdlePose.json` is 3,753 bytes, with SHA-256 `2c664448b0bd0ff6f2da5cdcb4ee01f98db3ea5774dd96966628e3dacc17358c`; the JSON embeds the exact model SHA-256. The conversion report records 55,943 vertices, 80,794 triangles, 26 materials, 10 packaged textures, one armature, and 60 source shape keys. Rig and shape inventory alone is not proof of runtime control.

The initial conversion passed `usdchecker --arkit`, device and Simulator SDK builds, and bundled RealityKit loading checks for normalized height, feet placement, centering, and nonempty geometry. Its authoring project, front preview, and report remain in `LocalAssets/Columbina/converted/`. The historical eye-corrected static asset and working files remain in `LocalAssets/Columbina/eye-fix/`; that asset is 26,560,808 bytes with SHA-256 `18f7c1e1c13abb985a595747283ccc431add227219c4e967eac4c06f37a308ce`. The pre-eye-correction asset remains at `LocalAssets/Columbina/diagnostics/eyes-before.usdz`. The first skeletal export and pose remain in `LocalAssets/Columbina/idle/`; the cuff correction, authoring project, and conversion report are in `LocalAssets/Columbina/sleeve-fix/`. Every USDZ entry's uncompressed payload is byte-identical between those two skeletal exports; archive metadata changes the container hash. The cuff correction changes pose metadata, not mesh, weights, textures, or materials.

The application loads the asset asynchronously and normalizes its reference pose to 1.6 meters through parent entities, preserving authored rig transforms. The placeholder is replaced only after a valid model loads. The current increment applies calibrated joint deltas and small upper-body motion independently of the model pivot and saved world placement.

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

The preview supports pausing in the current pose, resuming from the same phase, showing the exact imported reference pose, and returning smoothly to the natural stance. Hidden or inactive characters retain their phase; delayed frames are clamped rather than fast-forwarding the pose. Walking, automatic user-directed attention, blinking, lip sync, and hair/clothing physics are not implemented by this increment.

The preceding idle implementation passed all 56 simulator tests with no failures or skips; its historical result bundle is `Bina-Idle-Tests-2.xcresult` in the local temporary directory. The generic visionOS device build also passed. That run predates the cuff calibration and geometric regression.

Thirty historical macOS RealityKit captures under `LocalAssets/Columbina/idle-diagnostics/` exercise the actual runtime implementation: the reference pose and natural idle at 0, 2.75, 6, and 11 seconds, each from front, quarter, side, rear, eye, and cloth views. They preserve purple irises and two-sided clothing, but their broad views missed the cuff penetration subsequently reported on the headset. `runtime-verification.json` records zero fixed ankle/toe world-position movement and zero model-world-matrix change in every sampled pose. Pausing and hiding preserve the pose and phase, resuming advances again, and reference restoration is exact. Returning toward the natural stance starts within approximately `2e-7` of the reference and then advances smoothly.

The same directory retains `stance-comparison.png`, the native validation script, runtime source copies, and `diagnostics.json` with asset fingerprints. The comparison uses identical crops and resizing of actual captures, with no retouching or generated imagery.

### Cuff penetration correction

The user subsequently found posture and motion generally acceptable but reported severe clothing penetration, especially at the cuffs. It remained visible when idle was paused. Matching wrist close-ups reproduced thumb skin crossing the main sleeve surface. Export and runtime audits found matching mesh positions and skin influences; this was a pose-clearance defect. The earlier additional 7-degree elbow bend increased strict hand/cuff triangle crossings from 32 pairs per side in the reference pose to 228 per side. Removing that bend and gently adducting the thumbs reduces the settled natural pose to zero crossings on both sides.

`scripts/columbina_cuff_clearance.py` now checks evaluated hand surfaces (`CharacterMaterial_00`, `_14`, `_15`) against the nearby main sleeve (`_16`) during pose authoring and rejects intersecting natural poses. The metadata records reference and natural counts. `BundledCuffClearanceTests` independently skins the actual RealityKit mesh using its imported influences and bind matrices, then checks both hands at 0, 2.75, 6, and 11 seconds. Strict crossings exclude coincident endpoints; sampled vertex distance is diagnostic, not a guaranteed minimum surface separation. This asset-specific check does not implement cloth physics or cover every costume layer.

The source reference pose intentionally remains exact and retains its tiny original thumb intersection. During the short return from reference, that source detail can remain briefly visible; the settled natural pose removes it. Wrist-relative desktop captures in `LocalAssets/Columbina/sleeve-diagnostics/` compare the old stance, candidate calibrations, paused idle peak, and intermediate return poses from six directions for each hand. The six-degree thumb candidate also removes the small white sliver beside the crescent cuff decoration in the reviewed front views.

The final generated pair passes `usdchecker --arkit`, all 57 visionOS Simulator 27.0 tests with zero failures or skips, and the generic visionOS device build. The result bundle is `/private/tmp/Bina-Cuff-Fix-Tests.xcresult`. Both built app bundles contain the exact current USDZ and paired JSON with the hashes recorded above. Eighty-four final-resource RealityRenderer close-ups in `sleeve-diagnostics/production-final/` are byte-identical to the reviewed six-degree-thumb candidate captures: seven stages, two wrists, and six angles. These are desktop renderer and automated checks.

On 2026-10-30, the user tested the corrected build and reported that the cuff issue was resolved. Record this as a user-reported cuff-fix pass on the previously reported visionOS 27.2 headset. No detailed angle checklist, installed revision, full system build, or performance measurements accompanied that feedback. Broader costume behavior, scene comfort, and sustained performance remain open; this result does not validate head attention or other future motion.

## Reproduce locally

Use the retained original PMX file and a locally obtained MMD Tools directory. Replace the example executable and input paths below; no original binary or texture is supplied by the repository.

```sh
/path/to/blender --background --factory-startup --disable-autoexec --offline-mode \
  --python-exit-code 1 --python scripts/convert-columbina.py -- \
  --source /path/to/original-model.pmx --addon /path/to/mmd_tools \
  --output Bina/Resources/Characters/Columbina.usdz \
  --working LocalAssets/Columbina/sleeve-fix --turn-around
```

The converter also writes `ColumbinaIdlePose.json` beside the USDZ. Bundle both outputs. Headset testing should compare the natural and reference poses, pause and resume the idle, inspect sleeves, skirt, shoulder cape, and cloak during movement, and check the eye covering, hair detail, and shoes for preserved transparency. Continue checking identity, complete textures, scale, upright orientation, fixed feet, scene re-entry, and frame stability. Record material or costume differences rather than treating adapted shading as an exact reproduction.

See the [character asset specification](../character-assets.md) for the general asset contract and the [character profile](columbina.md) for portrayal requirements.

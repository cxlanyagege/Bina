# Columbina Model Intake

Status: both corrections pass all 39 tests, visionOS SDK builds, and matching-angle RealityKit render comparisons; the asset passes USD validation. The user reported a preliminary headset visual pass on 2026-10-30. Motion and measured performance remain open. Reviewed: 2026-10-30.

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

`LocalAssets/` and the runtime output `Bina/Resources/Characters/Columbina.usdz` are excluded by `.gitignore`. Do not commit or upload the archive, extracted textures, editable authoring project, or converted character asset. The application source and this metadata document remain separate from those local assets. A clone without the local USDZ reports a missing asset and retains the placeholder.

Revisit the asset source and applicable permissions before any public build, shared asset package, or commercial distribution. The repository's own software license does not extend to this model.

## Conversion and current evidence

The selected tools are Blender 4.5.15 and MMD Tools 4.5.14, obtained for isolated conversion work with package checksums verified during preparation. References: [Blender 4.5 LTS](https://www.blender.org/download/lts/4-5/), [MMD Tools extension](https://extensions.blender.org/add-ons/mmd-tools/), and [MMD Tools upstream](https://github.com/MMD-Blender/blender_mmd_tools).

PMX import and USDZ export completed with Y-up orientation and a 180-degree source-front correction. Materials were deliberately adapted to portable Principled/USD Preview Surface shading; original toon and sphere effects were not retained. The importer warned that shared `toon01.bmp` was missing; that reference is unused after adaptation.

The corrected runtime file is 26,560,808 bytes, with verified SHA-256 `18f7c1e1c13abb985a595747283ccc431add227219c4e967eac4c06f37a308ce`. The conversion report records 55,943 vertices, 80,794 triangles, 26 materials, 10 packaged textures, one armature, and 60 source shape keys. Rig and shape inventory is not proof of working facial control or animation.

The initial conversion passed `usdchecker --arkit`, device and Simulator SDK builds, and bundled RealityKit loading checks for normalized height, feet placement, centering, and nonempty geometry. Its authoring project, front preview, and report remain unchanged in `LocalAssets/Columbina/converted/`. Corrected working files are in `LocalAssets/Columbina/eye-fix/`; the previous runtime asset is retained as `LocalAssets/Columbina/diagnostics/eyes-before.usdz`.

The application loads the asset asynchronously and normalizes it to a 1.6-meter reference through parent entities, preserving authored rig transforms. Existing world placement remains unchanged; the placeholder is replaced only after a valid model loads. The current scope is a static source pose.

### Eye material correction

Physical headset testing found that eyes appeared correctly from above, became white at eye level, and exposed internal star-shaped geometry from below. The converter had connected texture alpha whenever Blender reported four image channels, including RGB images with no transparency. RealityKit consequently imported the six eye and face materials (`09`, `10`, `11`, `13`, `20`, and `21`) as transparent, allowing their overlapping surfaces to sort incorrectly.

The converter now respects disabled image alpha and caches the actual pixel alpha range, omitting the opacity connection for fully opaque textures. The six affected materials import as opaque. Genuine partial transparency in the eye covering and hair detail remains continuous, without a cutout threshold; the source shoe opacity is also retained. The original source, texture pixels, geometry, skin weights, and default shape-key values are unchanged.

The new RealityKit opacity regression failed all six material assertions against the previous asset and passes against the correction. Eye-correction validation passed all 36 simulator tests with no failures or skips, `usdchecker --arkit`, and the generic visionOS device build. Both built app bundles contain the corrected asset with the byte count and hash recorded above. RealityKit represents the shoe opacity through base-color tint alpha `0.75`, with opacity scale `1` and no opacity texture; the regression checks their product.

Matching-angle offscreen RealityRenderer captures on macOS 27.2 reproduce the old white eyes and exposed star geometry, while the correction retains both purple irises from above, level, and below without changing culling. Before and after captures are retained in `LocalAssets/Columbina/diagnostics/realitykit-before/` and `realitykit-after/`, with `eye-comparison.png` in the diagnostics directory. These renders verify RealityKit behavior on macOS; subsequent user-reported headset feedback is recorded below. Exact material fidelity, animation, facial control, physics, voice, and memory remain outside this result.

### Clothing culling correction

Further headset testing found that front clothing disappeared when viewed from behind, and rear clothing disappeared from the front. The source PMX marks 25 of its 26 materials as double-sided, including sleeves, skirt, shoulder cape, and cloak. Shoes (`CharacterMaterial_19`) are the single-sided exception. The exported USD mesh has `doubleSided = true`, but the local RealityKit import produced PBR materials with `.back` culling. This is an observed result for this asset and import path, not a claim about every RealityKit importer.

`CharacterAsset.configureMaterials(in:)` now visits the loaded hierarchy and restores the source policy: `.none` for double-sided surfaces and `.back` for shoes. It changes only PBR face culling; opacity, other material properties, and non-PBR materials remain intact. Apple documents that [PBR face culling defaults to `.back`](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial/faceculling-swift.property) and that [`.none` disables polygon culling](https://developer.apple.com/documentation/realitykit/materialparametertypes/faceculling/none). Rendering both sides adds work, so headset performance still requires checking.

This correction requires no USD re-export or duplicated geometry; the runtime file and hash above are unchanged. An initial all-surfaces culling probe logged 26 assertion failures before the runtime adjustment, confirming the imported `.back` settings. Its stalled log-finalization process was stopped, so it is not a completed test report. The independent final run passes all 39 simulator tests with no failures or skips, including two synthetic policy tests and the bundled sidedness regression that preserves the source shoe exception. The generic visionOS device build also passes.

Thirty macOS RealityRenderer captures compare the exact runtime helper against the previous culling settings. Full-model front and rear views retain the clothing, while an isolated cloak view changes from thin edges to the complete blue cape when viewed from its reverse side. Captures are retained under `LocalAssets/Columbina/diagnostics/cloth-culling/{before,after}/{all,cape07,skirt18}/`. Isolated mesh-part captures are diagnostics only; the application retains the complete original geometry. The accompanying `LocalAssets/Columbina/diagnostics/cloth-culling/eyes-after/{above,level,below}.png` captures retain both purple irises with the culling correction applied.

The cloth diagnostics directory also retains `cloth-comparison.png`, `diagnostics.json`, and the linked runtime-helper snapshot `CharacterAsset.verified.swift` for reviewing and reproducing the comparison.

### Preliminary headset appearance feedback

On 2026-10-30, after the material corrections, the user reported that the character looked acceptable to the naked eye for now. Record this as a preliminary static-appearance pass. No detailed view checklist, headset system version, app revision, frame-time measurements, or sustained-session results accompanied the feedback. Skeleton deformation, facial controls, natural stance, idle motion, and moving-clothing intersections still require validation. The next proposed increment is recorded in [milestones](../milestones.md#next-increment-natural-stance-and-minimal-idle).

## Reproduce locally

Use the retained original PMX file and a locally obtained MMD Tools directory. Replace the example executable and input paths below; no original binary or texture is supplied by the repository.

```sh
/path/to/blender --background --factory-startup --disable-autoexec --offline-mode \
  --python-exit-code 1 --python scripts/convert-columbina.py -- \
  --source /path/to/original-model.pmx --addon /path/to/mmd_tools \
  --output Bina/Resources/Characters/Columbina.usdz \
  --working LocalAssets/Columbina/eye-fix --turn-around
```

Headset retesting should compare above, level, and below eye views; inspect sleeves, skirt, shoulder cape, and cloak from both sides; and check the eye covering, hair detail, and shoes for preserved transparency. Continue checking identity, complete textures, scale, upright orientation, feet placement, and frame stability. Record material or costume differences rather than treating adapted shading as an exact reproduction.

See the [character asset specification](../character-assets.md) for the general asset contract and the [character profile](columbina.md) for portrayal requirements.

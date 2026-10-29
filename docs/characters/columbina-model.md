# Columbina Model Intake

Status: local USDZ conversion, ARKit USD validation, actual RealityKit loading, and SDK builds pass; headset appearance is unverified. Reviewed: 2026-10-29.

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

The runtime file is 26,560,949 bytes, with verified SHA-256 `d81049672cd4136bcdea985257b2d556d0f0ed46c98324881b74a54820e3aeaf`. The conversion report records 55,943 vertices, 80,794 triangles, 26 materials, 10 packaged textures, one armature, and 60 source shape keys. Rig and shape inventory is not proof of working facial control or animation.

`usdchecker --arkit` passed, and the front authoring preview was visually inspected. The editable project, `preview.png`, and `conversion-report.json` remain in `LocalAssets/Columbina/converted/`. Device and Simulator SDK builds pass; 34 simulator tests pass, including actual bundled RealityKit loading with normalized height, feet placement, centering, and nonempty geometry. Both built app bundles contain the local asset. No headset appearance, exact material fidelity, animation, facial control, physics, voice, or memory result is claimed.

The application loads the asset asynchronously and normalizes it to a 1.6-meter reference through parent entities, preserving authored rig transforms. Existing world placement remains unchanged; the placeholder is replaced only after a valid model loads. The current scope is a static source pose.

## Reproduce locally

Use the retained original PMX file and a locally obtained MMD Tools directory. Replace the example executable and input paths below; no original binary or texture is supplied by the repository.

```sh
/path/to/blender --background --factory-startup --disable-autoexec --offline-mode \
  --python-exit-code 1 --python scripts/convert-columbina.py -- \
  --source /path/to/original-model.pmx --addon /path/to/mmd_tools \
  --output Bina/Resources/Characters/Columbina.usdz \
  --working LocalAssets/Columbina/converted --turn-around
```

First device acceptance should check identity, complete textures, scale, upright orientation, feet placement, face and eye covering, transparency, and appearance from several angles. Record material or costume differences rather than treating adapted shading as an exact reproduction.

See the [character asset specification](../character-assets.md) for the general asset contract and the [character profile](columbina.md) for portrayal requirements.

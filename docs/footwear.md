# Footwear and Sole Contact

Status: water heels and a calibrated barefoot stance are implemented. The 2026-11-01 correction replaces runtime mesh regeneration with native import of an authored barefoot layer; see the [investigation and verification](footwear-mesh-investigation.md). The user clarified both forms and reported the Xcode/Simulator upgrade to 27.2 on 2026-10-31. The earlier headset feedback found no major issues, a preliminary appearance/contact pass that predates this correction. Detailed recovery, contact-error, and sustained-performance measurements remain open.

## Forms and controls

The character appearance group offers two forms:

| Form | Presentation | Ground contact |
| --- | --- | --- |
| Water heels | Original water spheres and surrounding heel decoration remain visible; original foot stance is retained. | Imported heel geometry and exposed feet define the contact disk. |
| Barefoot | Water-heel geometry is removed from the displayed mesh. Body textures and ankle decoration remain. A fixed ankle/forefoot calibration lowers the heel while retaining a level forefoot. | The visible foot skin in the calibrated pose defines contact; hidden heel geometry is excluded. |

The default is water heels. Footwear selection is retained in the running character controller through immersive exit/re-entry. Like existing appearance preferences, it resets after process restart and does not change the saved placement schema.

Selection is available during natural playback and disabled during pause, reference comparison, or a pending placement transaction. Pausing retains the entire current pose and footwear. Reference comparison shows the exact imported pose with its original water heels; returning to natural playback immediately restores the selected foot form while the existing upper-body transition proceeds. The reference display does not overwrite the selected preference.

Switching cancels any unconfirmed floor preview. For a sole-aligned placement, the current contact point is corrected around the same world-anchor location through scale and heading changes. Legacy/manual records retain their water-heel origin; an explicit barefoot selection adds the difference between the two contact corrections, keeping the existing contact point. Returning to water heels restores the original presentation offset. No anchor is created, moved, or saved by a footwear change.

The height slider continues to scale the 1.6-meter source character. Removing the heels naturally lowers the body by the calibrated contact-height difference; this feature does not rescale the body to compensate for shoe height.

## Asset and pose contract

`CharacterFootwearAsset` imports the authored barefoot layer through `Entity(contentsOf:)`. `CharacterFootwear` accepts that native mesh and measures both contact values before attachment to a presentation parent. It retains the original mesh for exact restoration. The barefoot variant excludes every part using `CharacterMaterial_19`, located by material name rather than assuming its array index. This removes the complete water-heel geometry and its renderer shadow. Setting material opacity to zero alone left a visible shadow in the native diagnostic.

The runtime never reconstructs the imported mesh through `MeshResource.generate(from:)`. That path triggered Simulator renderer exits even with unmodified imported contents; public index validation and copying did not resolve it. The exact internal cause and the earlier passing run's trigger conditions remain unproved. Native import retains ownership of the skinning and morph data required by the renderer.

The local `ColumbinaBarefoot.usdc` layer references its sibling `Columbina.usdz`. Authoring removes 13,472 heel triangles, retains 67,322 triangles, remaps face-varying normals/UVs and material-subset face indices, and leaves points, skinning, skeleton, named facial targets, materials, and textures unchanged. The empty heel subset retains its original material binding so native import preserves all 26 material slots while producing only 25 geometry parts. No texture copy or second full USDZ is needed. The current binary layer is 5,812,856 bytes.

`ColumbinaFootwear.json` pairs the layer's SHA-256 with the exact source model hash. Decoding and file hashing run off the main actor before import. Binding checks joint names, skeleton data, retained part identities/counts, material slots, and named facial mappings. Numeric facial channel positions from independently imported mappings are not treated as semantic identity. Current facial weights and material state remain owned by their existing controllers.

The current source uses deforming ankle joints `Joint_0017` and `Joint_0033`, with forefoot children `Joint_0018` and `Joint_0034`. A 28-degree character-frame ankle rotation and matching reverse forefoot rotation calibrate the barefoot stance. Rotation is converted into each original parent frame, leaving translations, scales, knees, and other joints unchanged. These source-specific roles and angles require review if the model is replaced. This is a fixed stance calibration, not terrain-following foot IK or walking.

During preparation, the imported joint pose is restored with `defer` after measuring the two contact values. Contact measurement includes the exposed skin near the foot base; the barefoot measurement excludes the heel material. Current normalized measurements are:

| Form | Contact center in meters | Conservative radius in meters |
| --- | --- | --- |
| Water heels | Approximately `(0, 0, -0.162226)` | `0.126108` |
| Barefoot | Approximately `(0, 0.045782, -0.202219)` | `0.112822` |

These are geometry values before presentation correction and the floor workflow's 3-centimeter margin. They do not measure real-room tracking accuracy. Independent skinning checks compare both heel and forefoot against the calibrated sole plane.

## Runtime ownership and failure handling

`CharacterIdleMotion` remains the single runtime skeleton writer. `CharacterFootwear.apply` composes fixed foot rotations into that owner's array and switches the mesh only when needed. It does not write runtime joint transforms or advance animation time. Upper-body idle, attention, selected hair dynamics, and face playback retain their existing stages and clocks.

Footwear mesh updates preserve the current material array and facial/debug components. The imported variant's skeleton and named facial mapping are checked before accepting the binding. `CharacterAsset` treats footwear preparation as an independent failure boundary: missing, damaged, or mismatched resources and invalid bindings retain the original heels, primary idle, attention, hair, and face capabilities and show a localized explanation. Grounded placement can use the original heel-contact measurement when footwear preparation is unavailable.

`SpatialPrototype` owns contact correction and preview invalidation. It updates the contact pivot after explicit form/reference changes and after a runtime footwear failure. The floor preview's existing identity/settings checks continue to reject an obsolete confirmation.

Both native mesh resources are retained for the loaded character. There is no runtime mesh rebuild or new sensing provider. The original USDZ, pose JSON, physics JSON, and face JSON are unchanged. The additional barefoot layer and footwear metadata are required for form selection; both are ignored by Git under the same character-use boundary.

## Reproduce the native variant

After preparing the four matching base resources, generate the layer beside the original USDZ. Replace the Blender executable below with the installed location. This command does not re-export Blender geometry or overwrite the source package.

```sh
/path/to/blender --background --factory-startup --disable-autoexec --offline-mode \
  --python-exit-code 1 --python scripts/prepare-columbina-footwear.py -- \
  --input Bina/Resources/Characters/Columbina.usdz \
  --output Bina/Resources/Characters/ColumbinaBarefoot.usdc
```

The script also writes `ColumbinaFootwear.json`. It verifies the material partition and source geometry, rejects unsupported indexed/animated face attributes, and checks that all unrelated scene attributes and relationships remain unchanged. Keep the layer, its metadata, and original USDZ together in the built resource directory. Regenerate the pair after any source-model change.

Run its synthetic USD regression tests through the same Python environment:

```sh
/path/to/blender --background --factory-startup --disable-autoexec --offline-mode \
  --python-exit-code 1 --python scripts/tests/test_prepare_columbina_footwear.py
```

## Verification

Automated coverage exercises complete heel removal, retained mesh attributes and named facial targets, current materials/weights, independent heel/forefoot contact, both forms at three heights and three headings, fixed rotations through playback, pause/reference/hidden behavior, invalid preparation, primary-motion fallback, preview invalidation, and saved-anchor compatibility.

The 2026-10-31 run passed all 151 tests with zero failures/skips and no reported runtime warnings at `/private/tmp/Bina-Footwear-Full-27_2.xcresult`. The generic visionOS device SDK build also passed with signing disabled. Both app bundles retained the exact four original resources. The toolchain was Xcode 27.2 (27B52), XROS SDK 27.2, and visionOS Simulator 27.2 (24N120), UUID `1BEDF9CF-615D-4096-9C28-33AF40FEEFB4`. That build's application minimum was 27.0; the current [deployment policy](platform-capabilities.md#local-project-baseline) requires 27.2. On 2026-11-01, replaying the preserved binaries produced 137 passes and 14 process kills. The historical pass remains valid but did not establish mesh-regeneration reliability. Current correction results are recorded in the [investigation](footwear-mesh-investigation.md); the [spatial verification record](spatial-prototype.md#footwear-verification) retains the original delivery evidence.

Local diagnostics under `LocalAssets/Columbina/footwear-diagnostics/` retain candidate geometry, native side/front/rear/above comparisons, production-controller captures, and summarized verification. Desktop rendering verifies the selected pipeline, not headset appearance or sustained performance.

On the user's visionOS 27.2 headset, check both forms at a conversational distance and close to the floor. Inspect heel/forefoot contact, complete water-heel removal, ankle decoration deformation, scale/yaw, pause/reference transitions, re-entry, eye states/blinking, rear hair, and frame stability. Floor classification, recentering, restoration, and actual contact error remain part of the [floor acceptance gate](floor-placement.md#verification-and-device-gate).

After this delivery, the user reported no major issues in the headset check. Treat this as a preliminary pass for the latest foot-form/contact presentation. No itemized checklist, contact-error measurements, tested revision, or sustained runtime data accompanied the report; it does not establish all floor-permission, interruption, or room-recovery cases.

The native-import correction requires a new headset check of both forms, eye states/blinking, hair, reference transitions, and ground contact. Earlier headset feedback does not validate this changed loading path.

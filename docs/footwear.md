# Footwear and Sole Contact

Status: water heels and a calibrated barefoot stance are implemented. The user clarified both forms and reported the Xcode/Simulator upgrade to 27.2 on 2026-10-31. Subsequent headset feedback found no major issues, a preliminary appearance/contact pass. Detailed recovery, contact-error, and sustained-performance measurements remain open.

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

`CharacterFootwear` prepares the two in-memory mesh variants and their contact values before attachment to a presentation parent. It retains the original mesh for exact restoration. The barefoot variant excludes every part using `CharacterMaterial_19`, located by material name rather than assuming its array index. This removes the complete water-heel geometry and its renderer shadow. Setting material opacity to zero alone left a visible shadow in the native diagnostic.

Retained triangle indices are validated and re-encoded into independent buffers before mesh generation. Imported buffer views can retain offsets that fail visionOS 27.2's cross-process mesh validation when reused after removing a part. Material slots, retained vertex attributes, facial target offsets, skeleton hierarchy, and inverse-bind/rest transforms are preserved. The generated mesh may enumerate facial channels in a different order; group identity and channel names are the binding contract. Numeric weight indices from independently generated mappings are not compared as semantic identity.

The current source uses deforming ankle joints `Joint_0017` and `Joint_0033`, with forefoot children `Joint_0018` and `Joint_0034`. A 28-degree character-frame ankle rotation and matching reverse forefoot rotation calibrate the barefoot stance. Rotation is converted into each original parent frame, leaving translations, scales, knees, and other joints unchanged. These source-specific roles and angles require review if the model is replaced. This is a fixed stance calibration, not terrain-following foot IK or walking.

During preparation, the imported joint pose is restored with `defer` after measuring the two contact values. Contact measurement includes the exposed skin near the foot base; the barefoot measurement excludes the heel material. Current normalized measurements are:

| Form | Contact center in meters | Conservative radius in meters |
| --- | --- | --- |
| Water heels | Approximately `(0, 0, -0.162226)` | `0.126108` |
| Barefoot | Approximately `(0, 0.045782, -0.202219)` | `0.112822` |

These are geometry values before presentation correction and the floor workflow's 3-centimeter margin. They do not measure real-room tracking accuracy. Independent skinning checks compare both heel and forefoot against the calibrated sole plane.

## Runtime ownership and failure handling

`CharacterIdleMotion` remains the single runtime skeleton writer. `CharacterFootwear.apply` composes fixed foot rotations into that owner's array and switches the mesh only when needed. It does not write runtime joint transforms or advance animation time. Upper-body idle, attention, selected hair dynamics, and face playback retain their existing stages and clocks.

Footwear mesh updates preserve the current material array and facial/debug components. The generated mesh's skeleton and named facial mapping are checked before accepting the binding. `CharacterAsset` treats footwear preparation as an independent failure boundary: an invalid binding retains the original heels, primary idle, attention, hair, and face capabilities and shows a localized explanation. Grounded placement can use the original heel-contact measurement when footwear preparation is unavailable.

`SpatialPrototype` owns contact correction and preview invalidation. It updates the contact pivot after explicit form/reference changes and after a runtime footwear failure. The floor preview's existing identity/settings checks continue to reject an obsolete confirmation.

Both mesh resources are cached for the loaded character. There is no per-frame mesh rebuild or new sensing provider. The original USDZ, pose JSON, physics JSON, and face JSON are unchanged; no fifth character resource is required.

## Verification

Automated coverage exercises complete heel removal, retained mesh attributes and named facial targets, current materials/weights, independent heel/forefoot contact, both forms at three heights and three headings, fixed rotations through playback, pause/reference/hidden behavior, invalid preparation, primary-motion fallback, preview invalidation, and saved-anchor compatibility.

All 151 tests pass with zero failures/skips and no reported runtime warnings at `/private/tmp/Bina-Footwear-Full-27_2.xcresult`. The generic visionOS device SDK build also passes with signing disabled. Both app bundles retain the exact four original resources. The toolchain is Xcode 27.2 (27B52), XROS SDK 27.2, and visionOS Simulator 27.2 (24N120), UUID `1BEDF9CF-615D-4096-9C28-33AF40FEEFB4`. The application minimum remains 27.0. See the [spatial verification record](spatial-prototype.md#footwear-verification) for scope and remaining device acceptance.

Local diagnostics under `LocalAssets/Columbina/footwear-diagnostics/` retain candidate geometry, native side/front/rear/above comparisons, production-controller captures, and summarized verification. Desktop rendering verifies the selected pipeline, not headset appearance or sustained performance.

On the user's visionOS 27.2 headset, check both forms at a conversational distance and close to the floor. Inspect heel/forefoot contact, complete water-heel removal, ankle decoration deformation, scale/yaw, pause/reference transitions, re-entry, eye states/blinking, rear hair, and frame stability. Floor classification, recentering, restoration, and actual contact error remain part of the [floor acceptance gate](floor-placement.md#verification-and-device-gate).

After this delivery, the user reported no major issues in the headset check. Treat this as a preliminary pass for the latest foot-form/contact presentation. No itemized checklist, contact-error measurements, tested revision, or sustained runtime data accompanied the report; it does not establish all floor-permission, interruption, or room-recovery cases.

The mesh generation API was checked against the installed 27.2 interfaces and [Apple's MeshResource documentation](https://developer.apple.com/documentation/realitykit/meshresource).

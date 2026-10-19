# Character Asset Specification

Status: proposed; no character asset, conversion pipeline, or animation controller is implemented.
Last reviewed: 2026-10-19.

## Purpose and first candidate

Bina is a companion and interactive character whose presence should feel coherent over time.
The selected first character is Columbina from Genshin Impact, preserving her original character identity and personality.
Model intake is pending: no model file or package provenance has been supplied, and availability, terms, and technical compatibility remain unverified.
The visual asset contract is separate from the format used to represent and load the character's persona.
The user's OpenClaw identity and personality files have been reviewed in the [Columbina profile](characters/columbina.md); they are not an assumed Bina runtime format.
See [product vision](product-vision.md) and [memory and emotion](memory-and-emotion.md) for portrayal and continuity requirements.

The first asset should support stable placement, conversation, interruption, and pointing at one tracked object.
Walking, sitting on arbitrary furniture, and dynamic clothing simulation are later capabilities.
A simple temporary rig may isolate technical problems during validation; it does not replace the intended first character.

## Terms used in this document

| Term | Meaning |
| --- | --- |
| Mesh | The visible surfaces of the body, clothing, hair, and accessories. |
| Skeleton and skinning | Joints and their influence on mesh deformation. |
| Control rig | Authoring controls used to pose the skeleton; not necessarily exported. |
| Blend shape | A stored mesh deformation mixed by a weight, often used for the face. |
| Viseme | A visible mouth pose associated with speech sounds. |
| Retargeting | Adapting animation from another skeleton to the selected character. |
| Root motion | Translation or rotation carried by an animation's root. |

## Evidence and intake record

Record the following before declaring a candidate usable:

- Character name, appearance variant, original publisher, source URL, download date, and package version.
- Original filenames, format, checksum, creator attribution, included notices, and unmodified source archive location.
- Applicable terms and evidence for the intended modification, local use, redistribution, and publication contexts.
- Whether model, textures, motions, voice, and other included components have different permissions.
- Importer, authoring application, exporter, and operating-system versions used in each conversion.

The [HoYoLAB resource article](https://www.hoyolab.com/article/118389) is a source lead to inspect with the actual package.
Its substantive content and package-specific terms were not available for verification during this review.
No permission to redistribute a character in an application, publish a build, or use a particular voice is established here.
Record a specific unresolved question rather than treating a downloadable file or fan-video permission as application permission.
This is an asset intake requirement, not a legal conclusion about any particular model.

## Proposed conversion pipeline

1. Inspect the supplied archive and notices without altering the original.
2. Import a working copy into a version-pinned authoring project and inventory geometry, rigging, facial controls, and textures.
3. Normalize scale and orientation, validate deformation, and remove or bake unsupported authoring behavior deliberately.
4. Prepare minimal motion clips and a semantic mapping for face and gaze controls.
5. Export a small USD/USDZ test containing one skeletal clip and one facial deformation before converting everything.
6. Inspect the export in Reality Composer Pro, then load it in the target RealityKit application on Vision Pro.
7. Compare against authoring references, record discrepancies and measurements, and iterate.
8. Retain the editable authoring project, export settings, mapping revision, and validation results for reproducible updates.

USD/USDZ is the proposed runtime delivery route, not an assumption that a source model can be loaded unchanged.
Apple documents skeletal animation and rigging requirements in its [USD authoring guidance](https://developer.apple.com/documentation/usd/creating-usd-files-for-apple-devices).
Blender can export armatures, skinned meshes, relative shape keys, and packaged USDZ; export behavior is version-dependent.
Use the [Blender USD manual](https://docs.blender.org/manual/en/4.2/files/import_export/usd.html) as a documented baseline and verify the installed release.

The actual source format is unknown. Conditional routes include:

| Source supplied | Candidate authoring route | Must be verified |
| --- | --- | --- |
| PMX or PMD | Blender with MMD Tools, then USD export | Morph types, bone constraints, skin weights, materials, and scale. |
| FBX | A compatible Blender FBX importer, then USD export | Bind pose, animation, normals, and facial-channel preservation. |
| Native authoring project or USD | Inspect its dependencies and export directly where suitable | Runtime compatibility and completeness. |

[MMD Tools](https://github.com/MMD-Blender/blender_mmd_tools) supports PMX/PMD import, but documents physics and IK differences from MMD.
Its existence does not establish that a selected model will convert correctly.
No game extraction tooling, importer, or third-party dependency is installed as part of this proposal.

## Spatial and skeleton contract

These are proposed Bina conventions, to be confirmed by the first successful export:

- Author physical dimensions in meters; record the intended standing height explicitly.
- Normalize the delivered asset to Y up, character forward along local negative Z, with documented axis conversion.
- Put the placement origin at floor level between the feet; retain a separately identified pelvis and skeleton root.
- Keep the placement transform independent of the animated skeleton so a clip cannot move the world anchor.
- Validate transforms and bind matrices together; avoid blindly applying transforms after skinning or relying on negative scale.
- Use one deforming joint hierarchy for the first character, with stable joint paths and an explicit reference pose.
- Inventory pelvis, spine, chest, neck, head, arms, hands, legs, feet, and any available eye, finger, or accessory joints.
- Record missing capabilities rather than guessing joint correspondence from names alone.

Apple recommends one skeleton hierarchy and explicit skeleton/material bindings for interoperable assets.
See [Apple's USD guidance](https://developer.apple.com/documentation/usd/creating-usd-files-for-apple-devices).
Authoring IK controls, drivers, constraints, and plugins are not a runtime contract.
Bake the evaluated joint animation where needed, while retaining the editable rig in the authoring source.
Blender documents USD limitations including unsupported bendy bones and absolute shape keys in the cited exporter baseline.

Initially use clips with stationary placement and no unrequested root translation.
Record clip name, duration, authoring frame rate, loop boundaries, reference pose, and intended transition points.
Retarget imported motions in authoring and check shoulders, wrists, knees, feet, and costume intersections.
Runtime retargeting is optional and requires a separate feasibility test.

## Motion and facial control contract

| Priority | Capability | Acceptance intent |
| --- | --- | --- |
| Baseline | Neutral standing and subtle idle | Stable feet, restrained motion, and a seamless idle loop. |
| Baseline | Listening, speaking, acknowledgement, greeting | Distinguishable behavior with smooth entry and exit. |
| Baseline | Turn toward the user and point | Head/body direction and target reference remain coherent. |
| Baseline | Character-appropriate attention | Head and posture convey attention without changing the approved portrayal. |
| Baseline | Speech mouth movement and a few expressions | Face remains legible at conversational distance. |
| Optional | Eye gaze, blinking, fingers, walking, sitting, secondary motion | Added where appropriate to the portrayal, after baseline quality and performance pass. |

The final implementation may combine authored clips with bounded procedural adjustments.
Do not require visible eye animation when the approved portrayal intentionally keeps the eyes closed or concealed.
Use head and posture direction to convey attention in that case; do not redesign the character to satisfy a generic rig checklist.
The supplied Columbina profile allows occasional eye opening and explicitly rejects permanent blindness or mandatory permanent eye closure.
Check eyeball geometry, lid controls, and covering occlusion for that expressive capability. A prototype without it must record the limitation rather than redefining the character.
Validate expression range for amusement, curiosity, surprise, sadness, and firm disagreement; one serene face is insufficient for the source-derived portrayal.
Arbitrary target pointing needs a validated joint or IK approach; one authored pointing clip alone does not solve it.
Interruption should stop speech, release speech-related mouth weights, and blend into an appropriate listening pose.

Define semantic controls and map them to the selected asset rather than requiring specific original channel names:

| Semantic controls | Candidate representation |
| --- | --- |
| `blinkLeft`, `blinkRight` | Eyelid blend shapes or authored lid-joint poses. |
| `gazeYaw`, `gazePitch` | Eye joints or verified eye-direction morphs, with per-asset limits. |
| `mouthOpen`, `mouthClosed`, `mouthWide`, `mouthRound` | Blend-shape combinations or a jaw plus lip controls. |
| `smile`, `browRaise`, `browConcern` | Small, calibrated expression combinations. |

For each mapping, record affected mesh/joint paths, neutral values, valid ranges, and conflicting channels.
MMD supports [several morph types](https://github.com/MMD-Blender/blender_mmd_tools/blob/main/mmd_tools/core/morph.py), including bone and material controls; a morph is not automatically a USD facial blend shape.
A full standardized face channel set is optional; first prove that the available controls support convincing speech and expression.
[RealityKit blend-shape weights](https://developer.apple.com/documentation/realitykit/blendshapeweightscomponent) allow runtime facial control.
Validate names, weight ranges, and simultaneous skeleton/face animation in the actual export.
Speech mouth timing depends on the chosen speech system; test timing metadata before promising phoneme-level synchronization.
Expression requests describe visible performance, not evidence of an internal emotion or the user's emotional state.

## Materials, hair, and clothing

Treat the original look as a visual reference, not a transferable shader implementation.
Blender's USD exporter approximates supported materials; arbitrary authoring node graphs are not guaranteed to survive.
Build a small face/hair/clothing material test before polishing the full character.
[ShaderGraphMaterial](https://developer.apple.com/documentation/realitykit/shadergraphmaterial) is a candidate for reauthoring supported stylized effects.
Toon shading, outlines, face shadows, and transparency require separate RealityKit and device validation.
Compare a simple unlit appearance with a supported lit material to choose an intentional response to room lighting.
Check face readability, eye highlights, color space, normal direction, thin surfaces, and transparent hair layers.
Apple identifies texture size and layered transparency as important costs in its [USD guidance](https://developer.apple.com/documentation/usd/creating-usd-files-for-apple-devices).

MMD rigid bodies, cloth simulation, collision rules, and authoring hair physics must not be assumed to transfer through USDZ.
Start with stable skinned geometry or baked secondary motion; assess runtime secondary motion later.
Check clothing during arms-up, turns, pointing, and close viewing before adding more animation.

## On-device validation and unresolved decisions

Measure rather than invent a universal polygon, texture, or joint limit.
Record triangles, vertices, joints, material slots, texture dimensions, transparency, package size, and load time.
Measure memory, CPU/GPU frame time, and sustained behavior in the intended mixed immersive scene on the user's headset.
Include close facial viewing, full-body distance, speech plus motion, interruption, and repeated loading.
Set asset budgets only after the first representative measurement, leaving capacity for spatial sensing and audio.
Use Instruments and available RealityKit diagnostics; a desktop preview alone does not establish device acceptance.

The first candidate passes when it loads with all dependencies, has correct scale/orientation, deforms correctly,
supports the baseline controls, and meets the performance target agreed after measurement.
Retain screenshots or short recordings and a pass/fail checklist with the tested device, OS, app build, and export revision.
Log unavailable channels and material differences explicitly; choose an adaptation or another asset before promising the capability.

Open decisions: actual model package and appearance variant, source and terms, intended distribution,
standing height, voice source, available facial channels, authoring tool versions, and final visual/performance targets.

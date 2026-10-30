# Character Secondary Motion and Collision

Status: the focused hair/collar experiment and rear-lock correction are implemented. The user reported no major issue in the subsequent headset check, a preliminary stability pass. The current 115-test facial suite retains the hair regressions. Full-costume quality and sustained performance remain open; full-garment cloth remains proposed. Reviewed: 2026-10-30.

## Problem and recommendation

The user reported hair and collar penetration on the headset after head attention was added. Desktop screenshots did not establish acceptable dynamic costume behavior. That implementation sampled static accessory offsets while adding primary body/head motion. The current increment adds a selected spring-bone stage with collision response. Rendering materials retain their existing policy.

The application retains native SwiftUI/RealityKit and now has a focused secondary-motion stage for selected hair. The broader direction remains collision-aware springs for accessories, native cloth evaluation for selected garment surfaces, and weight/corrective-deformation review for fitted collar regions. This is not a guarantee of zero penetration in arbitrary poses. Validate the selected contact region on the headset before expanding the motion set.

## Verified local asset findings

A read-only audit of the original PMX, using the existing MMD Tools PMX reader, found:

| Item | Observed result |
| --- | --- |
| Original PMX SHA-256 | `9f70cf5862d675be18c40cbf64f80423274347e7f7c52d3c2e48e51639e01b8c` |
| Source bones | 742; the imported/exported rig includes 790 bones after importer helpers. |
| Rigid bodies | 607: 34 source mode-0 bone followers, 305 dynamic bodies, and 268 mode-2 bodies. |
| Shapes | 79 capsules and 528 boxes. |
| Physics joints | 956, all source spring six-degree-of-freedom joints. |
| Distinct physics-linked bones | 593, including 573 linked to dynamic modes. Every linked bone name maps to the retained exported ASCII joint-name inventory. |
| Hair skinning | Each source hair layer uses 83 dynamically linked bones; 7,707 of its 8,902 vertices have a dynamic-bone influence greater than 0.001. |
| Runtime hair materials | The conversion report maps the two source hair layers to `CharacterMaterial_22` and `_23`. Source material indices differ from runtime material indices. |

The audit is retained locally in `LocalAssets/Columbina/physics-audit/source-physics.json`. It inventories authoring data; it does not validate simulated behavior. Mode-0 bodies follow source bones and should not be interpreted as immovable world-space colliders. Raw PMX dimensions, spring constants, and collision masks cannot be copied into a different solver without coordinate, unit, and semantic conversion.

The conversion script imports only `MESH`, `ARMATURE`, and `MORPHS`. MMD Tools exposes `PHYSICS` separately. The source physical configuration remains available for conversion and calibration, but the runtime does not reproduce its complete rigid-body/joint simulation. Instead, this increment drives 22 retained hair bones with independently calibrated spring constraints. It does not attach native cloth or rigid-body components to the character.

## Platform findings

Apple now documents [native cloth simulation](https://developer.apple.com/documentation/realitykit/physics-cloth-simulation), including `ClothSimulationComponent`, `ClothBodyComponent`, `ClothColliderComponent`, and `ClothMeshResource`. [WWDC26's RealityKit session](https://developer.apple.com/videos/play/wwdc2026/279/) demonstrates cloth, collision geometry, material stiffness, and fixed particles.

The installed XROS 27.0 SDK's public `RealityFoundationCloth` module, re-exported by RealityKit, marks these APIs available from visionOS 27.0. A compile-only probe using cloth resources, simulation timesteps, target shapes, pinned particles, and a capsule collider passes for `arm64-apple-xros27.0`. The probe is retained at `LocalAssets/Columbina/physics-audit/NativeClothAPIProbe.swift`. It was not executed; no runtime compatibility, character integration, collision quality, or performance pass is implied. The user reports visionOS 27.2; device evaluation is still required. The reviewed Apple documentation retains beta labels on several cloth pages.

Apple distinguishes the cloth simulation/proxy mesh from its rendered mesh and recommends a separate proxy for quality/performance choices. Cloth visual deformation can override rendering, and ordinary rigid-body colliders are not a substitute for cloth-compatible colliders. Confirm skinning/deformer order, mesh correspondence, and scene-update ordering in an isolated experiment before attaching cloth to the existing imported character. See [ClothBodyComponent](https://developer.apple.com/documentation/realitykit/clothbodycomponent) and [ClothColliderComponent](https://developer.apple.com/documentation/realitykit/clothcollidercomponent).

[VRM's spring-bone design](https://vrm.dev/en/univrm/springbone/univrm_secondary/) is a useful precedent for hair/accessory chains with stiffness, gravity, and collider groups. It is a design reference, not a claim that a Unity/VRM runtime can be dropped into this native app or that Bina already implements VRM physics.

## Proposed division of work

| Region | Initial treatment | Reason and limitation |
| --- | --- | --- |
| Hair locks and ribbons | A selected set of retained accessory bone chains, with inertia, damping, rest-shape/length constraints, and body/collar collision proxies. | Preserves styled locks and existing skinning; requires thickness-aware contact calibration. |
| Neck, shoulders, chest, collar | Bone-following collision proxies plus inspection of local weights, reference clearance, and corrective shapes where necessary. | A fitted collar needs stable authored deformation. Physics alone cannot guarantee repair of an intersecting reference shape or an unsuitable weight map. |
| Cape, skirt, loose sleeve panels | A separate native-cloth experiment using a modest proxy mesh, pinned/targeted attachment regions, and selected body collision groups. | Broad bending surfaces benefit from cloth constraints; current multi-material skinned geometry requires selective binding or extraction rather than simulating the entire character. |

The existing two hair layers should share one physical driver. Do not simulate coincident shading layers independently and create artificial self-collisions. Preserve visual topology, UV seams, material policy, eyes, and the accepted arm/thumb pose. Physical proxy resolution and visual mesh resolution have different purposes.

## Ownership and integration contract

Extend the existing single pose-presentation owner with a secondary-motion stage. Do not add a second independent writer to `jointTransforms`.

1. Evaluate reference, natural stance, idle, and attention into the current primary pose.
2. Derive kinematic roots and body/collar collision proxies from that pose.
3. Advance selected secondary chains using a fixed timestep with bounded catch-up; apply their offsets to the same pose buffer.
4. Commit the final skeleton once. For separately simulated cloth, feed updated attachment targets/colliders into the native simulation at the appropriate before-update event and allow its designated deformer to own the selected visual surface.
5. Render after those updates using a verified ordering. Rendering updates, collision queries, and simulation callbacks must not read half-updated or stale frames.

Keep the solver state separate from asset data and RealityKit binding. An asset-specific profile should identify joints, attachment points, rest lengths, damping/stiffness, thickness, collision groups, and reset rules in normalized units. Pair it to the exact asset, validate missing joints and malformed values, and retain local-only treatment for generated character data. The first implementation needs only the selected chain and proxy data; it does not require a general engine abstraction or migration.

Pause must freeze primary and secondary motion. Reference mode must restore the exact imported pose and disable simulation influence. Hidden/inactive scenes must stop stepping; re-placement, scale changes, recentering, long interruptions, and reference transitions need explicit reset/rebase rules to avoid explosive velocity or stale contacts. A failure should retain a stable primary pose and report that secondary motion is unavailable.

For hair, testing only bone endpoints against the body is insufficient. A wide lock can intersect a collar while its endpoint remains outside; inspect segment/lock thickness and actual skinned surfaces. Begin with limited relevant collision groups rather than all-pairs self-collision across the source's 607 bodies and 956 joints. Profile actual device cost before expanding the simulated subset.

## First experiment and acceptance

The implemented scope is four hair chains: two short side locks and the upper eight joints of each long rear lock, totaling 22 controlled joints. Their descendants retain their authored local transforms and inherit those turns. The two hair rendering layers share the same skeleton driver. Eight pose-derived capsule colliders cover the neck, collar edges, shoulders, upper chest, and upper back. Hair lock radii are 0.035 meters for the side locks and 0.05 meters for the broader rear locks, calibrated against actual skinned surfaces rather than only bone centers.

`CharacterPhysicsProfile` validates bounded finite settings, unique joint assignments, schema version, and exact model SHA-256. `CharacterHairPhysics` validates skeleton topology, contiguous chains, and head-descendant accessory ownership, then rejects protected body/attention/stance joints. Missing or invalid physics data retains the already loaded character and primary motion, shows an explanation, and disables physics controls. A simulation failure also disposes debug geometry and returns to primary motion.

`SpringBonePhysics` is framework-independent math for damped Verlet integration, rest-shape attraction, length constraints, hard bend limits, optional angular-speed limits, and capsule contacts along the entire bone segment. It uses 1/120-second fixed steps with at most six steps per update. Frame gaps over 0.05 seconds reset rather than fast-forwarding. Sixteen warm-up steps resolve initial contacts before clearing velocity. A 0.25-second influence transition supports comparison; reference-to-natural blending also controls influence. Intermediate comparison blends are not collision-clearance guarantees.

Physics uses reference-height character coordinates. Translation changes over 0.02 meters and scale changes over two percent invalidate stored kinetic history; ordinary character/ancestor yaw does not. Hidden frames and tracking/session interruptions also request a reset. Pause freezes both layers of motion. Reference restores the exact imported pose and hides debug geometry. `CharacterIdleMotion` remains the only joint-transform writer; successful physics changes only selected local rotations.

The preview exposes hair physics (default enabled), physical debug geometry (default hidden), and an explicit timing snapshot. Green segments/cyan tips show the selected chains; translucent orange capsules show the collision proxies. Debug mode temporarily multiplies the model's opacity by 0.3 to expose interior chains. Hiding debug geometry, entering reference mode, or disposing the simulation restores the previous opacity component exactly. Debug changes do not advance animation time. CPU timing is a ring of the most recent 600 update costs, including binding/solver work and debug updates when enabled; it excludes GPU rendering and the rest of the app.

The current `Bina/Resources/Characters/ColumbinaPhysics.json` is 4,151 bytes, SHA-256 `592b517b008c4ccb4728796986ac498ee5e4d9ae5005da46ed558caeafa18098`, and remains ignored by Git. Subsequent [facial preparation](facial-presentation.md) re-paired its model hash and serialization to the repaired USDZ; all numerical physics settings remain unchanged. That repair preserves base geometry, skinning, materials, and textures. Regenerate older profiles to include both rear-chain limits. The optional fields retain schema-1 decoding compatibility; older profiles omit these protections.

## Rear-lock stability correction

After the initial headset test, the user confirmed improved cheek locks but reported rear hair jerking upward during head turns and character rotation. Static clearance and sparse mesh samples did not test motion continuity or accumulated orientation.

- The previous bend interpolation started at `simd_quatf()`, which is a zero quaternion rather than identity. The solver now uses explicit identity and reapplies the hard bend limit after contact projection.
- Position projection previously became implicit velocity on the next Verlet step. The solver now retains predicted tangential velocity separately, so contact correction does not inject an impulse.
- Rear-lock rest targets followed already simulated ancestors, allowing bend and twist to accumulate through eight controlled joints and their descendants. Optional `maximumChainAngle` now evaluates rest direction and twist against the complete primary pose. Both rear locks use 0.65 radians; side locks retain their local-parent guide.
- Optional `maximumAngularSpeed` bounds rear-lock particle turns and stored tangential motion at 2 radians per second. Shape limits take precedence if contacts cannot all be satisfied. The two side locks retain their existing profile settings.
- The former placement-matrix comparison reset physics on every five-degree heading-slider step. Rotation of the character-local simulation frame now preserves history; relocation, scaling, interruptions, and reference transitions retain explicit reset behavior.

Capsules approximate visual volume. At combined head limits, a hard shape/rate envelope can leave proxy overlap: the normalized continuous sweep records a maximum of approximately 0.009 meters. This diagnostic is retained rather than hidden or converted into unstable motion. The actual-mesh regression continues to require zero crossings in the selected collar region. Feasible-contact unit tests still require separation; conflicting-contact tests explicitly require bounded shape, speed, and no injected impulse. Full-costume clearance remains outside this correction.

## Verification record

Ten pure solver/geometry/clock tests, five profile/pairing tests, and seven actual-asset physics tests supplement the preceding 73 tests. The actual-asset tests cover selected-region mesh crossings, unchanged primary joints, pause/reference, hidden/re-entry history, placement/scale changes, delayed frames, invalid replacement, primary-motion fallback, continuous head motion at 30/60/90/120 FPS, and repeated five-degree heading changes. The cuff regression runs with both attention and hair physics active. The strict triangle predicate is shared by the cuff and hair tests.

The initial 90-test run passed at `/private/tmp/Bina-Hair-Physics-Final-Tests-2.xcresult`; subsequent headset feedback exposed its continuity coverage gap. The corrected 95-test run passes with zero failures/skips and no runtime warnings at `/private/tmp/Bina-Rear-Hair-Regression-Tests-3.xcresult`. Verification includes both hair surfaces (`CharacterMaterial_22` and `_23`) against body/collar materials `_00` and `_05`, plus debug-opacity restoration. The tested region in default reference-height coordinates is X `[-0.18,0.18]`, Y `[1.18,1.32]`, Z `[-0.34,0.08]` meters; it is a selected collar region, not an all-costume collision test.

The initial thickness calibration produced zero strict crossings in seven settled poses and 24 sweep snapshots, but did not prevent rear-lock instability. The final correction again has zero selected-region crossings in seven settled poses and 24 snapshots across an 11-second sweep, now using the application's bounds-normalized hierarchy. Continuous actual-rig tests additionally enforce rear orientation within 0.651 radians of the primary pose and observed frame-to-frame angular speed below 4 radians per second, including head motion and fixed-step resampling. Repeated heading changes preserve the local pose and do not replay warm-up. An optimized native macOS sample reports approximately 0.03 ms average and 0.05 ms peak for recent physics CPU updates; these are desktop measurements and do not set a headset budget.

The generic visionOS device SDK build passes with signing disabled. The simulator and device app bundles contain the exact source model, pose, and current physics profile bytes. Initial evidence remains in `final-off/`, `final-on/`, `final-debug/`, and `verification-manifest.json` under `LocalAssets/Columbina/secondary-diagnostics/`. Current evidence is in `rear-correction-final/` (117 views, including full rear/side views), `rear-sweep-final/`, `rear-hair-collar-crossings.json`, `rear-contacts-final.json`, and `rear-stability-verification.json`. Native pause and reference-restoration errors are both zero. These are macOS RealityKit captures and simulator tests; headset smoothness, perceived volume, broader hair/clothing behavior, GPU cost, and thermal behavior still need the user's visionOS 27.2 test.

## Reproduce the local profile

Run from a character-enabled checkout on macOS with Xcode installed:

```sh
xcrun swiftc -parse-as-library -O \
  Bina/Character/CharacterPhysicsProfile.swift scripts/prepare-columbina-physics.swift \
  -framework RealityKit -o /private/tmp/Bina-Prepare-Physics
/private/tmp/Bina-Prepare-Physics \
  Bina/Resources/Characters/Columbina.usdz \
  Bina/Resources/Characters/ColumbinaPhysics.json
```

The authoring tool derives chain tails and bone-local proxy attachments from the exact imported reference rig. Runtime profile validation and model pairing remain mandatory. Keep generated profile data local under the same asset-use boundary as the model.

## Remaining acceptance and later expansion

The selected hair-lock integration has passed automated verification and is ready for headset review. A separate native cloth patch can establish runtime API behavior later; the existing compile probe must not be presented as character-cloth integration.

Deliverables:

- A reproducible before/after sweep of permitted head yaw/pitch and combined extremes, including a full idle cycle.
- Visible lag and settling during a turn, stable rest afterward, and no obvious hair-through-collar defect in the selected contact region.
- Debug visualization of physical chains and collision proxies to separate geometry, weights, contact thickness, and solver defects.
- Repeatable checks for length constraints, collision separation, invalid configuration, frame spikes, pause/reference, scene re-entry, re-placement, and scale changes.
- Actual skinned-mesh checks for the selected contact region, alongside the existing eye/material, fixed-foot, and cuff regressions. Proxy separation alone does not establish mesh clearance.
- Headset confirmation on visionOS 27.2 and CPU/GPU/frame-time/thermal observations with physics on and off. Set budgets from those measurements.

Only after that experiment passes should the scope expand to additional hair chains and a selected garment panel. Preserve the primary-motion implementation and local source files throughout. A third-party rigid-body engine or wider renderer migration should follow demonstrated native/custom-solver shortcomings, not precede the first measured experiment.

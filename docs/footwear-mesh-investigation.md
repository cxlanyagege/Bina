# Footwear Mesh Regression Investigation

Date: 2026-11-01. Status: the failing runtime reconstruction path has been replaced with native import of an authored layer. Verification of the correction is recorded below.

## Finding and limits

The original 151-test footwear pass is genuine. It does not establish that the derived barefoot mesh is reliable across later runs. Replaying the preserved application and test binaries now produces renderer-related process kills without rebuilding the conversation implementation into them.

Controlled experiments isolate a trigger to `MeshResource.generate(from:)` in `CharacterFootwear.init`. Skipping that call, while retaining the foot-pose calculation, contact measurements, and facial setup, lets the selected previously failing facial test pass. Disabling startup character loading alone does not.

These experiments locate the original failure in the footwear mesh preparation path and its interaction with RealityKit's renderer. The correction below removes that path. The evidence does not establish a particular corrupt index, an application buffer-lifetime error, or an Apple-only defect. It also does not explain which execution condition allowed the original run to pass. Do not attribute it to a user environment change, an API request, or local-memory persistence without additional evidence.

## Historical pass and comparison

The original `/private/tmp/Bina-Footwear-Full-27_2.xcresult` records 151 passes, zero failures/skips, and no reported runtime warnings on 2026-10-31. The toolchain was Xcode 27.2 (27B52), with visionOS Simulator 27.2 (24N120), device `1BEDF9CF-615D-4096-9C28-33AF40FEEFB4`.

The passing application and test bundle were retained under `/private/tmp/Bina-SpatialPrototype-DerivedData/Build/Products/Debug-xrsimulator/Bina.app`. A copy of those binaries was replayed using a regenerated run specification, without recompilation, on the same Simulator identifier and OS build. The replay recorded 137 passes and 14 process kills at `/private/tmp/Bina-151-Replay.xcresult`. The launch specification and transient process state were not preserved from the original run, so this is not a claim that every execution condition was identical.

Additional comparisons found:

- The four bundled character resources are byte-identical in the original passing app, the later failing spatial-baseline app, and the current source resources.
- The original spatial files listed in `LocalAssets/Columbina/footwear-diagnostics/verification-manifest.json` still match, except for the app entry point changed by conversation integration. New conversation files are outside that older manifest.
- `CharacterFootwear.swift` and `CharacterAsset.swift` have no changes between spatial commit `2c4cf3f` and conversation commit `d9bdabc`.
- The `CharacterFootwear.o` machine-code section from the passing build and the recompiled spatial baseline has the same 36,856-byte length and SHA-256 `2498a16a77ad97a4cfd13e425a8b3873454407c30e14ea172edae5d2a658c859`.
- Replaying with default test scheduling also fails; the later explicit serial-testing option is not a sufficient explanation.

The new root view moves `ContentView` behind the second tab instead of presenting it as the root. Its task loads the character, so this integration can change when footwear preparation runs relative to tests. It is a relevant difference, but it has not been proved to cause the pass/fail transition. The failures can occur without any conversation code.

## Why unrelated tests are reported as failures

The failures are process terminations (`Test crashed with signal kill.`), rather than fourteen independent assertion mismatches. Renderer crashes coincide with this stack in `backboardd`:

```text
IndexValidation._validate_neon(_:vertexCount:)
DRValidateIndices
validatePrivateData(id<REMeshPayload>, ...)
-[REMultiBufferMeshPayload initWithCoder:]
NSXPCDecoder
```

`CharacterAsset.loadIdleMotion` prepares footwear before hair and face, even when the selected form is water heels. Facial and hair fixtures therefore execute the barefoot-mesh generation path. In the old app, startup loading can also execute it while another test is active. A delayed renderer exit can consequently kill a test whose own assertions concern another feature. The fourteen failed test names differ between the conversation regression and the old-binary replay; the number does not identify fourteen newly broken behaviors.

## Controlled isolation

Experiments use an isolated archive of `2c4cf3f` at `/private/tmp/Bina-Conversation-Spatial-Baseline`. Diagnostic switches exist only in that temporary archive; they are not production options. Unless stated otherwise, the probe is `BundledCharacterFaceTests/testDeliveredFacialTargetsAreUniqueAndTheDefaultIsCoveredClosed` on Simulator 27.2. These are narrow isolation results, not full-suite or headset acceptance.

| Experiment | Result and artifact |
| --- | --- |
| Skip automatic startup character loading, retain normal fixture loading | Failed. `/private/tmp/Bina-Startup-Isolated-Face.xcresult`. |
| Skip startup loading and footwear preparation, retain real asset, hair, and face | Passed. `/private/tmp/Bina-No-Footwear-Face.xcresult`. This diagnostic disables footwear and is not an acceptable feature fix. |
| Skip startup loading and only the derived-mesh generation call; use the original mesh for the diagnostic | Passed twice, including a repeat with the same diagnostic binary used by the exact-roundtrip failure. Foot rotations, both contact measurements, and facial mapping setup still run. `/private/tmp/Bina-No-Generation-Face.xcresult` and `/private/tmp/Bina-No-Generation-Face-Repeat.xcresult`. Heel removal is intentionally absent, so this is not footwear acceptance. |
| Copy all publicly exposed vertex/index buffers before generation | Failed. `/private/tmp/Bina-Buffer-Copy.xcresult`. |
| Retain the generated mesh's input contents for the controller lifetime | Failed. `/private/tmp/Bina-Buffer-Retain.xcresult`. |
| Reconstruct fresh public part/model descriptors and copy buffers | Both facial and heel-removal probes failed; the app also reported a missing `originalModelVertexIndex` data buffer. `/private/tmp/Bina-Fresh-Descriptors.xcresult`. This candidate is rejected. |
| Keep all heel parts while rebuilding retained parts and re-encoding indices | Failed. `/private/tmp/Bina-Roundtrip-Face.xcresult`. Removing heel parts is not required for this failure. |
| Generate directly from the original, unmodified `component.mesh.contents` | Failed. `/private/tmp/Bina-Exact-Roundtrip-Face.xcresult`. The generation input has neither part filtering nor index re-encoding. |

The original source's public triangle-index range checks succeed before generation. Those checks do not validate the private mesh representation later decoded by the renderer. The previous conclusion that index re-encoding resolved the issue was stronger than the evidence: it was followed by one full pass, but later replays and the isolation experiments still fail.

## Completion criteria

A production correction must preserve both foot forms, actual heel-geometry and shadow removal, named facial targets, skeleton identity, current material/weight state, fixed foot poses, and ground contact. Disabling footwear, suppressing failing tests, or showing transparent heels does not meet those requirements.

Validate the correction first with the failing facial probe and `BundledFootwearTests/testBarefootRemovesHeelGeometryAndRetainsOtherPartsAndFacialMappings`, then the complete relevant spatial tests and the current full suite. Verify repeated independent launches because a single passing run did not establish stability here. Physical-headset presentation and sustained behavior remain separate acceptance checks.

## Production correction

`scripts/prepare-columbina-footwear.py` authors `ColumbinaBarefoot.usdc` beside the original USDZ. The layer references that package, removes the heel faces, and remaps corner attributes and subset indices offline. It retains the empty heel material binding so native import preserves the existing material slots. Source points, skinning, skeleton, sparse facial targets, materials, and textures remain unchanged. The derived layer is 5,812,856 bytes; it does not duplicate the source textures.

`CharacterFootwearAsset` verifies the layer/source pairing through `ColumbinaFootwear.json`, then calls `Entity(contentsOf:)` to obtain a native imported mesh. `CharacterFootwear` validates that mesh and retains it alongside the original mesh. It no longer calls `MeshResource.generate(from:)`. The existing pose owner, fixed rotations, contact measurement, form selection, face weights, materials, and fallback boundaries are retained. See [footwear preparation](footwear.md#reproduce-the-native-variant) for reproduction.

Additional regressions reject malformed/unpaired metadata, changed layer bytes, and an unfiltered native mesh. They also reload the character three times and switch both forms while checking actual facial weights and hair availability. Existing deep geometry comparisons remain in place; they are not replaced by count-only acceptance tests.

### Correction verification on 2026-11-01

| Check | Result |
| --- | --- |
| Focused Simulator 27.2 run | 13 passed: all eight bundled footwear cases, the previously failing facial case, and four profile tests. `/private/tmp/Bina-Footwear-Native-Fix-Smoke.xcresult`. |
| Full Simulator 27.2 regression | 217 passed, zero failures/skips and no reported runtime warnings. Includes the previous 211 tests plus four profile cases and two bundled regressions. All 60 conversation/memory tests and every previously interrupted character case pass. `/private/tmp/Bina-Footwear-Native-Fix-Full.xcresult`. |
| Independent Simulator 27.0 run | Three passed, zero failures/skips or reported runtime warnings, on device `653C1589-0C41-48BD-AC80-38660F69F83E`, OS build 24M362. Covers the facial failure probe, deep retained-geometry/heel-removal check, and repeated native loads/form switches with actual face weights. `/private/tmp/Bina-Footwear-Native-Fix-27_0.xcresult`. This is a focused minimum-version check, not another full-suite run. |
| Synthetic USD authoring regressions | Three passed, covering actual face/corner remapping, source preservation, malformed subsets, and unsupported indexed face data. `/private/tmp/Bina-Footwear-Authoring/tests.log`. |
| Simulator test build | Passed with normal ad-hoc identity. `/private/tmp/Bina-Footwear-Native-Fix-build.log`. |
| Generic visionOS device SDK build | Passed with signing disabled. `/private/tmp/Bina-Footwear-Native-Fix-Device.log`. This is not a headset installation or run. |
| Resource integrity | All six resource hashes match both built app bundles. The four original resource hashes also match the preserved historical passing app. `LocalAssets/Columbina/footwear-diagnostics/native-import-fix/resources.json`. |
| Native desktop rendering | Two capture runs cover both forms from four foot and four face views. In the repeated set, all eight barefoot captures and all four water-heel foot captures are pixel-identical to the historical reference. The four water-heel facial images differ at no more than 0.055% of pixels; the maximum mean absolute RGB difference is 0.000237 on the 0–255 scale. Both contact records are unchanged. Captures and numerical comparisons are under `LocalAssets/Columbina/footwear-diagnostics/native-import-fix/`. |

The first desktop capture run contained one empty water-heel rear image. Rerunning the unchanged program produced the expected image, pixel-identical to the reference. Both sets are retained; the empty capture is not silently treated as a presentation pass. The repeated full set was checked alongside front-face and side-foot views. These desktop diagnostics do not establish headset rendering or sustained frame stability.

Physical-headset appearance, frame stability, and sustained performance require a new check. Earlier user feedback predates this change. The private renderer mechanism and the original passing run's exact conditions remain unknown even when the replacement passes regression.

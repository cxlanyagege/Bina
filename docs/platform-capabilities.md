# Platform Capabilities

Status: platform baseline with a limited D1 implementation. General platform sources reviewed: 2026-10-19; plane APIs and implementation status updated: 2026-10-31. Sources include visionOS 27 documentation and the installed XROS 27.0 Swift interfaces.

## Local project baseline

The current project targets visionOS 27.0 and implements a mixed immersive scene, world tracking, floor preview/confirmation, calibrated sole contact, local anchor-association storage, character loading, stance/idle, head attention, selected hair physics, and facial previews. Build and test evidence are recorded in the [spatial prototype guide](spatial-prototype.md#automated-verification). The user reports visionOS 27.2, acceptable posture/motion, a resolved cuff defect, preliminary rear-hair stability, and natural facial presentation. Floor acceptance and detailed device measurements remain open. This does not change the 27.0 deployment target. Conversation and personal memory remain unimplemented.

Do not infer device support or permission from the deployment target. Check provider support, current authorization, and session state at runtime.

## Capabilities and boundaries

| Capability | Verified scope | Bina baseline |
| --- | --- | --- |
| World tracking and device pose | World tracking provides device pose and world anchors. World tracking itself does not require user authorization; other providers have their own requirements. [1] | Place the character in a user-confirmed location and track spatial validity. |
| Planes and scene reconstruction | ARKit exposes surfaces and environment geometry. These are not general identification or semantic understanding of arbitrary objects. [1][2][11] | Horizontal classified-floor meshes now support preview/confirmed placement with world-sensing permission. Scene reconstruction, environment occlusion, and room collision remain unimplemented. |
| Hand tracking | Hand and joint data support custom interaction with the relevant permission and tracking availability. [1] | Start with system interaction and a small set of useful gestures. |
| Reference-object tracking | Requires prepared 3D assets and Create ML reference-object training; visionOS object tracking operates in an ImmersiveSpace. [3] | Track one prepared, preferably rigid and stationary physical object. |
| Moving reference objects | visionOS 27 supports per-object high-frame-rate tracking with additional power and performance cost. [4] | Evaluate separately after stationary tracking works. |
| Persistent world anchors | ARKit persists anchor UUID and pose; the app stores their meaning and associated content state. Nearby anchors can return in later sessions. [5] | Restore placement when the anchor is available; recover gracefully when it is not. |
| Main-camera and Camera Region input | Enterprise APIs require approval and a license. They are not unrestricted consumer camera access. [6] | Optional research path; never a prerequisite for the initial companion. |
| Eye and facial input | Eye input is not shared with apps. Raw face tracking is not exposed on visionOS; a Persona video feed is a different capability. [7][8] | Use explicit input and head/device pose. Treat inferred attention and emotion as uncertain. |
| System Visual Intelligence | Apple states that this system capability shares no information with third parties. [8] | Do not assume Bina receives its recognition results. |

## Space and lifecycle

Bina's implemented initial sensing experience uses a mixed `ImmersiveSpace`: the app occupies a Full Space while the user can still see passthrough. Full Space is an application presentation mode, not a requirement to render a fully virtual environment. The system permits one immersive space at a time. [1][9]

The prototype runs `WorldTrackingProvider` with an authorized horizontal `PlaneDetectionProvider`. `NSWorldSensingUsageDescription` explains floor placement, and `.worldSensing` must be allowed before plane startup. The adapter uses `PlaneAnchor.surfaceClassification == .floor`, actual mesh coverage, and runtime support/state checks. Denial or unsupported detection leaves world tracking and manual-height placement available; a failed combined startup retries once with fresh world-only providers. Manual height remains a headset-relative offset rather than measured floor evidence. Scene reconstruction, hand, and camera data are not requested. See the [floor contract](floor-placement.md) and [device checks](spatial-prototype.md). [11]

The stance/idle preview uses local model data and rendering updates. It adds no sensing provider or permission. Motion pauses while the character is hidden or the scene is inactive, and update subscriptions are removed when the immersive view disappears.

Selected hair physics uses a local fixed-step spring solver with body/collar capsule proxies and existing skeletal transforms. It adds no ARKit provider or real-environment collision sensing. Native cloth APIs are present in the installed visionOS 27.0 SDK and pass a compile probe, but broad garment simulation is not integrated. See [Secondary motion](secondary-motion.md) for verified scope and the pending headset performance check.

Bounded head attention queries the same active `WorldTrackingProvider` on scene updates. The device position is an approximate head target, not the center-of-head visual anchor or eye-gaze input. No new sensing provider, authorization, or camera input is added. Missing/rear/near targets return toward neutral; inactive content retains its pose and discards the held target. See the [head-attention contract](head-attention.md).

Avoid the blanket claim that every ARKit provider only works in Full Space. Approved enterprise main-camera access can operate in Shared Space as well as Immersive Space starting with visionOS 26. This exception does not grant ordinary shared-space content equivalent environment sensing. [10]

Anchor persistence is not continuous background execution. Design a clear start, session interruption, resume, and stop lifecycle. Do not promise whole-system observation while other applications are in use.

## Camera research and distribution

Current enterprise API documentation requires business use and limits production distribution to approved private in-house or custom applications through Apple Business Manager. Development Only access can be requested for registered test devices using development profiles. Approval is not guaranteed, and development approval is not approval for public consumer distribution. [6]

Main camera and Camera Region are both part of this restricted capability path. Camera Region is not a public workaround. Apple Developer Program membership can be used to request access; joining the Enterprise Program does not automatically grant it. [6][10]

For the first experience, use reference objects and explicit user input. Treat manual labels or placement as manual evidence, not as autonomous recognition. If an experiment substitutes manual placement for live object tracking, record that limitation and do not mark the tracked-object milestone complete.

## Required experiment evidence

For each provider, record the device and system version, presentation mode, permission configuration, source data received, failure behavior, and observed performance. Validate the actual model and real room rather than extrapolating from Simulator or an API's existence.

Recheck this document before changing the deployment target, adopting a new sensor, or deciding distribution scope.

## Official references

1. [Setting up access to ARKit data](https://developer.apple.com/documentation/visionos/setting-up-access-to-arkit-data).
2. [ARKit in visionOS](https://developer.apple.com/documentation/arkit/arkit-in-visionos).
3. [Implementing object tracking in your app](https://developer.apple.com/documentation/visionos/implementing-object-tracking-in-your-app).
4. [Using a reference object with ARKit in visionOS](https://developer.apple.com/documentation/visionos/using-a-reference-object-with-arkit-in-visionos).
5. [Tracking specific points in world space](https://developer.apple.com/documentation/visionos/tracking-points-in-world-space).
6. [Building spatial experiences for business apps with enterprise APIs for visionOS](https://developer.apple.com/documentation/visionos/building-spatial-experiences-for-business-apps-with-enterprise-apis).
7. [Eyes, Hands & Privacy](https://www.apple.com/legal/privacy/data/en/eyes-hands/).
8. [WWDC26: visionOS Group Lab](https://developer.apple.com/videos/play/wwdc2026/8004/), including face data at 27:02 and Visual Intelligence at 28:23.
9. [ImmersiveSpace](https://developer.apple.com/documentation/SwiftUI/ImmersiveSpace).
10. [WWDC25: Explore enhancements to your spatial business app](https://developer.apple.com/videos/play/wwdc2025/223/), including camera presentation modes and Camera Region.
11. [Placing content on detected planes](https://developer.apple.com/documentation/visionos/placing-content-on-detected-planes) and [PlaneAnchor](https://developer.apple.com/documentation/arkit/planeanchor).

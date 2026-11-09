# Bina App Icon

The icon uses Columbina's white feathered head ornament as its central motif, with pearl-white relief and restrained lavender shading. The background transitions vertically from lighter violet (`#9678B5`) at the top through iris purple (`#7B599F`) to deeper violet (`#603F82`) at the bottom, inspired by her eye color. The restrained light-to-dark gradient supports system lighting while preserving contrast with the white ornament.

## Artwork

- [Square composite](bina-icon-v1.png): the production layers composited at 1024 by 1024 pixels.
- [Circular preview](bina-icon-v1-circular.png): a static preview of the circular crop.
- [Initial concept](bina-icon-concept-v1.png): the original generated composition with the earlier dark-to-light background, before the foreground was separated and its margins refined.
- [Background source](background.svg): the editable gradient specification.
- [Generation prompts](generation-prompts.txt): the complete prompts used with the built-in `image_gen` tool.

The initial image used the project's local rear-view character render as a reference for the headpiece and the eye close-up as a palette reference. The foreground was then extracted and refined with the same image tool, and resized to the production dimensions. The gradient and static previews were exported in sRGB with Core Graphics.

The production foreground subsequently received a lossless alpha cleanup after headset testing revealed scattered shadows during focus. This removed 440 disconnected regions containing 1,628 faint pixels. All 160,516 pixels belonging to the connected ornament retain their exact RGBA values, including the antialiased feather edges. The square and circular previews were regenerated from the repaired foreground and the existing background.

## Asset catalog

The existing `AppIcon` asset uses two layers:

- `Bina/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/Headpiece.png`: a transparent 1024-by-1024 foreground.
- `Bina/Assets.xcassets/AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/PurpleGradient.png`: an opaque 1024-by-1024 background.

Both runtime layers remain square and unmasked. visionOS supplies the circular mask, lighting, and depth behavior; see Apple's [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons). The former empty middle layer was removed from the stack.

## Verification

The foreground's significant alpha bounds are `(173, 193)` through `(851, 860)` in the 1024-pixel export. All pixels with alpha of at least 64 remain inside a centered circle with a diameter of 90 percent of the canvas. Both layer images and the circular composite were inspected locally. The background has no alpha channel.

On 2026-11-01, the asset manifests and image references passed validation, and the complete Debug build for a generic visionOS device succeeded with code signing disabled. The build used Xcode 27.2 and wrote its products to `/private/tmp/Bina-AppIcon-Build`.

The alpha regression check examines every nonzero alpha value, including values below normal visual thresholds. The ornament is intentionally one connected shape. Run it from the repository root:

```sh
swift scripts/check-app-icon-alpha.swift
```

The check rejects the retained pre-fix image with 440 stray regions and passes the repaired image with zero disconnected regions. It also checks dimensions, transparent background, nonempty content, and the circular safe margin. A PNG round-trip comparison verified that the repair changed only the isolated pixels' alpha values.

The complete generic visionOS Debug build passed again after this alpha repair. Its log is `/private/tmp/Bina-AppIcon-Alpha-Fix-Build.log`.

On 2026-11-03, the background changed to the softer top-to-bottom light-to-dark palette documented above. The background PNG matches the SVG's top, middle, and bottom color stops and remains an opaque 1024-by-1024 sRGB image. The foreground's SHA-256 remained unchanged, the alpha regression check passed, and both previews were refreshed. The complete generic visionOS Debug build passed; its log is `/private/tmp/Bina-AppIcon-Gradient-Build.log`.

The static preview does not reproduce system lighting or parallax. Their final appearance remains to be checked on Apple Vision Pro.

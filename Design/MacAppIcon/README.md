# Bina macOS App Icon

The Mac icon uses the same white feather headpiece as Bina's visionOS icon on a restrained top-to-bottom light-to-dark purple gradient. It is a native Icon Composer document so macOS supplies the rounded-rectangle enclosure, material effects, and appearance variants.

## Source and palette

- `BinaMac/Resources/AppIcon.icon/icon.json` defines the native background gradient and one foreground group.
- `BinaMac/Resources/AppIcon.icon/Assets/Headpiece.png` is a byte-for-byte copy of the cleaned visionOS foreground at `Bina/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/Headpiece.png`.
- `Preview.png` is a flattened, system-rendered default preview for review.

| Element | sRGB color |
| --- | --- |
| Background, top | `#9678B5` |
| Background, bottom | `#603F82` |
| Foreground | Pearl white with lavender relief shading |

The foreground uses a transparent, unmasked 1024 x 1024 sRGB canvas. The illustration stays centered with generous space around its edges. Its existing relief shading belongs to the approved artwork; Icon Composer adds the system's enclosure, highlights, and cast shadow. The background uses the approved purple endpoints as an opaque native gradient. Dark, clear, and tinted appearances use the system's automatic variants while preserving the same artwork.

Run `swift scripts/check-app-icon-alpha.swift BinaMac/Resources/AppIcon.icon/Assets/Headpiece.png` from the repository root after replacing the foreground. The check rejects disconnected alpha specks, including nearly invisible pixels that can produce stray system shadows.

## Build and preview

Run `bash scripts/build-macos.sh` to compile the icon with Apple's asset compiler and package both `Assets.car` and the generated `AppIcon.icns`. The bundle declares `CFBundleIconName` and `CFBundleIconFile` as `AppIcon`. The application icon appears in the Dock, Finder, and other system locations.

Open `BinaMac/Resources/AppIcon.icon` in Icon Composer to edit or inspect the layers. After changing artwork outside Icon Composer, reopen the icon document to reload it. Refresh the default preview from the repository root with the following command.

```sh
icon_composer_tool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$icon_composer_tool" "$PWD/BinaMac/Resources/AppIcon.icon" \
    --export-image --output-file Design/MacAppIcon/Preview.png \
    --platform macOS --rendition Default \
    --width 1024 --height 1024 --scale 1
```

## Verification

On 2026-11-21, the default and dark macOS renditions were exported with Icon Composer's bundled `ictool` and inspected. The Mac foreground matches the approved visionOS PNG byte for byte and passes the alpha connectivity and safe-margin check.

`bash scripts/build-macos.sh release` completed successfully. The packaged `.build/macos/Bina.app` contains `AppIcon.icns` and `Assets.car`, and its icon metadata names `AppIcon`. The generated `.icns` was inspected to confirm that the feather artwork is present in the application bundle. `codesign --verify --deep --strict --verbose=2 .build/macos/Bina.app` passed, including the embedded controls extension.

## Apple references

- [App icons in the Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

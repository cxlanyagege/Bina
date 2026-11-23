# Bina for macOS

Bina for macOS is a native toolbox with tools for managing idle sleep and browsing installed applications. The interface and built-in help use Simplified Chinese.

## Run locally

The app requires macOS 26.0 or later. Use Xcode 27.2 with the macOS SDK and Icon Composer. The signed build requires a valid Apple Development signing identity.

```sh
bash scripts/build-macos.sh release
```

The script builds the app and its embedded extension, verifies their signatures, and publishes the development-signed bundle at `.build/macos/Bina.app`. Copy it to `~/Applications/Bina.app` for daily use and open that copy to register its control. Quit Bina before updating the installed bundle. Set `BINA_MAC_DEVELOPMENT_TEAM` or select the same development team in Xcode for both the app and the extension to build with a different team.

In Control Center, choose Edit Controls and add the **Keep Display Awake** control (`保持常亮`) from Bina. Click it to toggle the display request. The control can start Bina in the background. The app uses the `cxlanyagege.Bina.Mac` bundle identifier and its extension uses `cxlanyagege.Bina.Mac.Controls`.

In the macOS menu bar, choose **Help > Bina Help** (`Bina 帮助`) to open the offline guide.

## Keep Awake

The tool opens selected in the sidebar. The window and Control menu offer the same switches.

- **Keep Display Awake** (`保持常亮`) keeps the display on and also prevents idle system sleep. It starts off.
- **Prevent Idle Sleep** keeps the Mac awake while allowing the display to sleep. It starts off.

Closing the window leaves both settings active for the current app session. Reopen Bina to show its window. Quit Bina to release both requests. Manual sleep, lid closure, and system power or thermal policies are handled by macOS.

### Control Center and app lifetime

The app delegate owns independent IOKit assertions for the display and system. Turning Prevent Idle Sleep on acquires a system assertion even while the display assertion is active. The system assertion then continues protecting the Mac from idle sleep after the display assertion is released. [IOKit assertion types](https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes)

The app and WidgetKit extension both compile `SetKeepAwakeIntent.swift`. The intent runs in the containing app with dynamic foreground support and uses the app-owned display session. The extension reads the live display assertion. The app asks Control Center to reload when the display request changes. Failed IOKit transitions preserve the previous state. macOS removes the app's assertions if the process exits unexpectedly. [App Intent runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)

## Application Management

Select Application Management in the tools sidebar to browse separately installed apps. Use the toolbar search field to filter by display name. Select a row to see its version, location, and bundle identifier on the App Details page. With the list focused, use the arrow keys to select a row and Return to open it. The toolbar Back button restores the search and list position.

The tool reads the shared and current user's application folders and supplements them with Spotlight results from local volumes. The catalog omits macOS system apps based on their bundle locations. Separately installed Apple apps are eligible for discovery. Discovery outside the standard folders depends on Spotlight indexing and the file access macOS grants to Bina.

## Development

Open `Bina.xcodeproj` and select the shared `BinaMac` scheme. `BinaMac/Build.xcconfig` configures the macOS SDK, Swift language mode, and deployment target for the Mac targets.

- `BinaMac/App` owns the window, menu commands, help, and tool presentation. Add new tools under `App/Tools` and register them in `MainWindowContent`.
- `KeepAwakeCore` owns the session state and assertion contract. `KeepAwakePower` implements the contract and status queries with IOKit. Both build as static libraries.
- The Mac app embeds the `BinaMacControls` WidgetKit extension. Both targets use App Sandbox.
- `BinaMacTests` uses the Mac app as its host. `KeepAwakeTests` tests the libraries and live IOKit assertions.

```sh
xcodebuild -project Bina.xcodeproj -scheme BinaMac -destination 'platform=macOS' test
bash scripts/tests/test_build_macos.sh
swift format lint --strict --recursive BinaMac
```

Quit the installed Mac app before running hosted tests with its bundle identifier. To run the tests while keeping it open, pass `BINA_MAC_BUNDLE_IDENTIFIER=cxlanyagege.Bina.Mac.EngineeringTests` to the Xcode build command.

The build script locks publication, checks the staged app signature, and restores the previous bundle if replacing it fails. The packaging tests exercise this workflow with disposable bundles.

The [Mac app icon notes](../../Design/MacAppIcon/README.md) describe the Icon Composer resources. For measurements of the earlier standalone tool, see the [Keep Awake performance baseline](performance-baseline.md).

## Migration verification

On November 21, 2026, all 16 macOS test runs and the packaging checks passed using Xcode 27.2 on macOS 27.3. The Release app and embedded extension passed signature verification. The initial local install in `~/Applications` included a compiled app icon and Simplified Chinese bundle metadata.

The Mac target's app icon subsequently changed to Bina's white feather headpiece on a light-to-dark purple gradient, using native Icon Composer enclosure and appearance effects. The updated Release bundle passed icon packaging and deep signature checks, and its default and dark icon previews were inspected. See the [Mac app icon notes](../../Design/MacAppIcon/README.md).

The installed app acquired separate display and idle system assertions. Turning off Keep Display Awake from the Control menu released the display assertion while retaining the system assertion. The system assertion survived closing and reopening the app window. Quitting removed it. The Help menu opened the offline guide.

Control Center recognized and added the Bina control. Turning it on after the app exited started the installed Bina in the background and acquired its display assertion. Turning the control off released the assertion. The localized control remained present after updating the installed app.

The signed visionOS 27.2 Simulator run passed all 277 tests. The generic visionOS Release build also passed with device signing disabled.

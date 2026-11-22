import AppIntents
import AppKit
import KeepAwakeCore
import KeepAwakePower
import SwiftUI
import WidgetKit

@main
@MainActor
struct BinaMacApp: App {
    @NSApplicationDelegateAdaptor(BinaMacAppDelegate.self) private var delegate

    var body: some Scene {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Bina"
        WindowGroup(displayName, id: "main") {
            MainWindowContent(keepAwake: delegate.keepAwake)
        }
        .defaultSize(width: 680, height: 440)
        .commands {
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            KeepAwakeCommands(model: delegate.keepAwake)
            HelpCommands()
        }

        Window(HelpView.title, id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 560, height: 460)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}

@MainActor
final class BinaMacAppDelegate: NSObject, NSApplicationDelegate {
    let keepAwake: KeepAwakeModel

    override init() {
        let displaySession = KeepAwakeSession(assertion: IdleSleepAssertion(target: .display)) {
            ControlCenter.shared.reloadControls(ofKind: KeepAwakeControlConfiguration.kind)
        }
        let systemSession = KeepAwakeSession(assertion: IdleSleepAssertion(target: .system))
        keepAwake = KeepAwakeModel(displaySession: displaySession, systemSession: systemSession)
        super.init()
        AppDependencyManager.shared.add(
            key: KeepAwakeControlConfiguration.sessionDependencyKey, dependency: displaySession)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ControlCenter.shared.reloadControls(ofKind: KeepAwakeControlConfiguration.kind)
    }

    func applicationWillTerminate(_ notification: Notification) {
        keepAwake.shutdown()
        ControlCenter.shared.reloadControls(ofKind: KeepAwakeControlConfiguration.kind)
    }
}

import SwiftUI
import AVFAudio
import Combine

struct BinaRootView: View {
    @Bindable var prototype: SpatialPrototype
    @Bindable var conversation: ConversationModel
    let speech: SpeechSession

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ConversationView(model: conversation, speech: speech)
                    .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
                ContentView(prototype: prototype)
                    .tabItem { Label("角色与空间", systemImage: "person.crop.rectangle") }
            }
            Divider()
            SpeechControlsView(speech: speech, hasAPIKey: conversation.hasAPIKey)
        }
        .frame(width: 620, height: 940)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification).receive(on: RunLoop.main)) { notification in
            let context = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            if context?.source != .app { speech.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereLostNotification).receive(on: RunLoop.main)) { _ in speech.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification).receive(on: RunLoop.main)) { _ in speech.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                || reason == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue { speech.stop() }
        }
    }
}

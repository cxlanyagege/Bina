import SwiftUI
import RealityKit

struct SpatialPrototypeView: View {
    let prototype: SpatialPrototype
    let speech: SpeechSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var motionSubscription: EventSubscription?
    @State private var motionToken: UUID?

    var body: some View {
        RealityView { [prototype] content, attachments in
            content.add(prototype.contentEntity)
            content.add(prototype.floorMarker.root)
            if let caption = attachments.entity(for: "speech") {
                caption.components.set(BillboardComponent())
                prototype.attachSpeechCaption(caption)
            }
            motionSubscription?.cancel()
            let token = prototype.beginMotionUpdates()
            motionToken = token
            motionSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak prototype] event in
                prototype?.advanceCharacterMotion(by: event.deltaTime, token: token)
                speech.updatePresentation(available: prototype?.canPresentSpeech == true)
            }
        } update: { _, attachments in
            prototype.floorMarker.update(prototype.canShowFloorPreview ? prototype.floorPlacement.preview : nil)
            if let caption = attachments.entity(for: "speech") {
                prototype.attachSpeechCaption(caption)
                caption.isEnabled = prototype.canPresentSpeech && speech.phase != .idle
            }
        } attachments: {
            Attachment(id: "speech") { SpeechCaptionView(speech: speech) }
        }
        .task {
            prototype.spaceDidAppear()
            prototype.setSceneActive(scenePhase == .active)
            await prototype.startTracking()
        }
        .onChange(of: scenePhase) { _, phase in
            prototype.setSceneActive(phase == .active)
        }
        .onDisappear {
            speech.spaceDidDisappear()
            motionSubscription?.cancel()
            motionSubscription = nil
            prototype.endMotionUpdates(token: motionToken)
            motionToken = nil
            prototype.spaceDidDisappear()
        }
    }
}

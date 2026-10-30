import SwiftUI
import RealityKit

struct SpatialPrototypeView: View {
    let prototype: SpatialPrototype
    @Environment(\.scenePhase) private var scenePhase
    @State private var motionSubscription: EventSubscription?
    @State private var motionToken: UUID?

    var body: some View {
        RealityView { [prototype] content in
            content.add(prototype.contentEntity)
            content.add(prototype.floorMarker.root)
            motionSubscription?.cancel()
            let token = prototype.beginMotionUpdates()
            motionToken = token
            motionSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak prototype] event in
                prototype?.advanceCharacterMotion(by: event.deltaTime, token: token)
            }
        } update: { _ in
            prototype.floorMarker.update(prototype.canShowFloorPreview ? prototype.floorPlacement.preview : nil)
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
            motionSubscription?.cancel()
            motionSubscription = nil
            prototype.endMotionUpdates(token: motionToken)
            motionToken = nil
            prototype.spaceDidDisappear()
        }
    }
}

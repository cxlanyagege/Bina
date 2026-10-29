import SwiftUI
import RealityKit

struct SpatialPrototypeView: View {
    let prototype: SpatialPrototype
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RealityView { content in
            content.add(prototype.contentEntity)
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
            prototype.spaceDidDisappear()
        }
    }
}

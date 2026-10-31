//
//  BinaApp.swift
//  Bina
//
//  Created by 沈赫 on 2026/10/19.
//

import SwiftUI

@main
struct BinaApp: App {
    @State private var prototype = SpatialPrototype()
    @State private var conversation = ConversationModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BinaRootView(prototype: prototype, conversation: conversation)
        }
        .defaultSize(width: 620, height: 840)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) {
            if scenePhase == .background { conversation.cancel() }
        }

        ImmersiveSpace(id: SpatialPrototype.spaceID) {
            SpatialPrototypeView(prototype: prototype)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

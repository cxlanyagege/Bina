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

    var body: some Scene {
        WindowGroup {
            ContentView(prototype: prototype)
        }
        .defaultSize(width: 540, height: 760)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: SpatialPrototype.spaceID) {
            SpatialPrototypeView(prototype: prototype)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

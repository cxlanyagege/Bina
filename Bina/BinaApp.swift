//
//  BinaApp.swift
//  Bina
//
//  Created by 沈赫 on 2026/10/19.
//

import SwiftUI

@main
struct BinaApp: App {
    @State private var prototype: SpatialPrototype
    @State private var conversation: ConversationModel
    @State private var speech: SpeechSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let prototype = SpatialPrototype()
        let conversation = ConversationModel()
        let audioSession = SpeechAudioSession()
        let player = SpeechAudioPlayer(session: audioSession, target: { [weak prototype] in
            guard let prototype, prototype.canPresentSpeech else { return nil }
            return prototype.speechEmitter
        })
        _prototype = State(initialValue: prototype)
        _conversation = State(initialValue: conversation)
        _speech = State(initialValue: SpeechSession(conversation: conversation, player: player, audioSession: audioSession,
            present: { [weak prototype] cue, mouth in prototype?.presentConversation(cue, mouth: mouth) }))
    }

    var body: some Scene {
        WindowGroup {
            BinaRootView(prototype: prototype, conversation: conversation, speech: speech)
        }
        .defaultSize(width: 620, height: 940)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) {
            if scenePhase == .background { conversation.cancel() }
        }

        ImmersiveSpace(id: SpatialPrototype.spaceID) {
            SpatialPrototypeView(prototype: prototype, speech: speech)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

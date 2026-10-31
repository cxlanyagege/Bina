import SwiftUI

struct BinaRootView: View {
    @Bindable var prototype: SpatialPrototype
    @Bindable var conversation: ConversationModel

    var body: some View {
        TabView {
            ConversationView(model: conversation)
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
            ContentView(prototype: prototype)
                .tabItem { Label("角色与空间", systemImage: "person.crop.rectangle") }
        }
        .frame(width: 620, height: 840)
    }
}

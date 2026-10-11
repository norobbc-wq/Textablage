import SwiftUI

@main
@MainActor
struct TextablageApp: App {
    @StateObject private var store = SharedClipStore()

    var body: some Scene {
        WindowGroup {
            CollectionView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

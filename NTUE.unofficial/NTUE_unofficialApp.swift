import SwiftUI

@main
struct NTUE_unofficialApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.restoreSession() }
                .tint(Theme.accent)
        }
    }
}

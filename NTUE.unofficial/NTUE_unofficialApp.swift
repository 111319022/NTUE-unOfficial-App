import SwiftUI

@main
struct NTUE_unofficialApp: App {
    @State private var appState = AppState()
    @AppStorage("app_theme") private var themeRaw = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.restoreSession() }
                .tint(Theme.accent)
                .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
        }
    }
}

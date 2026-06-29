import SwiftUI

@main
struct NTUE_unofficialApp: App {
    @State private var appState = AppState()
    @AppStorage("app_theme") private var themeRaw = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.restoreSession() }
                .tint(Theme.accent)
                .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            // Keep the class Live Activity in step with the current period each
            // time the app comes to the foreground (and auto-start if enabled).
            if phase == .active { LiveActivityController.shared.syncOnForeground() }
        }
    }
}

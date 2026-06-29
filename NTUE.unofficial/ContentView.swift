import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            switch appState.phase {
            case .launching:
                SplashView()
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainTabView()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .task { if !hasSeenOnboarding { showOnboarding = true } }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("首頁", systemImage: "house.fill") }
            NavigationStack { ScheduleView() }
                .tabItem { Label("課表", systemImage: "calendar") }
            NavigationStack { AssignmentsView() }
                .tabItem { Label("作業", systemImage: "checklist") }
            NavigationStack { ServicesView() }
                .tabItem { Label("其他服務", systemImage: "square.grid.2x2.fill") }
        }
    }
}

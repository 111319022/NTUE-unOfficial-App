import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            switch appState.phase {
            case .launching:
                InitializingView()
                    .transition(.opacity)
            case .loggedOut:
                // 登入頁與初始化頁的插圖位置一樣，交叉淡入時看起來就像同一張圖
                // 留在原地、只有下面的字換了。
                LoginView()
                    .transition(.opacity)
            case .loggedIn:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.55), value: appState.phase)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .task { if !hasSeenOnboarding { showOnboarding = true } }
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

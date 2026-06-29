import SwiftUI

struct ServicesView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("app_theme") private var themeRaw = AppTheme.system.rawValue
    @State private var showOnboarding = false

    var body: some View {
        List {
            Section {
                profileRow
            }

            Section("外觀") {
                Picker(selection: $themeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.label, systemImage: theme.icon).tag(theme.rawValue)
                    }
                } label: {
                    Label("主題", systemImage: "paintbrush.fill")
                }
            }

            Section("教務") {
                serviceLink("成績查詢", "chart.bar.doc.horizontal", .blue) { GradesView() }
                serviceLink("歷年成績", "list.number", .cyan) { TranscriptView() }
                serviceLink("修業進度管制", "chart.pie.fill", .purple) { ProgressControlView() }
                serviceLink("公開課表查詢", "magnifyingglass", .teal) { PublicScheduleView() }
            }

            Section("學生事務") {
                serviceLink("請假 / 缺曠", "list.bullet.clipboard", .orange) { AttendanceView() }
                serviceLink("請假申請", "square.and.pencil", .red) { LeaveApplyView() }
                serviceLink("操行 / 獎懲", "star.circle.fill", .indigo) { ConductView() }
                serviceLink("在學證明", "checkmark.seal.fill", .green) { EnrollmentCertificateView() }
            }

            Section("Moodle 教學平台") {
                serviceLink("課程公告", "megaphone.fill", .pink) { AnnouncementsView() }
            }

            Section {
                Button(role: .destructive) {
                    appState.logout()
                } label: {
                    Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Button {
                    showOnboarding = true
                } label: {
                    Label("重新觀看 App 介紹", systemImage: "sparkles")
                }
            } footer: {
                Text("本 App 為學生自製，非學校官方出品；資料以 iNTUE 校務系統與 Moodle 教學平台為準。")
            }
        }
        .navigationTitle("其他服務")
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
        }
    }

    private var profileRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 52, height: 52)
                Text(String((appState.studentInfo.name.isEmpty ? appState.username : appState.studentInfo.name).suffix(2)))
                    .font(.headline).foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.studentInfo.name.isEmpty ? appState.username : appState.studentInfo.name)
                    .font(.headline)
                let detail = [appState.studentInfo.studentId, appState.studentInfo.className]
                    .filter { !$0.isEmpty }.joined(separator: "　")
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func serviceLink<Destination: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

import SwiftUI

struct ServicesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                profileRow
            }

            Section("教務") {
                serviceLink("成績查詢", "chart.bar.doc.horizontal", .blue) { GradesView() }
                serviceLink("修業進度管制", "chart.pie.fill", .purple) { ProgressControlView() }
                serviceLink("公開課表查詢", "magnifyingglass", .teal) { PublicScheduleView() }
            }

            Section("學生事務") {
                serviceLink("請假明細", "list.bullet.clipboard", .orange) { LeaveDetailView() }
                serviceLink("請假申請", "square.and.pencil", .red) { LeaveApplyView() }
                serviceLink("在學證明", "checkmark.seal.fill", .green) { EnrollmentCertificateView() }
            }

            Section {
                Button(role: .destructive) {
                    appState.logout()
                } label: {
                    Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("其他服務")
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
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

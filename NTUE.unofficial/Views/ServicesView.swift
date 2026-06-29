import SwiftUI

struct ServicesView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("app_theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("use18Week") private var use18Week = false
    @AppStorage("liveActivity_autoStart") private var liveAutoStart = false
    @State private var showOnboarding = false
    @State private var liveRunning = LiveActivityController.shared.isRunning
    @State private var webLink: WebLink?

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

            Section {
                Toggle(isOn: $use18Week) {
                    Label("18 週制學期", systemImage: "calendar.badge.clock")
                }
                .tint(Theme.accent)
            } footer: {
                Text("預設以 16 週(課程結束)計算學期倒數與假期;若你的系所/課程到第 18 週才結束，打開這個。")
            }

            Section {
                Toggle(isOn: $liveAutoStart) {
                    Label("上課時自動顯示", systemImage: "bolt.badge.clock")
                }
                .tint(Theme.accent)

                if liveRunning {
                    Button(role: .destructive) {
                        LiveActivityController.shared.end()
                        liveRunning = false
                    } label: {
                        Label("結束課程動態", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        LiveActivityController.shared.start()
                        liveRunning = LiveActivityController.shared.isRunning
                    } label: {
                        Label("立即開始課程動態", systemImage: "play.circle")
                    }
                }
            } header: {
                Text("課程動態（Live Activity）")
            } footer: {
                Text("在鎖定畫面與靈動島顯示目前這節課的下課倒數、以及下一節課何時開始。自動顯示需要你開啟 App 或系統背景刷新時才會更新;若要完全自動每天跳出需要推播伺服器(尚未支援)。")
            }

            Section("教務") {
                serviceLink("成績", "chart.bar.doc.horizontal", Theme.iconMaroon) { GradesView() }
                serviceLink("修業進度管制", "chart.pie.fill", Theme.iconMaroon) { ProgressControlView() }
            }

            Section("選課相關") {
                serviceLink("選課結果", "calendar.badge.plus", Theme.iconMaroon) { PreScheduleView() }
                serviceLink("公開課表查詢", "magnifyingglass", Theme.iconMaroon) { PublicScheduleView() }
            }

            Section("學生事務") {
                serviceLink("請假 / 缺曠", "list.bullet.clipboard", Theme.iconAmber) { AttendanceView() }
                serviceLink("請假申請", "square.and.pencil", Theme.iconAmber) { LeaveApplyView() }
                serviceLink("操行 / 獎懲", "star.circle.fill", Theme.iconAmber) { ConductView() }
                serviceLink("在學證明", "checkmark.seal.fill", Theme.iconAmber) { EnrollmentCertificateView() }
            }

            Section("Moodle 教學平台") {
                serviceLink("課程公告", "megaphone.fill", Theme.iconBlue) { AnnouncementsView() }
            }

            Section {
                webLinkRow("開啟 iNTUE 校務系統", "building.columns.fill", Theme.iconMaroon,
                           url: "https://nsa.ntue.edu.tw/Alltop", title: "iNTUE 校務系統")
                webLinkRow("開啟 Moodle 教學平台", "graduationcap.fill", Theme.iconBlue,
                           url: "https://md.ntue.edu.tw", title: "Moodle 教學平台")
            } header: {
                Text("校園網站")
            } footer: {
                Text("沿用 App 內的登入狀態直接開啟原始網站，無需再次登入;若 App 尚未支援的功能可從這裡操作。")
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
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("關於", systemImage: "info.circle")
                }
            }

            #if DEBUG
            Section {
                NavigationLink {
                    DevToolsView()
                } label: {
                    Label("開發者工具", systemImage: "hammer.fill")
                }
            } footer: {
                Text("僅 Debug 版本顯示:注入測試課表以驗證小工具與課程動態。")
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("其他服務")
        .onAppear { liveRunning = LiveActivityController.shared.isRunning }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
        }
        .sheet(item: $webLink) { link in
            NTUEWebSheet(url: link.url, title: link.title)
        }
    }

    private func webLinkRow(_ title: String, _ icon: String, _ color: Color, url: String, title sheetTitle: String) -> some View {
        Button {
            if let u = URL(string: url) { webLink = WebLink(url: u, title: sheetTitle) }
        } label: {
            Label {
                Text(title).foregroundStyle(.primary)
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
                if !appState.studentInfo.studentId.isEmpty {
                    Text(appState.studentInfo.studentId).font(.caption).foregroundStyle(.secondary)
                }
                let info = appState.studentInfo
                let line = [info.department, info.className, info.gradeLabel]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "　")
                if !line.isEmpty {
                    Text(line).font(.caption).foregroundStyle(.secondary)
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

/// Identifies a website to open inside `NTUEWebSheet`, reusing the login session.
private struct WebLink: Identifiable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("NTUE 非官方校園 App")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("版本", value: version)
                LabeledContent("作者", value: "CHENG RUEI HSU")
            }

            Section {
                Text("本 App 為學生自製，非學校官方出品；資料以 iNTUE 校務系統與 Moodle 教學平台為準。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("關於")
        .navigationBarTitleDisplayMode(.inline)
    }
}

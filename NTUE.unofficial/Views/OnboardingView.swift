import SwiftUI

/// First-launch (and re-triggerable) introduction. Explains what the app is,
/// stresses that it is **unofficial**, that the authoritative data lives in the
/// iNTUE 校務系統 and Moodle 教學平台, then points the user at the login screen.
struct OnboardingView: View {
    /// Called when the user finishes or skips. The caller decides what to do
    /// (mark as seen + reveal login, or just dismiss).
    var onFinish: () -> Void

    @State private var page = 0
    private let lastPage = 3

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                skipBar
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    disclaimerPage.tag(2)
                    loginPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                dots
                continueButton
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Top bar

    private var skipBar: some View {
        HStack {
            Spacer()
            if page < lastPage {
                Button("略過") { onFinish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(height: 44)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        page(
            icon: "graduationcap.fill",
            title: "NTUE unofficial",
            subtitle: "把國立臺北教育大學的課表、成績、作業與校園服務，整合到一個 App。"
        ) {
            Text("學生自製・非官方 App")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accentSoft, in: Capsule())
        }
    }

    private var featuresPage: some View {
        page(
            icon: "square.grid.2x2.fill",
            title: "一個 App，全部搞定",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 16) {
                featureRow("house.fill", "首頁", "下一堂課、今日課表、作業截止、學期倒數")
                featureRow("calendar", "課表", "個人週課表，一眼看完整學期")
                featureRow("checklist", "作業", "Moodle 各課作業與繳交狀態")
                featureRow("square.grid.2x2.fill", "其他服務", "成績、缺曠、操行獎懲、請假、在學證明…")
            }
            .padding(.horizontal, 8)
        }
    }

    private var disclaimerPage: some View {
        page(
            icon: "checkmark.shield.fill",
            title: "資料以官方系統為準",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 14) {
                bullet("本 App 由學生製作，並非學校官方出品。")
                bullet("所有成績、課表、作業等資料，皆即時取自 iNTUE 校務系統 與 Moodle 教學平台。")
                bullet("如顯示內容與官方系統不一致，一律以官方系統為準。")
            }
            .padding(18)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.15), lineWidth: 1))
            .padding(.horizontal, 4)
        }
    }

    private var loginPage: some View {
        page(
            icon: "person.badge.key.fill",
            title: "開始使用",
            subtitle: "接下來請用你的「校園入口網」帳號密碼登入，就能開始使用所有功能。"
        ) {
            Label("帳號密碼只用於登入官方系統，僅保存在這支裝置上。", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Building blocks

    private func page<Extra: View>(icon: String, title: String, subtitle: String?, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(Theme.accent)
                .frame(width: 96, height: 96)
                .background(Theme.accentSoft, in: Circle())
            Text(title)
                .font(.title.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            extra()
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func featureRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0...lastPage, id: \.self) { i in
                Circle()
                    .fill(i == page ? Theme.accent : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, 20)
    }

    private var continueButton: some View {
        Button {
            if page < lastPage {
                withAnimation { page += 1 }
            } else {
                onFinish()
            }
        } label: {
            Text(page == lastPage ? "開始使用" : "下一步")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 24)
    }
}

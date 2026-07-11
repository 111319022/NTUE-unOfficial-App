import SwiftUI

/// First-launch (and re-triggerable) introduction. Explains what the app is,
/// stresses that it is **unofficial**, that the authoritative data lives in the
/// iNTUE 校務系統 and Moodle 教學平台, then points the user at the login screen.
struct OnboardingView: View {
    /// Called when the user finishes or skips. The caller decides what to do
    /// (mark as seen + reveal login, or just dismiss).
    var onFinish: () -> Void

    @State private var page = 0
    @State private var appeared = false
    private let lastPage = 3

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ambientBlobs

            VStack(spacing: 0) {
                skipBar
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    disclaimerPage.tag(2)
                    loginPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                dots
                continueButton
            }
            .padding(.bottom, 24)
        }
        .onAppear { appeared = true }
    }

    private func isActive(_ index: Int) -> Bool {
        appeared && page == index
    }

    // MARK: - Ambient background

    /// Two soft colour blobs that drift with the current page (parallax).
    private var ambientBlobs: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: 150 - CGFloat(page) * 60, y: -280)
            Circle()
                .fill(Theme.amber.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -160 + CGFloat(page) * 40, y: 300)
        }
        .animation(.spring(duration: 1.0), value: page)
        .ignoresSafeArea()
    }

    // MARK: - Top bar

    private var skipBar: some View {
        HStack {
            Spacer()
            if page < lastPage {
                Button("略過") { onFinish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(height: 44)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    // MARK: - Page 1 · Welcome

    private var welcomePage: some View {
        let active = isActive(0)
        return VStack(spacing: 24) {
            Spacer()
            mockCardStack(active: active)
            VStack(spacing: 12) {
                (Text("NTUE").foregroundStyle(.primary)
                 + Text(".unofficial").foregroundStyle(Theme.accent))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .reveal(active, index: 3)
                Text("把國立臺北教育大學的課表、成績、\n作業與校園服務，整合到一個 App。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .reveal(active, index: 4)
                Text("非官方 App")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.accentSoft, in: Capsule())
                    .reveal(active, index: 5)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    /// A tilted stack of miniature "real UI" cards — the product as the hero.
    private func mockCardStack(active: Bool) -> some View {
        ZStack {
            mockCard(rotation: 3, floatDuration: 3.1) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("作業 · 明天截止")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.amber)
                    Text("教育心理學 反思報告")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 190)
            .offset(x: 64, y: 10)
            .reveal(active, index: 1)

            mockCard(rotation: -3, floatDuration: 2.6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下一堂課 · 10:10")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("國音及說話")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("篤行樓 401")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 200)
            .offset(x: -48, y: -62)
            .reveal(active, index: 0)

            mockCard(rotation: 2, floatDuration: 3.5, background: Theme.accentFill) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本學期")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                    Text("第 7 週 · 還有 87 天")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 195)
            .offset(x: -30, y: 72)
            .reveal(active, index: 2)
        }
        .frame(height: 220)
    }

    private func mockCard<Content: View>(
        rotation: Double, floatDuration: Double,
        background: Color = Theme.cardBackground,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.accent.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
            .rotationEffect(.degrees(rotation))
            .floating(duration: floatDuration)
    }

    // MARK: - Page 2 · Features

    private var featuresPage: some View {
        let active = isActive(1)
        return VStack(spacing: 26) {
            Spacer()
            Text("一個 App，全部搞定")
                .font(.title.bold())
                .reveal(active, index: 0)
            VStack(alignment: .leading, spacing: 16) {
                featureRow("house.fill", "首頁", "下一堂課、今日課表、作業截止、學期倒數")
                    .reveal(active, index: 1)
                featureRow("calendar", "課表", "個人週課表，一眼看完整學期")
                    .reveal(active, index: 2)
                featureRow("checklist", "作業", "Moodle 各課作業與繳交狀態")
                    .reveal(active, index: 3)
                featureRow("square.grid.2x2.fill", "其他服務", "成績、缺曠、操行獎懲、請假、在學證明…")
                    .reveal(active, index: 4)
            }
            .padding(.horizontal, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Page 3 · Disclaimer

    private var disclaimerPage: some View {
        let active = isActive(2)
        return VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.accent)
                .frame(width: 96, height: 96)
                .background(Theme.accentSoft, in: Circle())
                .symbolEffect(.bounce, value: active)
                .reveal(active, index: 0)
            Text("資料以官方系統為準")
                .font(.title.bold())
                .reveal(active, index: 1)
            VStack(alignment: .leading, spacing: 14) {
                bullet("本 App 並非學校官方出品。")
                bullet("所有成績、課表、作業等資料，皆即時取自 iNTUE 校務系統 與 Moodle 教學平台。")
                bullet("如顯示內容與官方系統不一致，一律以官方系統為準。")
            }
            .padding(18)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.15), lineWidth: 1))
            .reveal(active, index: 2)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Page 4 · Login prompt

    private var loginPage: some View {
        let active = isActive(3)
        return VStack(spacing: 22) {
            Spacer()
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.accent)
                .frame(width: 96, height: 96)
                .background(Theme.accentSoft, in: Circle())
                .symbolEffect(.bounce, value: active)
                .reveal(active, index: 0)
            Text("開始使用")
                .font(.title.bold())
                .reveal(active, index: 1)
            Text("接下來請用你的「校園入口網」帳號密碼登入，\n就能開始使用所有功能。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .reveal(active, index: 2)
            Label("帳號密碼只用於登入官方系統，僅保存在這支裝置上。", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 24)
                .reveal(active, index: 3)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Building blocks

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
                Capsule()
                    .fill(i == page ? Theme.accent : Color.secondary.opacity(0.3))
                    .frame(width: i == page ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: page)
        .padding(.bottom, 20)
    }

    private var continueButton: some View {
        Button {
            if page < lastPage {
                withAnimation(.spring(duration: 0.5)) { page += 1 }
            } else {
                onFinish()
            }
        } label: {
            HStack(spacing: 8) {
                Text(page == lastPage ? "開始使用" : "下一步")
                    .font(.headline)
                    .contentTransition(.opacity)
                Image(systemName: page == lastPage ? "arrow.right.circle.fill" : "arrow.right")
                    .font(.headline)
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.accentFill, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, 24)
    }
}

// MARK: - Animation helpers

/// Staggered entrance: fades + slides an element in when its page becomes
/// active; `index` sets the stagger order.
private struct RevealModifier: ViewModifier {
    let isActive: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 28)
            .animation(
                isActive
                    ? .spring(duration: 0.55, bounce: 0.25).delay(0.12 + 0.08 * Double(index))
                    : .easeIn(duration: 0.15),
                value: isActive
            )
    }
}

/// Gentle perpetual vertical drift, so the card stack feels alive.
private struct FloatingModifier: ViewModifier {
    var duration: Double
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -4 : 4)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

private extension View {
    func reveal(_ isActive: Bool, index: Int) -> some View {
        modifier(RevealModifier(isActive: isActive, index: index))
    }

    func floating(duration: Double) -> some View {
        modifier(FloatingModifier(duration: duration))
    }
}

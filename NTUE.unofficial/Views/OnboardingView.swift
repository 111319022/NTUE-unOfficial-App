import SwiftUI

/// 第一次開啟（或從設定重看）的介紹。四頁：這是什麼 → 有什麼 → 資料哪來 →
/// 去登入。排版和登入／初始化頁同一套：滿版插圖在上、左對齊的字在下、
/// 底部固定的操作列。
struct OnboardingView: View {
    /// 使用者看完或略過時呼叫。
    var onFinish: () -> Void

    @State private var step = 0
    @State private var forward = true

    private let lastStep = 3
    private var total: Int { lastStep + 1 }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if step > 0 {
                    header
                        .transition(.opacity)
                }

                ZStack {
                    page
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .frame(maxHeight: .infinity)

                footer
            }
        }
        .animation(.spring(duration: 0.45), value: step)
    }

    // MARK: - 頂端：進度 + 略過

    private var header: some View {
        HStack(spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(8, geo.size.width * CGFloat(step + 1) / CGFloat(total)))
                }
            }
            .frame(height: 3)

            Text(String(format: "%02d/%02d", step + 1, total))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            if step < lastStep {
                Button("略過") {
                    AuthHaptic.tap()
                    onFinish()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(height: 44)
    }

    // MARK: - 四頁

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: welcomePage
        case 1: featuresPage
        case 2: sourcePage
        default: startPage
        }
    }

    private var welcomePage: some View {
        StepPage { appeared in
            DeskHero(appeared: appeared)
        } content: { appeared in
            (Text("NTUE").foregroundStyle(Theme.accent)
             + Text(".unofficial").foregroundStyle(Theme.accent.opacity(0.5)))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(0.2)
                .authReveal(appeared, 0)

            AuthTitle(text: "把學校的事，\n收在同一個地方")
                .authReveal(appeared, 1)

            AuthBody(text: "課表、成績、作業、請假、在學證明 —— 原本要在校務系統和 Moodle 之間切來切去的東西，這裡一次看完。")
                .authReveal(appeared, 2)

            Text("學生自己做的，非官方 App")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
                .authReveal(appeared, 3)
        }
    }

    private var featuresPage: some View {
        StepPage { appeared in
            TimetableHero(appeared: appeared)
        } content: { appeared in
            AuthEyebrow(text: "What's inside")
                .authReveal(appeared, 0)

            AuthTitle(text: "四個分頁，就這樣", size: 25)
                .authReveal(appeared, 1)

            VStack(alignment: .leading, spacing: 14) {
                numberedRow("01", "首頁", "下一堂課、今天的課表、快到期的作業、學期倒數")
                    .authReveal(appeared, 2)
                numberedRow("02", "課表", "個人週課表，一眼看完整個學期")
                    .authReveal(appeared, 3)
                numberedRow("03", "作業", "Moodle 各科作業與繳交狀態")
                    .authReveal(appeared, 4)
                numberedRow("04", "其他服務", "成績、缺曠、操行獎懲、請假、在學證明")
                    .authReveal(appeared, 5)
            }
            .padding(.top, 2)
        }
    }

    private var sourcePage: some View {
        StepPage { appeared in
            DataFlowHero(appeared: appeared)
        } content: { appeared in
            AuthEyebrow(text: "Data source")
                .authReveal(appeared, 0)

            AuthTitle(text: "資料直接跟學校要", size: 25)
                .authReveal(appeared, 1)

            VStack(alignment: .leading, spacing: 13) {
                ruledLine("畫面上的成績、課表、作業，都是當下向 iNTUE 校務系統與 Moodle 取得的。")
                    .authReveal(appeared, 2)
                ruledLine("這個 App 不是學校官方出品，中間也沒有其他伺服器。")
                    .authReveal(appeared, 3)
                ruledLine("如果顯示的內容和官方系統不一樣，一律以官方系統為準。")
                    .authReveal(appeared, 4)
            }
            .padding(.top, 2)
        }
    }

    private var startPage: some View {
        StepPage { appeared in
            // 和登入頁同一張校園小景、同樣的燈數 —— 這一頁關掉之後
            // 插圖就留在原地，接著就是登入畫面。
            CampusScene(litWindows: 3, appeared: appeared)
        } content: { appeared in
            AuthEyebrow(text: "Ready")
                .authReveal(appeared, 0)

            AuthTitle(text: "準備好了，來登入吧")
                .authReveal(appeared, 1)

            AuthBody(text: "接下來用你在 iNTUE 校務系統（校園入口網）的帳號密碼登入，就可以開始用了。")
                .authReveal(appeared, 2)

            Text("帳號密碼只會存在這支手機的 Keychain，只用來登入學校系統。")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .authReveal(appeared, 3)
        }
    }

    // MARK: - 內文元件

    private func numberedRow(_ index: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func ruledLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Theme.accent.opacity(0.35))
                .frame(width: 2.5)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 底部操作列

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button(action: goBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Theme.accentFill, in: Circle())
                }
                .buttonStyle(PressScaleStyle())
                .transition(.scale.combined(with: .opacity))
            }

            AuthPrimaryButton(title: step == lastStep ? "開始使用" : "下一步", action: goNext)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func goNext() {
        if step < lastStep {
            AuthHaptic.tap()
            forward = true
            step += 1
        } else {
            AuthHaptic.commit()
            onFinish()
        }
    }

    private func goBack() {
        AuthHaptic.step()
        forward = false
        step = max(0, step - 1)
    }
}

// MARK: - 單頁的骨架

/// 插圖在上、文字在下，兩者都在這一頁出現時才開始動。
private struct StepPage<Hero: View, Content: View>: View {
    @ViewBuilder var hero: (Bool) -> Hero
    @ViewBuilder var content: (Bool) -> Content

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            hero(appeared)
                .frame(height: 250)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content(appeared)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }
}

#Preview {
    OnboardingView {}
}

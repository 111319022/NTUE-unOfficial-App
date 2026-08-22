import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var username = KeychainHelper.load(key: "ntue_username") ?? ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var appeared = false
    @State private var shakes: CGFloat = 0
    @FocusState private var focused: Field?

    private enum Field { case account, password }

    /// 回訪的人（Keychain 裡還留著上次的學號）看到的文案跟第一次來的不一樣。
    private let isReturning = (KeychainHelper.load(key: "ntue_username")?.isEmpty == false)

    private var keyboardUp: Bool { focused != nil }

    /// 邊填欄位，樓裡的燈邊一盞一盞亮起來 —— 剩下的留給初始化畫面點完。
    private var litWindows: Int {
        3 + (username.isEmpty ? 0 : 3) + (password.isEmpty ? 0 : 3)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                CampusScene(litWindows: litWindows, appeared: appeared)
                    .frame(height: keyboardUp ? 156 : 262)
                    .animation(.spring(duration: 0.42), value: keyboardUp)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headline
                        form
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)

                footer
            }
        }
        .modifier(ShakeEffect(shakes: shakes))
        .onAppear { appeared = true }
        .onChange(of: appState.loginError) { _, error in
            guard error != nil else { return }
            AuthHaptic.failure()
            withAnimation(.linear(duration: 0.45)) { shakes += 1 }
        }
    }

    // MARK: - 標題

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            wordmark
                .authReveal(appeared, 0)

            AuthTitle(text: isReturning ? "又見面了" : "先登入，\n才看得到你的課表")
                .authReveal(appeared, 1)

            if !keyboardUp {
                AuthBody(text: isReturning
                         ? "登入之後，課表、成績和作業就會自己回到這裡。"
                         : "用你在 iNTUE 校務系統（校園入口網）的同一組帳號密碼就可以了。")
                    .authReveal(appeared, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.4), value: keyboardUp)
    }

    /// App 的字標。等寬字、幾乎不加字距，看起來像個名字，
    /// 而不是被拆開來唸的字母。
    private var wordmark: some View {
        (Text("NTUE").foregroundStyle(Theme.accent)
         + Text(".unofficial").foregroundStyle(Theme.accent.opacity(0.5)))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .tracking(0.2)
    }

    // MARK: - 表單

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(label: "學號", isFocused: focused == .account) {
                TextField("例如 112345678", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.username)
                    .focused($focused, equals: .account)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }
            .authReveal(appeared, 3)

            field(
                label: "密碼",
                isFocused: focused == .password,
                accessory: password.isEmpty ? nil : (showPassword ? "隱藏" : "顯示"),
                accessoryAction: {
                    showPassword.toggle()
                    focused = .password
                }
            ) {
                Group {
                    if showPassword {
                        TextField("校園入口網密碼", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("校園入口網密碼", text: $password)
                    }
                }
                .textContentType(.password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit(attemptLogin)
            }
            .authReveal(appeared, 4)

            if let error = appState.loginError {
                AuthNotice(text: error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !keyboardUp {
                perks.transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.35), value: appState.loginError)
        .animation(.spring(duration: 0.4), value: keyboardUp)
    }

    /// 登入之後拿得到什麼。刻意寫成一行說明文字 —— 做成一顆顆的標籤會讓人
    /// 以為可以點。
    private var perks: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2.5)
            Text("登入後，課表、成績、作業、請假與在學證明都會在這裡。")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
    }

    private func field<Content: View>(
        label: String,
        isFocused: Bool,
        accessory: String? = nil,
        accessoryAction: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(isFocused ? Theme.accent : .secondary)

            HStack(spacing: 10) {
                content()
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))

                if let accessory {
                    Button(accessory, action: accessoryAction)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isFocused ? Theme.accent : Color.primary.opacity(0.09),
                            lineWidth: isFocused ? 1.6 : 1)
            )
        }
        .animation(.snappy(duration: 0.22), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: accessory)
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 12) {
            AuthPrimaryButton(
                title: "登入",
                busyTitle: "驗證中",
                isBusy: appState.isAuthenticating,
                isEnabled: canSubmit,
                action: attemptLogin
            )
            .authReveal(appeared, 5)

            Text("帳號密碼只會存在這支手機的 Keychain，只用來登入學校系統。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .authReveal(appeared, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 動作

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !appState.isAuthenticating
    }

    private func attemptLogin() {
        guard canSubmit else { return }
        focused = nil
        AuthHaptic.commit()
        Task { await appState.login(username: username, password: password) }
    }
}

// MARK: - 登入失敗時的搖頭

private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: sin(shakes * .pi * 6) * 7, y: 0)
        )
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}

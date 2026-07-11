import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var username = KeychainHelper.load(key: "ntue_username") ?? ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var appeared = false
    @State private var shakes: CGFloat = 0
    @FocusState private var focused: Field?

    private enum Field { case account, password }

    private var keyboardActive: Bool { focused != nil }

    var body: some View {
        ZStack {
            MaroonMeshBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                panel
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.05)) {
                appeared = true
            }
        }
        .onChange(of: appState.loginError) { _, error in
            guard error != nil else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.45)) { shakes += 1 }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: keyboardActive ? 8 : 16) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: keyboardActive ? 30 : 44))
                .foregroundStyle(.white)
                .frame(width: keyboardActive ? 64 : 92, height: keyboardActive ? 64 : 92)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.continuous))

            VStack(spacing: 6) {
                (Text("NTUE").foregroundStyle(.white)
                 + Text(".unofficial").foregroundStyle(.white.opacity(0.55)))
                    .font(.system(size: keyboardActive ? 24 : 32, weight: .bold, design: .rounded))

                if !keyboardActive {
                    Text("國立臺北教育大學 · 非官方 App")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.top, keyboardActive ? 16 : 48)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -16)
        .animation(.spring(duration: 0.45), value: keyboardActive)
    }

    // MARK: - Bottom panel

    private var panel: some View {
        VStack(spacing: 18) {
            HStack {
                Text(username.isEmpty ? "開始使用" : "歡迎回來")
                    .font(.title3.bold())
                    .contentTransition(.opacity)
                Spacer()
            }

            loginField(
                title: "學號 / 帳號", systemImage: "person.fill",
                isFocused: focused == .account
            ) {
                TextField("請輸入帳號", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.username)
                    .focused($focused, equals: .account)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }

            loginField(
                title: "密碼", systemImage: "lock.fill",
                isFocused: focused == .password
            ) {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("請輸入密碼", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("請輸入密碼", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(attemptLogin)

                    if !password.isEmpty {
                        Button {
                            showPassword.toggle()
                            focused = .password
                        } label: {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let error = appState.loginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            loginButton

            Label("帳密僅用於登入官方系統，加密存於本機 Keychain", systemImage: "shield.lefthalf.filled")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background {
            Theme.cardBackground
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
                .ignoresSafeArea(.all, edges: .bottom)
        }
        .modifier(ShakeEffect(shakes: shakes))
        .animation(.spring(duration: 0.35), value: appState.loginError)
    }

    private var loginButton: some View {
        Button(action: attemptLogin) {
            ZStack {
                if appState.isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text("登入").font(.headline)
                }
            }
            .frame(maxWidth: appState.isAuthenticating ? 56 : .infinity)
            .frame(height: 56)
            .background(
                canSubmit || appState.isAuthenticating ? Theme.accentFill : Color.gray.opacity(0.35),
                in: Capsule()
            )
            .foregroundStyle(.white)
        }
        .disabled(!canSubmit)
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: appState.isAuthenticating)
        .animation(.easeInOut(duration: 0.2), value: canSubmit)
    }

    // MARK: - Helpers

    private func loginField<Content: View>(
        title: String, systemImage: String, isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFocused ? Theme.accent : .secondary)
            content()
                .textFieldStyle(.plain)
                .padding(14)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isFocused ? Theme.accent : .clear, lineWidth: 1.5)
                )
        }
        .animation(.snappy(duration: 0.25), value: isFocused)
    }

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !appState.isAuthenticating
    }

    private func attemptLogin() {
        guard canSubmit else { return }
        focused = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await appState.login(username: username, password: password) }
    }
}

// MARK: - Animated maroon mesh background

/// Slowly drifting maroon mesh — the brand backdrop behind the login panel.
private struct MaroonMeshBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5],
                    [0.5 + 0.22 * Float(sin(t * 0.43)), 0.5 + 0.18 * Float(cos(t * 0.31))],
                    [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    Color(red: 0.33, green: 0.09, blue: 0.10),
                    Color(red: 0.47, green: 0.13, blue: 0.13),
                    Color(red: 0.30, green: 0.08, blue: 0.10),
                    Color(red: 0.52, green: 0.16, blue: 0.14),
                    Color(red: 0.62, green: 0.22, blue: 0.18),
                    Color(red: 0.42, green: 0.12, blue: 0.12),
                    Color(red: 0.28, green: 0.07, blue: 0.09),
                    Color(red: 0.44, green: 0.14, blue: 0.12),
                    Color(red: 0.35, green: 0.10, blue: 0.11)
                ]
            )
        }
    }
}

// MARK: - Shake

/// Horizontal shake driven by an incrementing trigger — used on login failure.
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

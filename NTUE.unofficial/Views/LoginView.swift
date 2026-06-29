import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var username = KeychainHelper.load(key: "ntue_username") ?? ""
    @State private var password = ""
    @FocusState private var focused: Field?

    private enum Field { case account, password }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accent, Theme.accent.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    card
                    footer
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
            Text("iNTUE")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("國立臺北教育大學 · 校務系統")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.top, 40)
    }

    private var card: some View {
        VStack(spacing: 18) {
            field(title: "學號 / 帳號", systemImage: "person.fill") {
                TextField("請輸入帳號", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focused, equals: .account)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }

            field(title: "密碼", systemImage: "lock.fill") {
                SecureField("請輸入密碼", text: $password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(attemptLogin)
            }

            if let error = appState.loginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: attemptLogin) {
                ZStack {
                    if appState.isAuthenticating {
                        ProgressView().tint(.white)
                    } else {
                        Text("登入").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(canSubmit ? Theme.accent : Color.gray.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canSubmit)
        }
        .padding(22)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
    }

    private var footer: some View {
        Text("非官方 App · 帳號密碼僅以加密方式儲存在本機 Keychain")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
    }

    // MARK: - Helpers

    private func field<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !appState.isAuthenticating
    }

    private func attemptLogin() {
        guard canSubmit else { return }
        focused = nil
        Task { await appState.login(username: username, password: password) }
    }
}

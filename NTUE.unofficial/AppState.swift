import Foundation

@Observable
@MainActor
final class AppState {
    enum Phase {
        case launching      // checking saved session
        case loggedOut
        case loggedIn
    }

    var phase: Phase = .launching
    var isAuthenticating = false
    var loginError: String?
    var username = ""
    var studentInfo = StudentInfo()

    private let auth = AuthService.shared
    private let service = NTUEService.shared

    // MARK: - Login

    func login(username: String, password: String) async {
        isAuthenticating = true
        loginError = nil
        do {
            try await auth.login(username: username, password: password)
            KeychainHelper.save(key: "ntue_username", value: username)
            KeychainHelper.save(key: "ntue_password", value: password)
            self.username = username
            await refreshStudentInfo()
            phase = .loggedIn
        } catch {
            loginError = error.localizedDescription
        }
        isAuthenticating = false
    }

    func logout() {
        auth.logout()
        DataStore.shared.clear()
        KeychainHelper.delete(key: "ntue_password")
        studentInfo = StudentInfo()
        phase = .loggedOut
    }

    /// On launch: reuse a live session, else silently re-login with saved credentials.
    func restoreSession() async {
        if await auth.isAuthenticated() {
            username = KeychainHelper.load(key: "ntue_username") ?? ""
            await refreshStudentInfo()
            phase = .loggedIn
            return
        }
        if let user = KeychainHelper.load(key: "ntue_username"),
           let pass = KeychainHelper.load(key: "ntue_password") {
            await login(username: user, password: pass)
            // login() sets phase to .loggedIn on success; otherwise fall through.
            if phase != .loggedIn { phase = .loggedOut }
            return
        }
        phase = .loggedOut
    }

    private func refreshStudentInfo() async {
        let info = await service.loadStudentInfo()
        if !info.isEmpty {
            studentInfo = info
            // Warm the slow school pages in the background so screens open fast.
            DataStore.shared.prefetch(studentId: info.studentId)
        }
    }
}

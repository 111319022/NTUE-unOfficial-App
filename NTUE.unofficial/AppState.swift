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

    /// On launch: if we were logged in before, show the UI immediately using the
    /// cached profile and validate/refresh in the background (stale-while-revalidate).
    /// Only the genuine cold start (no saved credentials) blocks on the network.
    func restoreSession() async {
        let savedUser = KeychainHelper.load(key: "ntue_username")
        let hasPassword = KeychainHelper.load(key: "ntue_password") != nil
        let cachedInfo = Persistence.load(StudentInfo.self, for: .studentInfo)

        if let savedUser, hasPassword, let cachedInfo, !cachedInfo.isEmpty {
            // Instant: trust the cache, get the user into the app right away.
            username = savedUser
            studentInfo = cachedInfo
            phase = .loggedIn
            // Background: confirm the session is still valid and refresh data.
            Task { await validateAndRefresh() }
            return
        }

        // Cold start — no usable cache. Validate / log in before showing the UI.
        if await auth.isAuthenticated() {
            username = savedUser ?? ""
            await refreshStudentInfo()
            phase = .loggedIn
            return
        }
        if let savedUser, let pass = KeychainHelper.load(key: "ntue_password") {
            await login(username: savedUser, password: pass)
            if phase != .loggedIn { phase = .loggedOut }
            return
        }
        phase = .loggedOut
    }

    /// Background revalidation after an instant cached launch. `loadStudentInfo`
    /// doubles as the auth check (a logged-out request yields empty info).
    private func validateAndRefresh() async {
        let info = await service.loadStudentInfo()
        if !info.isEmpty {
            persist(info)
            DataStore.shared.prefetch(studentId: info.studentId)
            return
        }
        // Session is dead → try a silent re-login with saved credentials.
        if let user = KeychainHelper.load(key: "ntue_username"),
           let pass = KeychainHelper.load(key: "ntue_password") {
            do {
                try await auth.login(username: user, password: pass)
                await refreshStudentInfo()
            } catch {
                phase = .loggedOut
            }
        } else {
            phase = .loggedOut
        }
    }

    private func refreshStudentInfo() async {
        let info = await service.loadStudentInfo()
        if !info.isEmpty {
            persist(info)
            // Warm the slow school pages in the background so screens open fast.
            DataStore.shared.prefetch(studentId: info.studentId)
        }
    }

    private func persist(_ info: StudentInfo) {
        studentInfo = info
        Persistence.save(info, for: .studentInfo)
    }
}

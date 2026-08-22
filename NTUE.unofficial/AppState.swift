import Foundation

@Observable
@MainActor
final class AppState {
    enum Phase {
        case launching      // checking saved session
        case loggedOut
        case loggedIn
    }

    /// 初始化畫面上的四個步驟。順序就是實際發生的順序，畫面照著顯示，
    /// 不是隨便跑個進度條。
    enum BootStep: Int, Comparable, CaseIterable {
        case connecting   // 連線到校務系統
        case verifying    // 確認登入狀態
        case profile      // 讀取學籍資料
        case preparing    // 準備課表與作業

        var label: String {
            switch self {
            case .connecting: "連線到校務系統"
            case .verifying:  "確認登入狀態"
            case .profile:    "讀取學籍資料"
            case .preparing:  "準備課表與作業"
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var phase: Phase = .launching
    var bootStep: BootStep = .connecting
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
        bootStep = .verifying
        do {
            try await auth.login(username: username, password: password)
            KeychainHelper.save(key: "ntue_username", value: username)
            KeychainHelper.save(key: "ntue_password", value: password)
            self.username = username
            // 帳密確認過了 → 交棒給初始化畫面，剩下的等待才有東西可看。
            isAuthenticating = false
            bootStep = .profile
            phase = .launching
            await refreshStudentInfo()
            // 課表與作業的預抓在背景繼續；這裡停一拍，讓最後一步的動畫走完
            // 再切進主畫面，不然畫面會閃一下。
            bootStep = .preparing
            try? await Task.sleep(for: .milliseconds(420))
            phase = .loggedIn
        } catch {
            loginError = error.localizedDescription
            isAuthenticating = false
        }
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
        bootStep = .connecting
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
        bootStep = .verifying
        if await auth.isAuthenticated() {
            username = savedUser ?? ""
            bootStep = .profile
            await refreshStudentInfo()
            bootStep = .preparing
            try? await Task.sleep(for: .milliseconds(350))
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
            Task { await ensureProfileDetails() }
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
            Task { await ensureProfileDetails() }
        }
    }

    /// Reads 系所 + 入學學年 from the 在學證明 (once), so the profile can show
    /// department + auto-incrementing 年級. Cached in `studentInfo`.
    private func ensureProfileDetails() async {
        guard studentInfo.department.isEmpty || studentInfo.enrollmentYear == nil else { return }
        guard let cert = try? await service.loadEnrollmentCertificate(), !cert.department.isEmpty else { return }
        var info = studentInfo
        info.department = cert.department
        if let year = Int(cert.year), let grade = StudentInfo.gradeNumber(cert.grade) {
            info.enrollmentYear = year - (grade - 1)   // fixed anchor → 年級 +1 each 8/1
        }
        persist(info)
    }

    /// Persists student info, preserving cert-derived fields (系所/入學學年) that
    /// the grades-page refresh doesn't carry.
    private func persist(_ info: StudentInfo) {
        var merged = info
        if merged.department.isEmpty { merged.department = studentInfo.department }
        if merged.className.isEmpty { merged.className = studentInfo.className }
        if merged.enrollmentYear == nil { merged.enrollmentYear = studentInfo.enrollmentYear }
        studentInfo = merged
        Persistence.save(merged, for: .studentInfo)
    }
}

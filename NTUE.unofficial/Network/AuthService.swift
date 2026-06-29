import Foundation
import Security

enum AuthError: LocalizedError {
    case loginPageFetchFailed
    case missingHiddenFields
    case loginFailed(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .loginPageFetchFailed: return "無法取得登入頁面"
        case .missingHiddenFields: return "登入頁面格式異常，缺少必要欄位"
        case .loginFailed(let msg): return "登入失敗：\(msg)"
        case .sessionExpired: return "登入已過期，請重新登入"
        }
    }
}

struct AuthService {
    static let shared = AuthService()
    private let client = NTUEClient.shared

    private static let loginPageBase = "https://protocol.ntue.edu.tw/openidConnectServer.do"
    private static let loginPostURL = "https://protocol.ntue.edu.tw/openidConnectServerLogin.do"
    private static let redirectURI = "https://nsa.ntue.edu.tw/Alltop_Dery"
    private static let sessionCheckURL = "https://nsa.ntue.edu.tw/AstarProxy/IsServiceWorking.aspx"

    func login(username: String, password: String) async throws {
        let state = Int.random(in: 1_000_000_000...9_999_999_999)

        // Step 1 – fetch login page
        let loginPageURL = "\(Self.loginPageBase)?response_type=id_token&client_id=alltop&redirect_uri=\(Self.redirectURI)&state=\(state)"
        let html = try await client.get(loginPageURL)

        // Parse hidden fields
        guard let fields = parseLoginForm(html) else {
            throw AuthError.missingHiddenFields
        }

        // Step 2 – POST credentials
        var formData: [String: String] = [
            "muid": username,
            "mpassword": password,
            "response_type": "id_token",
            "client_id": "alltop",
            "redirect_uri": Self.redirectURI,
            "state": "\(state)",
            "code": fields.code,
            "oauthServer": fields.oauthServer,
        ]
        // Include any extra hidden fields found on the page
        for (k, v) in fields.extras { formData[k] = v }

        _ = try await client.post(Self.loginPostURL, form: formData, referer: loginPageURL)

        // Step 3 – verify we are *actually* authenticated.
        // NOTE: IsServiceWorking.aspx returns Working=1 even when logged out, so it
        // cannot be used to confirm login. Instead we check that an authenticated
        // page yields real student data.
        if !(await isAuthenticated()) {
            throw AuthError.loginFailed("帳號或密碼錯誤")
        }
    }

    /// True only when an authenticated iNTUE page returns real student data.
    func isAuthenticated() async -> Bool {
        guard let html = try? await client.get("\(NTUEClient.base)/a05/a052A0") else { return false }
        // A logged-out request is redirected to the portal login (no 學號 / form-group header).
        return !NTUEParser.studentInfo(from: html).isEmpty
    }

    func logout() {
        client.clearCookies()
    }

    // MARK: - HTML form parsing

    private struct LoginFormFields {
        let code: String
        let oauthServer: String
        let extras: [String: String]
    }

    private func parseLoginForm(_ html: String) -> LoginFormFields? {
        // Extract hidden input values using simple string parsing (no SwiftSoup needed for login page)
        var code = ""
        var oauthServer = ""
        var extras: [String: String] = [:]

        let inputs = extractInputs(from: html)
        for (name, value) in inputs {
            switch name {
            case "code": code = value
            case "oauthServer": oauthServer = value
            case "muid", "mpassword", "response_type", "client_id", "redirect_uri", "state": break
            default:
                if !name.isEmpty && !value.isEmpty {
                    extras[name] = value
                }
            }
        }

        guard !code.isEmpty || !oauthServer.isEmpty else {
            // Fields might be empty/optional - return with whatever we have
            return LoginFormFields(code: code, oauthServer: oauthServer, extras: extras)
        }
        return LoginFormFields(code: code, oauthServer: oauthServer, extras: extras)
    }

    private func extractInputs(from html: String) -> [(String, String)] {
        var results: [(String, String)] = []
        // Match <input ... name="X" ... value="Y" ...> and variants
        let pattern = #"<input[^>]+>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return results }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])
            let name = extractAttr("name", from: tag) ?? ""
            let value = extractAttr("value", from: tag) ?? ""
            if !name.isEmpty { results.append((name, value)) }
        }
        return results
    }

    private func extractAttr(_ attr: String, from tag: String) -> String? {
        let patterns = [
            "\(attr)=['\"]([^'\"]*)['\"]",
            "\(attr)=([^\\s>]+)",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(tag.startIndex..., in: tag)
                if let match = regex.firstMatch(in: tag, range: range),
                   let captureRange = Range(match.range(at: 1), in: tag) {
                    return String(tag[captureRange])
                }
            }
        }
        return nil
    }
}

// MARK: - Keychain helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.ntue.unofficial",
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.ntue.unofficial",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.ntue.unofficial",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

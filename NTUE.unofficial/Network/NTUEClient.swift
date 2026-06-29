import Foundation

/// Thin URLSession wrapper that keeps the iNTUE session cookie and speaks the
/// site's Laravel/DataTables conventions (CSRF token + JSON data islands).
final class NTUEClient: Sendable {
    static let shared = NTUEClient()

    static let base = "https://nsa.ntue.edu.tw"

    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        self.session = URLSession(configuration: config)
    }

    // MARK: - Requests

    func get(_ urlString: String, referer: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        applyCommonHeaders(&request, referer: referer)
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        return Self.decode(data)
    }

    func post(_ urlString: String, form: [String: String], referer: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        applyCommonHeaders(&request, referer: referer)
        request.httpBody = Self.encodeForm(form)
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        return Self.decode(data)
    }

    /// POST a raw JSON body (used by Moodle's `/lib/ajax/service.php`).
    func postJSON(_ urlString: String, json: Data, referer: String? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        applyCommonHeaders(&request, referer: referer)
        request.httpBody = json
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        return data
    }

    /// GET returning raw bytes (used for binary downloads such as PDFs).
    func getData(_ urlString: String, referer: String? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        return data
    }

    func clearCookies() {
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - Header helpers

    private func applyCommonHeaders(_ request: inout URLRequest, referer: String?) {
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(referer ?? Self.base, forHTTPHeaderField: "Referer")
    }

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func encodeForm(_ dict: [String: String]) -> Data {
        var comps = URLComponents()
        comps.queryItems = dict.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents encodes spaces as %20; site expects + but both are accepted.
        return (comps.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode < 400 else { throw URLError(.badServerResponse) }
    }
}

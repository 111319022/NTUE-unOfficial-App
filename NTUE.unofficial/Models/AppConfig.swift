import Foundation
import CloudKit

/// Remote app configuration — currently the 強制更新 gate. Maintained as a
/// single record in the CloudKit Dashboard (record name = `current`).
///
/// CloudKit record type: `AppConfig`  (recordName must be "current")
///   minVersion    String — 最低可用版本，例：`1.4.0`（低於此版就強制更新）
///   latestVersion String — 最新版本（可空，僅供顯示）
///   updateURL     String — App Store 連結（可空）
///   updateTitle   String — 提示標題（可空）
///   updateMessage String — 提示內文（可空）
struct AppConfig: Codable, Hashable {
    var minVersion: String?
    var latestVersion: String?
    var updateURL: String?
    var updateTitle: String?
    var updateMessage: String?

    /// The build's current short version, e.g. "1.4.0".
    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// True when the running app is older than `minVersion` → block with the gate.
    var forceUpdateRequired: Bool {
        guard let minVersion, !minVersion.isEmpty else { return false }
        return Self.compare(Self.currentVersion, isLessThan: minVersion)
    }

    /// Semantic-ish version compare ("1.4" < "1.4.1" < "1.10.0").
    static func compare(_ lhs: String, isLessThan rhs: String) -> Bool {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b }
        }
        return false
    }
}

extension AppConfig {
    init(record: CKRecord) {
        self.minVersion = record["minVersion"] as? String
        self.latestVersion = record["latestVersion"] as? String
        self.updateURL = record["updateURL"] as? String
        self.updateTitle = record["updateTitle"] as? String
        self.updateMessage = record["updateMessage"] as? String
    }

    func apply(to record: CKRecord) {
        if let minVersion { record["minVersion"] = minVersion }
        if let latestVersion { record["latestVersion"] = latestVersion }
        if let updateURL { record["updateURL"] = updateURL }
        if let updateTitle { record["updateTitle"] = updateTitle }
        if let updateMessage { record["updateMessage"] = updateMessage }
    }
}

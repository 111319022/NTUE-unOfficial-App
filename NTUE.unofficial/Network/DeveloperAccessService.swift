import Foundation
import CloudKit
import CryptoKit

/// Result of checking whether the current iCloud account may use the developer tools.
enum DeveloperAccessCheckResult {
    case allowed
    case denied(String)
}

enum DeveloperAccessError: LocalizedError {
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: return "iCloud 帳號不可用，請先到 設定 → Apple ID 登入 iCloud。"
        }
    }
}

/// Gates the in-app developer tools by an **iCloud-account whitelist stored in
/// CloudKit** — the same model used by the sibling TPASS app. Instead of
/// `#if DEBUG`, the tools appear (in any build, including TestFlight / App Store
/// releases) only when the running device's iCloud user record hash is listed in
/// the public `DevAccessPolicy` record. The whitelist is maintained by hand in
/// the CloudKit Dashboard — there is no in-app admin page.
///
/// ## One-time CloudKit setup
/// In the CloudKit Dashboard for `\(CloudKitConfig.containerID)` create a record:
/// - **Record Type:** `DevAccessPolicy`
/// - **Record Name:** `main-dev-access-policy`
/// - **Fields:** `enabled` (Int64, 1 = on) · `allowedUserHashes` (List<String>)
///
/// Run the app once and copy the hash shown under 開發者身分 in the dev tools (or the
/// `denied` message), then paste it into `allowedUserHashes`. Because release builds
/// talk to the **Production** environment, deploy the schema + record to Production
/// too (CloudKit Console → Deploy Schema Changes) for the gate to open off-device.
enum DeveloperAccessService {
    private static var container: CKContainer { CloudKitConfig.container }
    private static var database: CKDatabase { container.publicCloudDatabase }

    private static let policyRecordType = "DevAccessPolicy"
    private static let policyRecordName = "main-dev-access-policy"

    /// Whether the current iCloud account is on the developer whitelist.
    static func verifyCurrentUserAccess() async -> DeveloperAccessCheckResult {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                return .denied("iCloud 帳號不可用，無法驗證開發者權限。")
            }

            let userRecordID = try await container.userRecordID()
            let userHash = normalizedHash(sha256(userRecordID.recordName))

            let recordID = CKRecord.ID(recordName: policyRecordName)
            let policyRecord: CKRecord
            do {
                policyRecord = try await database.record(for: recordID)
            } catch let ckError as CKError where ckError.code == .unknownItem {
                return .denied("CloudKit 尚未建立白名單設定（DevAccessPolicy/\(policyRecordName)）。\n你的識別碼：\n\(userHash)")
            }

            guard policyRecord.recordType == policyRecordType else {
                return .denied("CloudKit 白名單設定格式錯誤（recordType 應為 DevAccessPolicy）。")
            }

            let enabled = boolValue(from: policyRecord["enabled"], defaultValue: true)
            guard enabled else {
                return .denied("開發者功能目前由遠端設定關閉。")
            }

            let allowedHashes = normalizedHashes(from: policyRecord["allowedUserHashes"] as? [String] ?? [])
            guard !allowedHashes.isEmpty else {
                return .denied("白名單目前為空。請在 CloudKit 的 DevAccessPolicy/\(policyRecordName) 的 allowedUserHashes 填入：\n\(userHash)")
            }

            guard allowedHashes.contains(userHash) else {
                return .denied("你目前不在白名單內。\n請把以下識別碼加入白名單：\n\(userHash)")
            }

            return .allowed
        } catch {
            return .denied("驗證開發者權限失敗：\(error.localizedDescription)")
        }
    }

    /// The current iCloud account's whitelist hash (nil if iCloud is unavailable).
    /// Shown in the dev tools so you can copy it into the CloudKit whitelist.
    static func currentUserHash() async -> String? {
        do {
            let status = try await container.accountStatus()
            guard status == .available else { return nil }
            let userRecordID = try await container.userRecordID()
            return normalizedHash(sha256(userRecordID.recordName))
        } catch {
            return nil
        }
    }

#if DEBUG
    /// One-time bootstrap: create/update `DevAccessPolicy/main-dev-access-policy`
    /// in the running CloudKit environment, enable it, and add **this device's**
    /// hash to the whitelist. Writing the record auto-creates the schema in the
    /// Development environment, so you never have to build the record type by hand
    /// in the Console. (Production schema is locked, so run this from a Debug build
    /// first, then Deploy to Production from the CloudKit Console.)
    ///
    /// **DEBUG-only on purpose.** Self-enrollment must never ship in a release
    /// binary — otherwise anyone who finds the 關於 → 作者 ×5 gesture could add their
    /// own iCloud account to the whitelist and gain CloudKit write access. In a
    /// release build the unlock sheet only *shows* the hash for manual whitelisting.
    static func enrollCurrentUser() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw DeveloperAccessError.iCloudUnavailable }

        let userRecordID = try await container.userRecordID()
        let hash = normalizedHash(sha256(userRecordID.recordName))

        let recordID = CKRecord.ID(recordName: policyRecordName)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            record = CKRecord(recordType: policyRecordType, recordID: recordID)
        }

        var hashes = Set(normalizedHashes(from: record["allowedUserHashes"] as? [String] ?? []))
        hashes.insert(hash)
        record["allowedUserHashes"] = hashes.sorted()
        record["enabled"] = 1

        _ = try await database.save(record)
    }
#endif

    // MARK: - Helpers

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func boolValue(from raw: CKRecordValueProtocol?, defaultValue: Bool) -> Bool {
        if let bool = raw as? Bool { return bool }
        if let number = raw as? NSNumber { return number.boolValue }
        return defaultValue
    }

    private static func normalizedHashes(from rawValues: [String]) -> [String] {
        var results: Set<String> = []
        for value in rawValues {
            let parts = value
                .replacingOccurrences(of: "\r", with: "\n")
                .split { $0 == "\n" || $0 == "," }
            for part in parts {
                let normalized = normalizedHash(String(part))
                if !normalized.isEmpty { results.insert(normalized) }
            }
        }
        return Array(results)
    }

    /// Keep only lowercase hex characters, so pasted hashes with stray spaces /
    /// newlines still match.
    private static func normalizedHash(_ input: String) -> String {
        input.lowercased().filter { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}

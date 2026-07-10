import Foundation
import CloudKit

/// Read-side helpers for the manifest-based storage scheme.
///
/// CloudKit's public database only lets you list records with a `CKQuery`, which
/// requires a *Queryable* index on `recordName` — and that index is **not** added
/// automatically when the schema is auto-created by saving records, nor can it be
/// added from the app (only in the CloudKit Console). To stay 100% Console-free we
/// avoid queries entirely: each record type has a **manifest** record (a fixed
/// recordName listing all child recordNames), so we can fetch everything by ID
/// (`records(for:)`), which needs no index at all.
enum CloudKitStore {
    /// All child records of a type, fetched via its manifest. Returns [] if the
    /// manifest doesn't exist yet.
    static func fetchList(manifest manifestName: String) async throws -> [CKRecord] {
        let ids = try await manifestIDs(manifestName)
        guard !ids.isEmpty else { return [] }
        let results = try await CloudKitConfig.publicDB.records(
            for: ids.map { CKRecord.ID(recordName: $0) })
        return results.values.compactMap { try? $0.get() }
    }

    /// The child recordNames listed in a manifest (empty if it doesn't exist).
    static func manifestIDs(_ manifestName: String) async throws -> [String] {
        do {
            let record = try await CloudKitConfig.publicDB.record(
                for: CKRecord.ID(recordName: manifestName))
            return (record["ids"] as? [String]) ?? []
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    /// Load a manifest record for mutation, creating a fresh one if it's absent.
    static func loadManifest(_ manifestName: String) async throws -> CKRecord {
        do {
            return try await CloudKitConfig.publicDB.record(
                for: CKRecord.ID(recordName: manifestName))
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: CloudKitConfig.RecordType.manifest,
                            recordID: CKRecord.ID(recordName: manifestName))
        }
    }
}

import Foundation
import CloudKit

/// Developer-only writer for the CloudKit public database — the backing store for
/// the in-app 管理後台 (`AdminView`). Lets you add/edit/delete 校園行事曆、學期
/// 起迄日期、強制更新設定 straight from the app instead of the CloudKit Console.
///
/// Records are enumerated via **manifests** (see `CloudKitStore`) rather than
/// CKQuery, so every write also updates the type's manifest to keep the list in
/// sync — no queryable index / Console setup required.
///
/// The build's CloudKit *environment* (Development vs Production) is fixed at
/// sign time: a plain Xcode debug build talks to **Development**; add the
/// `com.apple.developer.icloud-container-environment = Production` entitlement to
/// point this same debug build at **Production** (only after the schema has been
/// deployed there once).
enum CloudKitAdmin {
    /// A fresh recordName for a brand-new event.
    static func newEventID() -> String { "event-\(UUID().uuidString)" }

    // MARK: CalendarEvent

    static func save(event: CalendarEvent) async throws {
        let record = CKRecord(recordType: CloudKitConfig.RecordType.calendarEvent,
                              recordID: CKRecord.ID(recordName: event.id))
        event.apply(to: record)
        let manifest = try await CloudKitStore.loadManifest(CloudKitConfig.Manifest.events)
        add(event.id, to: manifest)
        try await save([record, manifest])
    }

    /// Bulk-save many events, touching the events manifest only once. Used by the
    /// 115 行事曆 importer. Idempotent when event ids are stable: `savePolicy .allKeys`
    /// overwrites existing records so re-running the import doesn't create duplicates.
    static func save(events: [CalendarEvent]) async throws {
        guard !events.isEmpty else { return }
        let manifest = try await CloudKitStore.loadManifest(CloudKitConfig.Manifest.events)
        var records: [CKRecord] = []
        for event in events {
            let record = CKRecord(recordType: CloudKitConfig.RecordType.calendarEvent,
                                  recordID: CKRecord.ID(recordName: event.id))
            event.apply(to: record)
            add(event.id, to: manifest)
            records.append(record)
        }
        // Save the event records first (chunked; the public DB default zone can't
        // commit large batches atomically), then the manifest so it never points at
        // an id that failed to write.
        let chunkSize = 300
        var i = 0
        while i < records.count {
            let chunk = Array(records[i..<min(i + chunkSize, records.count)])
            try await save(chunk, atomic: false)
            i += chunkSize
        }
        try await save([manifest], atomic: false)
    }

    static func deleteEvent(id: String) async throws {
        let manifest = try await CloudKitStore.loadManifest(CloudKitConfig.Manifest.events)
        remove(id, from: manifest)
        try await save([manifest], deleting: [CKRecord.ID(recordName: id)])
    }

    // MARK: AcademicTerm  (recordName convention: "term-<code>")

    static func termRecordName(_ code: String) -> String { "term-\(code)" }

    static func save(term: AcademicTerm) async throws {
        let name = termRecordName(term.code)
        let record = CKRecord(recordType: CloudKitConfig.RecordType.academicTerm,
                              recordID: CKRecord.ID(recordName: name))
        term.apply(to: record)
        let manifest = try await CloudKitStore.loadManifest(CloudKitConfig.Manifest.terms)
        add(name, to: manifest)
        try await save([record, manifest])
    }

    static func deleteTerm(code: String) async throws {
        let name = termRecordName(code)
        let manifest = try await CloudKitStore.loadManifest(CloudKitConfig.Manifest.terms)
        remove(name, from: manifest)
        try await save([manifest], deleting: [CKRecord.ID(recordName: name)])
    }

    // MARK: AppConfig (single record "current", fetched by ID — no manifest)

    static func save(config: AppConfig) async throws {
        let record = CKRecord(recordType: CloudKitConfig.RecordType.appConfig,
                              recordID: CKRecord.ID(recordName: CloudKitConfig.appConfigRecordName))
        config.apply(to: record)
        try await save([record])
    }

    // MARK: Manifest mutation

    private static func add(_ id: String, to manifest: CKRecord) {
        var ids = (manifest["ids"] as? [String]) ?? []
        if !ids.contains(id) { ids.append(id) }
        manifest["ids"] = ids
    }

    private static func remove(_ id: String, from manifest: CKRecord) {
        var ids = (manifest["ids"] as? [String]) ?? []
        ids.removeAll { $0 == id }
        manifest["ids"] = ids
    }

    // MARK: Save helper

    /// `.allKeys` overwrites the server copy regardless of change tag, so we can
    /// build a fresh record from the model and save without a fetch-modify cycle.
    private static func save(_ records: [CKRecord],
                             deleting ids: [CKRecord.ID] = [],
                             atomic: Bool = true) async throws {
        _ = try await CloudKitConfig.publicDB.modifyRecords(
            saving: records, deleting: ids, savePolicy: .allKeys, atomically: atomic)
    }
}

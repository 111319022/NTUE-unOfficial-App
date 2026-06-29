import Foundation
import WidgetKit

/// Reads / writes the `WidgetSnapshot` in the shared App Group container so the
/// widget and Live Activity (separate processes) can see the same data the app
/// last fetched.
enum SharedStore {
    /// Must match the App Group capability added to BOTH targets.
    static let appGroupID = "group.com.rayhsu63.NTUE-unofficial"

    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Persist the latest snapshot and ask the system to refresh the widgets.
    static func save(_ snapshot: WidgetSnapshot) {
        guard let fileURL, let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Load the last-written snapshot (or `.empty` if there isn't one yet).
    static func load() -> WidgetSnapshot {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    // Shared coders so both sides agree on the date representation.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

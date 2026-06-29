import Foundation

/// Tiny JSON-on-disk store for caching the last-known data so screens can paint
/// instantly on launch and refresh in the background (stale-while-revalidate).
enum Persistence {
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cache", isDirectory: true)
    }

    enum Key: String {
        case studentInfo
        case timetable
        case moodleDeadlines
    }

    static func save<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url(key), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: dir)
    }

    private static func url(_ key: Key) -> URL {
        dir.appendingPathComponent("\(key.rawValue).json")
    }

    // MARK: - Generic per-key store (used for past-semester snapshots)

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url(key), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func url(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safe).json")
    }
}

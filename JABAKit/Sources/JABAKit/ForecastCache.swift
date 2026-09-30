import Foundation

/// Keeps the last successful download of each feed on disk so the app still
/// works without signal (e.g. in a tent). Raw inputs are cached rather than
/// finished reports, so a cached forecast is re-scored against the current time.
public struct ForecastCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "ForecastCache", directoryHint: .isDirectory)
    }

    public static let kpKey = "kp-forecast"
    public static func weatherKey(_ id: UUID) -> String { "weather-\(id.uuidString)" }
    public static func nowcastKey(_ id: UUID) -> String { "nowcast-\(id.uuidString)" }

    public func store<Value>(_ snapshot: Snapshot<Value>, key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url(for: key), options: .atomic)
    }

    public func load<Value>(_: Value.Type, key: String) -> Snapshot<Value>? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(Snapshot<Value>.self, from: data)
    }

    public func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    private func url(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }
}

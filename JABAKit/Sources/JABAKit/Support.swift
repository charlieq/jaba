import Foundation

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

public enum ForecastError: LocalizedError, Sendable, Equatable {
    case badResponse(source: String, status: Int)
    case unexpectedFormat(source: String)

    public var errorDescription: String? {
        switch self {
        case let .badResponse(source, status):
            "\(source) returned HTTP \(status)."
        case let .unexpectedFormat(source):
            "\(source) returned data in an unexpected format."
        }
    }
}

/// A fetched value plus when it was fetched, so cached data can be shown with its age when offline.
public struct Snapshot<Value: Codable & Sendable>: Codable, Sendable {
    public let fetchedAt: Date
    public let value: Value

    public init(fetchedAt: Date = .now, value: Value) {
        self.fetchedAt = fetchedAt
        self.value = value
    }
}

/// Shared number/time formatting so the engine's reasoning text and the UI agree.
public enum AuroraFormat {
    public static func kp(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "°"
    }

    /// Whole degrees with a typographic minus, e.g. "−16°".
    public static func signedDegrees(_ value: Double) -> String {
        let whole = Int(value.rounded())
        return (whole < 0 ? "−\(-whole)" : "\(whole)") + "°"
    }

    /// Short clock time in the location's own time zone, honoring the user's 12/24-hour setting.
    public static func time(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Hour-only label for the hourly strip ("23" or "11 PM" depending on locale).
    public static func hour(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = timeZone
        return date.formatted(style)
    }

    public static func weekday(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    public static func timeRange(_ start: Date, _ end: Date, in timeZone: TimeZone) -> String {
        "\(time(start, in: timeZone))–\(time(end, in: timeZone))"
    }
}

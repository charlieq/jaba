import Foundation

/// One 3-hour UTC block of NOAA's planetary K-index product.
public struct KpBin: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case observed, estimated, predicted
    }

    public static let duration: TimeInterval = 3 * 3_600

    public let start: Date
    public let kp: Double
    public let kind: Kind
    /// NOAA geomagnetic storm scale ("G1"…"G5") when a storm is forecast.
    public let noaaScale: String?

    public init(start: Date, kp: Double, kind: Kind, noaaScale: String? = nil) {
        self.start = start
        self.kp = kp
        self.kind = kind
        self.noaaScale = noaaScale
    }

    public var end: Date { start.addingTimeInterval(Self.duration) }
}

/// NOAA SWPC's 3-day planetary Kp forecast: the data behind the UAF Geophysical
/// Institute's aurora forecast (gi.alaska.edu/monitors/aurora-forecast).
public struct KpForecast: Codable, Hashable, Sendable {
    public let bins: [KpBin]

    public init(bins: [KpBin]) {
        self.bins = bins.sorted { $0.start < $1.start }
    }

    public func bin(containing date: Date) -> KpBin? {
        bins.last { $0.start <= date && date < $0.end }
    }

    public var coverageEnd: Date? { bins.last?.end }

    /// Parses `noaa-planetary-k-index-forecast.json`. NOAA serves an array of
    /// objects; older versions served an array of rows with a header row, so both are accepted.
    public static func parseNOAA(_ data: Data) throws -> KpForecast {
        let source = "NOAA Kp forecast"
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ForecastError.unexpectedFormat(source: source)
        }

        var records: [[String: Any]] = []
        if let objects = rows as? [[String: Any]] {
            records = objects
        } else if let table = rows as? [[Any]], let header = table.first as? [String] {
            records = table.dropFirst().map { row in
                Dictionary(uniqueKeysWithValues: zip(header, row))
            }
        } else {
            throw ForecastError.unexpectedFormat(source: source)
        }

        var byStart: [Date: KpBin] = [:]
        for record in records {
            guard let tag = record["time_tag"] as? String,
                  let start = parseTimeTag(tag),
                  let kp = number(record["kp"])
            else { continue }
            let kind = (record["observed"] as? String).flatMap(KpBin.Kind.init(rawValue:)) ?? .predicted
            let scale = (record["noaa_scale"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            byStart[start] = KpBin(start: start, kp: kp, kind: kind, noaaScale: scale)
        }
        guard !byStart.isEmpty else { throw ForecastError.unexpectedFormat(source: source) }
        return KpForecast(bins: Array(byStart.values))
    }

    /// NOAA time tags are UTC without a zone suffix: "2026-09-29T21:00:00" or "2026-09-29 21:00:00".
    static func parseTimeTag(_ tag: String) -> Date? {
        let normalized = tag.replacingOccurrences(of: " ", with: "T")
        let withZone = normalized.hasSuffix("Z") ? normalized : normalized + "Z"
        return try? Date(withZone, strategy: .iso8601)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }
}

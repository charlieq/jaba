import Foundation

/// NOAA's OVATION 30-minute aurora model, reduced to what matters for one location.
public struct Nowcast: Codable, Hashable, Sendable {
    /// When the solar-wind data behind the model was observed.
    public let observationTime: Date
    /// The time the prediction is valid for (about 30–90 minutes after observation).
    public let forecastTime: Date
    /// Probability (%) of aurora directly overhead.
    public let overheadProbability: Int
    /// Highest probability (%) anywhere within viewing distance: what you might see on the horizon.
    public let inViewProbability: Int

    public init(observationTime: Date, forecastTime: Date, overheadProbability: Int, inViewProbability: Int) {
        self.observationTime = observationTime
        self.forecastTime = forecastTime
        self.overheadProbability = overheadProbability
        self.inViewProbability = inViewProbability
    }
}

/// The full OVATION grid: 1° cells, longitude 0…359 east, latitude −90…90.
public struct OvationGrid: Sendable {
    public let observationTime: Date
    public let forecastTime: Date
    private let values: [UInt8]

    /// How far away aurora (~110 km up) is still usefully visible above the horizon.
    public static let viewingRadiusKm = 600.0

    init(observationTime: Date, forecastTime: Date, values: [UInt8]) {
        self.observationTime = observationTime
        self.forecastTime = forecastTime
        self.values = values
    }

    /// Builds a grid from `(longitude, latitude, probability)` samples; used by tests and the parser.
    public init(observationTime: Date, forecastTime: Date, samples: [(lon: Int, lat: Int, value: Int)]) {
        var values = [UInt8](repeating: 0, count: 360 * 181)
        for s in samples {
            values[Self.index(lon: s.lon, lat: s.lat)] = UInt8(clamping: s.value)
        }
        self.init(observationTime: observationTime, forecastTime: forecastTime, values: values)
    }

    private static func index(lon: Int, lat: Int) -> Int {
        let l = ((lon % 360) + 360) % 360
        let a = min(90, max(-90, lat))
        return l * 181 + (a + 90)
    }

    public func probability(lon: Int, lat: Int) -> Int {
        Int(values[Self.index(lon: lon, lat: lat)])
    }

    public func nowcast(latitude: Double, longitude: Double) -> Nowcast {
        let overhead = probability(lon: Int(longitude.rounded()), lat: Int(latitude.rounded()))

        let latSpan = Int((Self.viewingRadiusKm / 111).rounded(.up))
        let lonSpan = min(180, Int((Double(latSpan) / max(0.1, cos(latitude.radians))).rounded(.up)))
        let centerLat = Int(latitude.rounded()), centerLon = Int(longitude.rounded())
        var inView = overhead
        for lat in (centerLat - latSpan)...(centerLat + latSpan) where (-90...90).contains(lat) {
            for lon in (centerLon - lonSpan)...(centerLon + lonSpan) {
                let km = Self.distanceKm(latitude, longitude, Double(lat), Double(lon))
                if km <= Self.viewingRadiusKm {
                    inView = max(inView, probability(lon: lon, lat: lat))
                }
            }
        }
        return Nowcast(
            observationTime: observationTime,
            forecastTime: forecastTime,
            overheadProbability: overhead,
            inViewProbability: inView
        )
    }

    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let dLat = (lat2 - lat1).radians, dLon = (lon2 - lon1).radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1.radians) * cos(lat2.radians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6_371 * asin(min(1, sqrt(a)))
    }

    /// Parses `ovation_aurora_latest.json`.
    public static func parse(_ data: Data) throws -> OvationGrid {
        let source = "NOAA aurora nowcast"
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let observed = (json["Observation Time"] as? String).flatMap({ try? Date($0, strategy: .iso8601) }),
              let forecast = (json["Forecast Time"] as? String).flatMap({ try? Date($0, strategy: .iso8601) }),
              let coordinates = json["coordinates"] as? [[NSNumber]]
        else { throw ForecastError.unexpectedFormat(source: source) }

        var values = [UInt8](repeating: 0, count: 360 * 181)
        for point in coordinates where point.count >= 3 {
            let i = index(lon: point[0].intValue, lat: point[1].intValue)
            values[i] = UInt8(clamping: point[2].intValue)
        }
        return OvationGrid(observationTime: observed, forecastTime: forecast, values: values)
    }
}

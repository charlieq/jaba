import Foundation

/// Hourly cloud cover and daily sunrise/sunset from Open-Meteo, in the location's time zone.
public struct WeatherForecast: Codable, Hashable, Sendable {
    public struct Hour: Codable, Hashable, Sendable {
        public let time: Date
        /// Total cloud cover, percent.
        public let cloudCover: Double?
        public let cloudCoverLow: Double?
        public let cloudCoverMid: Double?
        public let cloudCoverHigh: Double?
        /// Air temperature at 2 m, °C.
        public let temperature: Double?

        public init(
            time: Date, cloudCover: Double?,
            cloudCoverLow: Double? = nil, cloudCoverMid: Double? = nil, cloudCoverHigh: Double? = nil,
            temperature: Double? = nil
        ) {
            self.time = time
            self.cloudCover = cloudCover
            self.cloudCoverLow = cloudCoverLow
            self.cloudCoverMid = cloudCoverMid
            self.cloudCoverHigh = cloudCoverHigh
            self.temperature = temperature
        }
    }

    public struct Day: Codable, Hashable, Sendable {
        /// Local midnight starting this day.
        public let date: Date
        public let sunrise: Date?
        public let sunset: Date?

        public init(date: Date, sunrise: Date?, sunset: Date?) {
            self.date = date
            self.sunrise = sunrise
            self.sunset = sunset
        }
    }

    public let timeZoneIdentifier: String
    public let utcOffsetSeconds: Int
    public let hours: [Hour]
    public let days: [Day]

    public init(timeZoneIdentifier: String, utcOffsetSeconds: Int, hours: [Hour], days: [Day]) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.utcOffsetSeconds = utcOffsetSeconds
        self.hours = hours.sorted { $0.time < $1.time }
        self.days = days.sorted { $0.date < $1.date }
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt
    }

    public func hour(containing date: Date) -> Hour? {
        hours.last { $0.time <= date && date < $0.time.addingTimeInterval(3_600) }
    }

    /// Parses an Open-Meteo `/v1/forecast` response requested with `timeformat=unixtime`.
    public static func parseOpenMeteo(_ data: Data) throws -> WeatherForecast {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response: OpenMeteoResponse
        do {
            response = try decoder.decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw ForecastError.unexpectedFormat(source: "Open-Meteo")
        }

        let h = response.hourly
        func value(_ series: [Double?]?, _ i: Int) -> Double? {
            guard let series, i < series.count else { return nil }
            return series[i]
        }
        let hours = h.time.indices.map { i in
            Hour(
                time: Date(timeIntervalSince1970: h.time[i]),
                cloudCover: value(h.cloudCover, i),
                cloudCoverLow: value(h.cloudCoverLow, i),
                cloudCoverMid: value(h.cloudCoverMid, i),
                cloudCoverHigh: value(h.cloudCoverHigh, i),
                temperature: value(h.temperature2m, i)
            )
        }

        let d = response.daily
        let days = d.time.indices.map { i -> Day in
            var sunrise = i < d.sunrise.count ? d.sunrise[i].map(Date.init(timeIntervalSince1970:)) : nil
            var sunset = i < d.sunset.count ? d.sunset[i].map(Date.init(timeIntervalSince1970:)) : nil
            // Polar day/night: Open-Meteo reports equal or out-of-day times; treat as no event.
            if let r = sunrise, let s = sunset, r == s {
                sunrise = nil
                sunset = nil
            }
            return Day(date: Date(timeIntervalSince1970: d.time[i]), sunrise: sunrise, sunset: sunset)
        }

        return WeatherForecast(
            timeZoneIdentifier: response.timezone,
            utcOffsetSeconds: response.utcOffsetSeconds,
            hours: hours,
            days: days
        )
    }

    public static func openMeteoURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,temperature_2m"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "forecast_days", value: "4"),
        ]
        return components.url!
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Hourly: Decodable {
        let time: [TimeInterval]
        let cloudCover: [Double?]?
        let cloudCoverLow: [Double?]?
        let cloudCoverMid: [Double?]?
        let cloudCoverHigh: [Double?]?
        let temperature2m: [Double?]?
    }

    struct Daily: Decodable {
        let time: [TimeInterval]
        let sunrise: [TimeInterval?]
        let sunset: [TimeInterval?]
    }

    let timezone: String
    let utcOffsetSeconds: Int
    let hourly: Hourly
    let daily: Daily
}

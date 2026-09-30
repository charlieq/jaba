import Foundation
import Testing
@testable import JABAKit

enum Canmore {
    static let latitude = 51.0884
    static let longitude = -115.3479
    static let timeZone = TimeZone(identifier: "America/Edmonton")!
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func utc(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

/// A local wall-clock time in the given zone, e.g. local("2026-09-29 15:00").
func local(_ text: String, _ timeZone: TimeZone = Canmore.timeZone) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

/// Hourly weather for Canmore starting at local midnight on `startDay`, with real sunrise/sunset.
func syntheticWeather(
    startDay: String = "2026-09-28",
    days: Int = 5,
    includeSunTimes: Bool = true,
    cloud: (Date) -> Double?
) -> WeatherForecast {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Canmore.timeZone
    let start = local("\(startDay) 00:00")
    let hours = (0..<(days * 24)).map { i -> WeatherForecast.Hour in
        let time = start.addingTimeInterval(Double(i) * 3_600)
        return WeatherForecast.Hour(time: time, cloudCover: cloud(time), temperature: 2)
    }
    let dayList = (0..<days).map { d -> WeatherForecast.Day in
        let midnight = calendar.date(byAdding: .day, value: d, to: start)!
        let noon = midnight.addingTimeInterval(12 * 3_600)
        guard includeSunTimes else { return WeatherForecast.Day(date: midnight, sunrise: nil, sunset: nil) }
        let crossings = SolarPosition.crossings(
            latitude: Canmore.latitude, longitude: Canmore.longitude,
            threshold: SolarPosition.horizon, from: midnight, to: midnight.addingTimeInterval(86_400)
        )
        return WeatherForecast.Day(
            date: midnight,
            sunrise: crossings.first { $0.isRising && $0.date < noon }?.date,
            sunset: crossings.first { !$0.isRising && $0.date > noon }?.date
        )
    }
    return WeatherForecast(timeZoneIdentifier: Canmore.timeZone.identifier, utcOffsetSeconds: -21_600, hours: hours, days: dayList)
}

/// 3-hour Kp bins from 2026-09-28 00:00 UTC, `count` bins long.
func syntheticKp(count: Int = 40, kp: (Date) -> Double) -> KpForecast {
    let start = utc("2026-09-28T00:00:00Z")
    return KpForecast(bins: (0..<count).map { i in
        let binStart = start.addingTimeInterval(Double(i) * KpBin.duration)
        return KpBin(start: binStart, kp: kp(binStart), kind: .predicted)
    })
}

func canmoreOutlook(now: Date, kp: KpForecast, weather: WeatherForecast, nowcast: Nowcast? = nil) -> AuroraOutlook {
    AuroraOutlook(
        placeName: "Canmore", latitude: Canmore.latitude, longitude: Canmore.longitude,
        kp: kp, weather: weather, nowcast: nowcast, now: now
    )
}

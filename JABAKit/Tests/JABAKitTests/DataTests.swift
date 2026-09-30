import Foundation
import Testing
@testable import JABAKit

struct GeomagneticTests {
    @Test func magneticLatitudesOfExamplePlaces() {
        let canmore = GeomagneticInfo(latitude: 51.0884, longitude: -115.3479)
        #expect(abs(canmore.magneticLatitude - 57.35) < 0.2)
        #expect(abs(canmore.requiredKp - 4.46) < 0.1)

        let whitehorse = GeomagneticInfo(latitude: 60.7212, longitude: -135.0568)
        #expect(abs(whitehorse.magneticLatitude - 63.8) < 0.2)
        #expect(abs(whitehorse.requiredKp - 1.33) < 0.1)

        let haines = GeomagneticInfo(latitude: 59.236, longitude: -135.4453)
        #expect(abs(haines.requiredKp - 2.0) < 0.1)
    }

    @Test func requiredKpFollowsTheVisibilityTable() {
        #expect(Geomagnetic.requiredKp(magneticLatitude: 70) == 0)
        #expect(Geomagnetic.requiredKp(magneticLatitude: 66.5) == 0)
        #expect(abs(Geomagnetic.requiredKp(magneticLatitude: 58.3) - 4) < 1e-9)
        #expect(abs(Geomagnetic.requiredKp(magneticLatitude: 48.1) - 9) < 1e-9)
        #expect(Geomagnetic.requiredKp(magneticLatitude: 45) > 9)
        #expect(GeomagneticInfo(latitude: 20, longitude: -100).isOutOfReach)
    }
}

struct SolarTests {
    @Test func solsticeNoonInSeattle() {
        // Solar noon at 47.6°N on the June solstice: 90 − 47.6 + 23.44 ≈ 65.8°.
        let elevation = SolarPosition.elevation(latitude: 47.6062, longitude: -122.3321, at: utc("2026-06-21T20:11:00Z"))
        #expect(abs(elevation - 65.8) < 0.3)
    }

    @Test func computedSunsetMatchesOpenMeteo() throws {
        let weather = try WeatherForecast.parseOpenMeteo(fixture("open-meteo-canmore"))
        let day = weather.days[1]
        let sunset = try #require(day.sunset)
        let crossings = SolarPosition.crossings(
            latitude: Canmore.latitude, longitude: Canmore.longitude,
            threshold: SolarPosition.horizon,
            from: sunset.addingTimeInterval(-3_600), to: sunset.addingTimeInterval(3_600)
        )
        let computed = try #require(crossings.first { !$0.isRising })
        #expect(abs(computed.date.timeIntervalSince(sunset)) < 120)
    }

    @Test func darknessLevels() {
        #expect(Darkness(sunElevation: 1) == .daylight)
        #expect(Darkness(sunElevation: -3) == .civilTwilight)
        #expect(Darkness(sunElevation: -9) == .nauticalTwilight)
        #expect(Darkness(sunElevation: -15) == .astronomicalTwilight)
        #expect(Darkness(sunElevation: -25) == .night)
        #expect(Darkness(sunElevation: -12.5).isDark)
        #expect(!Darkness(sunElevation: -11).isDark)
    }
}

struct ParsingTests {
    @Test func parsesCurrentNOAAKpFormat() throws {
        let forecast = try KpForecast.parseNOAA(fixture("noaa-kp-forecast"))
        #expect(forecast.bins.count == 81)
        #expect(forecast.bins.contains { $0.kind == .predicted })
        #expect(zip(forecast.bins, forecast.bins.dropFirst()).allSatisfy { $0.start < $1.start })
        let first = try #require(forecast.bins.first)
        #expect(first.start == utc("2026-09-22T00:00:00Z"))
        #expect(forecast.bin(containing: first.start.addingTimeInterval(5_000)) == first)
        #expect(forecast.bin(containing: first.start.addingTimeInterval(-1)) == nil)
    }

    @Test func parsesLegacyNOAAKpTable() throws {
        let legacy = """
        [["time_tag","kp","observed","noaa_scale"],
         ["2026-09-29 21:00:00","5.33","predicted","G1"],
         ["2026-09-29 18:00:00","2.67","estimated",null]]
        """
        let forecast = try KpForecast.parseNOAA(Data(legacy.utf8))
        #expect(forecast.bins.map(\.kp) == [2.67, 5.33])
        #expect(forecast.bins.last?.noaaScale == "G1")
        #expect(forecast.bins.first?.kind == .estimated)
    }

    @Test func rejectsGarbage() {
        #expect(throws: ForecastError.self) { try KpForecast.parseNOAA(Data("{}".utf8)) }
        #expect(throws: ForecastError.self) { try WeatherForecast.parseOpenMeteo(Data("[]".utf8)) }
    }

    @Test func parsesOpenMeteo() throws {
        let weather = try WeatherForecast.parseOpenMeteo(fixture("open-meteo-canmore"))
        #expect(weather.timeZoneIdentifier == "America/Edmonton")
        #expect(weather.hours.count == 120)
        #expect(weather.days.count == 5)
        #expect(weather.days.allSatisfy { $0.sunrise != nil && $0.sunset != nil })
        #expect(weather.hours.allSatisfy { $0.cloudCover != nil })
        let hour = try #require(weather.hours.dropFirst(10).first)
        #expect(weather.hour(containing: hour.time.addingTimeInterval(1_800)) == hour)
    }

    @Test func parsesGeocodingResults() throws {
        let json = """
        {"results":[{"id":5847,"name":"Haines","latitude":59.23595,"longitude":-135.44533,
          "country_code":"US","country":"United States","admin1":"Alaska","timezone":"America/Juneau"}]}
        """
        let places = try Place.parseOpenMeteo(Data(json.utf8))
        #expect(places.first?.subtitle == "Alaska, United States")
        #expect(try Place.parseOpenMeteo(Data("{}".utf8)).isEmpty)
    }
}

struct NowcastTests {
    let observed = utc("2026-09-29T22:35:00Z")
    let forecast = utc("2026-09-30T00:09:00Z")

    @Test func overheadAndInViewProbabilities() {
        let grid = OvationGrid(observationTime: observed, forecastTime: forecast, samples: [
            (lon: 245, lat: 51, value: 5),   // over Canmore
            (lon: 245, lat: 55, value: 40),  // ~440 km north: on the horizon
            (lon: 245, lat: 62, value: 90),  // ~1200 km north: out of view
        ])
        let nowcast = grid.nowcast(latitude: Canmore.latitude, longitude: Canmore.longitude)
        #expect(nowcast.overheadProbability == 5)
        #expect(nowcast.inViewProbability == 40)
    }

    @Test func parsesOvationJSON() throws {
        let json = """
        {"Observation Time":"2026-09-29T22:35:00Z","Forecast Time":"2026-09-30T00:09:00Z",
         "Data Format":"[Longitude, Latitude, Aurora]","coordinates":[[245,51,7],[245,52,12]],"type":"MultiPoint"}
        """
        let grid = try OvationGrid.parse(Data(json.utf8))
        #expect(grid.forecastTime == forecast)
        #expect(grid.probability(lon: -115, lat: 52) == 12)
    }
}

struct CacheTests {
    @Test func roundTripsSnapshots() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "jaba-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ForecastCache(directory: dir)
        let kp = syntheticKp(count: 3) { _ in 3.33 }
        let fetched = utc("2026-09-29T12:00:00Z")
        try cache.store(Snapshot(fetchedAt: fetched, value: kp), key: ForecastCache.kpKey)
        let loaded = try #require(cache.load(KpForecast.self, key: ForecastCache.kpKey))
        #expect(loaded.value == kp)
        #expect(loaded.fetchedAt == fetched)
        #expect(cache.load(WeatherForecast.self, key: "missing") == nil)
    }

    @Test func locationStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "jaba-\(UUID().uuidString)/locations.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocationStore(fileURL: url)
        #expect(store.load() == nil)
        try store.save(SavedLocation.starters)
        #expect(store.load() == SavedLocation.starters)
    }
}

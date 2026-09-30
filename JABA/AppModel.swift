import Foundation
import JABAKit
import Observation
import SwiftUI // IndexSet-based remove/move helpers for List editing

/// App state: the saved locations, the latest (or cached) forecast data for each,
/// and alert preferences. Reports are rebuilt from the raw data on demand, so a
/// cached forecast is always scored against the current time.
@Observable
final class AppModel {
    static let shared = AppModel()

    struct LocationData {
        var weather: Snapshot<WeatherForecast>?
        var nowcast: Snapshot<Nowcast>?
        var error: String?
    }

    private(set) var locations: [SavedLocation]
    private(set) var data: [UUID: LocationData] = [:]
    private(set) var kp: Snapshot<KpForecast>?
    private(set) var isRefreshing = false
    private(set) var lastFailure: String?
    private(set) var alertsEnabled: Bool
    private(set) var alertOnMaybe: Bool
    private(set) var notificationsDenied = false

    @ObservationIgnored let client = AuroraDataClient()
    @ObservationIgnored private let cache = ForecastCache(directory: ForecastCache.defaultDirectory)
    @ObservationIgnored private let store = LocationStore(fileURL: URL.applicationSupportDirectory.appending(path: "locations.json"))
    @ObservationIgnored private let alerts = AlertScheduler()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var lastAttempt: Date?

    private enum Keys {
        static let alertsEnabled = "alertsEnabled"
        static let alertOnMaybe = "alertOnMaybe"
    }

    /// A nowcast older than this no longer describes "right now".
    static let nowcastMaxAge: TimeInterval = 45 * 60

    init() {
        if let saved = store.load() {
            locations = saved
        } else {
            // Save the starters right away so their IDs (the cache keys) survive relaunches.
            let starters = SavedLocation.starters
            locations = starters
            try? store.save(starters)
        }
        alertsEnabled = defaults.bool(forKey: Keys.alertsEnabled)
        alertOnMaybe = defaults.bool(forKey: Keys.alertOnMaybe)
        kp = cache.load(KpForecast.self, key: ForecastCache.kpKey)
        for location in locations {
            data[location.id] = LocationData(
                weather: cache.load(WeatherForecast.self, key: ForecastCache.weatherKey(location.id)),
                nowcast: cache.load(Nowcast.self, key: ForecastCache.nowcastKey(location.id))
            )
        }
    }

    // MARK: - Reports

    func outlook(for location: SavedLocation, now: Date = .now) -> AuroraOutlook? {
        guard let entry = data[location.id], let weather = entry.weather?.value else { return nil }
        let nowcast = entry.nowcast?.value
        let freshNowcast = nowcast.flatMap { $0.forecastTime > now.addingTimeInterval(-Self.nowcastMaxAge) ? $0 : nil }
        return AuroraOutlook(
            placeName: location.name,
            latitude: location.latitude,
            longitude: location.longitude,
            kp: kp?.value ?? KpForecast(bins: []),
            weather: weather,
            nowcast: freshNowcast,
            now: now
        )
    }

    func fetchedAt(_ location: SavedLocation) -> Date? {
        data[location.id]?.weather?.fetchedAt
    }

    /// Non-nil when the shown data isn't fresh: e.g. "Offline · forecast from 3 hours ago".
    func statusMessage(for location: SavedLocation? = nil, now: Date = .now) -> String? {
        let fetched: Date?
        if let location {
            fetched = fetchedAt(location)
        } else {
            fetched = locations.compactMap { fetchedAt($0) }.min()
        }
        let isOld = fetched.map { now.timeIntervalSince($0) > 90 * 60 } ?? false
        guard lastFailure != nil || isOld else { return nil }
        let prefix = lastFailure ?? "Not updated recently"
        guard let fetched else { return prefix }
        return "\(prefix) · forecast from \(fetched.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Refresh

    /// Refreshes every location. Skips if the last successful refresh was under five minutes ago, unless forced.
    func refresh(force: Bool = false) async {
        if !force, lastFailure == nil, let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < 5 * 60 { return }
        await update(locations, sharedFeeds: true)
    }

    func backgroundRefresh() async {
        await update(locations, sharedFeeds: true)
    }

    private func update(_ targets: [SavedLocation], sharedFeeds: Bool) async {
        guard !isRefreshing, !targets.isEmpty else { return }
        isRefreshing = true
        lastAttempt = .now

        let client = client
        async let kpResult: Result<KpForecast, Error>? = sharedFeeds ? attempt { try await client.kpForecast() } : nil
        async let ovationResult: Result<OvationGrid, Error>? = sharedFeeds ? attempt { try await client.ovation() } : nil
        let weatherResults = await withTaskGroup(of: (UUID, Result<WeatherForecast, Error>).self) { group in
            for location in targets {
                group.addTask {
                    (location.id, await attempt { try await client.weather(latitude: location.latitude, longitude: location.longitude) })
                }
            }
            var results: [UUID: Result<WeatherForecast, Error>] = [:]
            for await (id, result) in group { results[id] = result }
            return results
        }

        let now = Date.now
        var errors: [Error] = []

        switch await kpResult {
        case .success(let forecast)?:
            let snapshot = Snapshot(fetchedAt: now, value: forecast)
            kp = snapshot
            try? cache.store(snapshot, key: ForecastCache.kpKey)
        case .failure(let error)?:
            errors.append(error)
        case nil:
            break
        }

        let grid = try? await ovationResult?.get()
        for location in targets {
            var entry = data[location.id] ?? LocationData()
            switch weatherResults[location.id] {
            case .success(let forecast)?:
                let snapshot = Snapshot(fetchedAt: now, value: forecast)
                entry.weather = snapshot
                entry.error = nil
                try? cache.store(snapshot, key: ForecastCache.weatherKey(location.id))
            case .failure(let error)?:
                entry.error = error.localizedDescription
                errors.append(error)
            case nil:
                break
            }
            if let grid {
                let snapshot = Snapshot(fetchedAt: now, value: grid.nowcast(latitude: location.latitude, longitude: location.longitude))
                entry.nowcast = snapshot
                try? cache.store(snapshot, key: ForecastCache.nowcastKey(location.id))
            }
            data[location.id] = entry
        }

        lastFailure = errors.isEmpty ? nil : Self.describe(errors)
        // Cleared here rather than in a defer: the data is in, and alert rescheduling
        // (which may be slow) shouldn't hold the spinner or block the next refresh.
        isRefreshing = false
        await rescheduleAlerts()
    }

    private static func describe(_ errors: [Error]) -> String {
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut,
            .cannotFindHost, .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff,
        ]
        if errors.contains(where: { ($0 as? URLError).map { offlineCodes.contains($0.code) } ?? false }) {
            return "Offline"
        }
        return "Couldn't update"
    }

    // MARK: - Locations

    func add(_ place: Place) {
        let location = place.makeSavedLocation()
        let duplicate = locations.contains {
            abs($0.latitude - location.latitude) < 0.02 && abs($0.longitude - location.longitude) < 0.02
        }
        guard !duplicate else { return }
        locations.append(location)
        saveLocations()
        Task { await update([location], sharedFeeds: true) }
    }

    func remove(atOffsets offsets: IndexSet) {
        let removed = offsets.map { locations[$0] }
        locations.remove(atOffsets: offsets)
        saveLocations()
        for location in removed {
            data[location.id] = nil
            cache.remove(key: ForecastCache.weatherKey(location.id))
            cache.remove(key: ForecastCache.nowcastKey(location.id))
        }
        Task { await rescheduleAlerts() }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        locations.move(fromOffsets: source, toOffset: destination)
        saveLocations()
    }

    private func saveLocations() {
        try? store.save(locations)
    }

    // MARK: - Alerts

    func setAlertsEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await alerts.requestAuthorization()
            alertsEnabled = granted
            notificationsDenied = !granted
        } else {
            alertsEnabled = false
        }
        defaults.set(alertsEnabled, forKey: Keys.alertsEnabled)
        await rescheduleAlerts()
    }

    func setAlertOnMaybe(_ enabled: Bool) async {
        alertOnMaybe = enabled
        defaults.set(enabled, forKey: Keys.alertOnMaybe)
        await rescheduleAlerts()
    }

    private func rescheduleAlerts() async {
        guard alertsEnabled else {
            await alerts.removeAll()
            return
        }
        let items = locations.compactMap { location in
            outlook(for: location).map { (location, $0) }
        }
        await alerts.sync(items, includeMaybe: alertOnMaybe)
    }
}

/// Runs a throwing operation and captures its outcome, so one failed feed doesn't cancel the rest.
nonisolated func attempt<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

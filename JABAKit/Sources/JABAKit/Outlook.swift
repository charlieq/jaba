import Foundation

/// Why a night came out as NO.
public enum Blocker: Hashable, Sendable {
    case lowKp, clouds, lowKpAndClouds, noDarkness, noKpForecast, mismatch

    public var shortText: String {
        switch self {
        case .lowKp: "Kp too low"
        case .clouds: "Too cloudy"
        case .lowKpAndClouds: "Cloudy, Kp too low"
        case .noDarkness: "Never gets dark"
        case .noKpForecast: "No Kp forecast yet"
        case .mismatch: "Clear spells miss the activity"
        }
    }
}

/// One night (sunset to sunrise), scored hour by hour.
public struct NightReport: Hashable, Sendable, Identifiable {
    public var id: Date { window.start }

    /// Local noon to the next local noon: the calendar slot this night belongs to.
    public let window: DateInterval
    public let isTonight: Bool
    public let sunset: Date?
    public let sunrise: Date?
    /// When the sun drops below −12° (dark enough for aurora), and when it climbs back.
    public let darkStart: Date?
    public let darkEnd: Date?
    /// Every hour with the sun below the horizon. For tonight, only hours from now on.
    public let hours: [HourAssessment]
    public let verdict: Verdict
    public let score: Int
    /// Highest-scoring hour; nil when nothing rates above NO.
    public let best: HourAssessment?
    /// Contiguous run of hours around `best` that share its verdict.
    public let bestWindow: DateInterval?
    public let kpRange: ClosedRange<Double>?
    public let cloudRange: ClosedRange<Double>?
    /// Fraction of the night's hours that NOAA's Kp forecast covers.
    public let kpCoverage: Double
    public let stormScale: String?
    public let blocker: Blocker?
    public let reasoning: [String]
    /// Short summary for the location list, e.g. "23:00–02:00" or "Too cloudy".
    public let headline: String
}

public struct TimelineEntry: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case hour(HourAssessment)
        case sunset
        case sunrise
    }

    public let date: Date
    public let kind: Kind
    public let isNow: Bool

    public var id: String {
        switch kind {
        case .hour: "h\(date.timeIntervalSince1970)"
        case .sunset: "ss\(date.timeIntervalSince1970)"
        case .sunrise: "sr\(date.timeIntervalSince1970)"
        }
    }
}

/// Everything the app shows for one location, built from raw forecast data at a given moment.
/// Cheap to rebuild, so cached data is re-scored against the current time on every render.
public struct AuroraOutlook: Sendable {
    public let placeName: String
    public let latitude: Double
    public let longitude: Double
    public let geomagnetic: GeomagneticInfo
    public let timeZone: TimeZone
    public let now: Date
    /// The hour containing `now`, with darkness evaluated at `now`.
    public let current: HourAssessment?
    public let currentKpBin: KpBin?
    public let tonight: NightReport
    /// Tonight followed by later nights the Kp forecast reaches.
    public let nights: [NightReport]
    /// The next 24 hours, with sunset and sunrise interleaved.
    public let timeline: [TimelineEntry]
    public let nowcast: Nowcast?
    public let kpCoverageEnd: Date?

    public init(
        placeName: String,
        latitude: Double,
        longitude: Double,
        kp: KpForecast,
        weather: WeatherForecast,
        nowcast: Nowcast? = nil,
        now: Date = .now,
        rules: ScoringRules = .standard
    ) {
        let geomagnetic = GeomagneticInfo(latitude: latitude, longitude: longitude)
        let scorer = AuroraScorer(requiredKp: geomagnetic.requiredKp, rules: rules)
        let timeZone = weather.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let assessed = weather.hours.map { hour in
            let bin = kp.bin(containing: hour.time)
            let sunTime = hour.time == currentHourStart ? now : hour.time
            return scorer.assess(
                time: hour.time,
                kp: bin?.kp,
                kpKind: bin?.kind,
                cloudCover: hour.cloudCover,
                temperature: hour.temperature,
                sunElevation: SolarPosition.elevation(latitude: latitude, longitude: longitude, at: sunTime)
            )
        }

        let context = NightBuilder(
            placeName: placeName, latitude: latitude, longitude: longitude,
            geomagnetic: geomagnetic, rules: rules, timeZone: timeZone,
            kp: kp, weather: weather, assessed: assessed,
            currentHourStart: currentHourStart, now: now
        )
        let windows = context.windows(calendar: calendar).filter { $0.end > now }

        let tonightIndex = windows.firstIndex { !context.nightHours(in: $0, fromNow: true).isEmpty } ?? 0
        var nights: [NightReport] = []
        for (i, window) in windows.enumerated() where i >= tonightIndex {
            let night = context.makeNight(window: window, isTonight: i == tonightIndex)
            if i == tonightIndex || (night.kpCoverage > 0 && !night.hours.isEmpty) {
                nights.append(night)
            }
        }
        if nights.isEmpty {
            let fallback = DateInterval(start: now, duration: 86_400)
            nights = [context.makeNight(window: fallback, isTonight: true)]
        }

        let timelineEnd = currentHourStart.addingTimeInterval(24 * 3_600)
        var timeline = assessed
            .filter { $0.time >= currentHourStart && $0.time <= timelineEnd }
            .map { TimelineEntry(date: $0.time, kind: .hour($0), isNow: $0.time == currentHourStart) }
        for day in weather.days {
            if let sunset = day.sunset, sunset > now, sunset < timelineEnd {
                timeline.append(TimelineEntry(date: sunset, kind: .sunset, isNow: false))
            }
            if let sunrise = day.sunrise, sunrise > now, sunrise < timelineEnd {
                timeline.append(TimelineEntry(date: sunrise, kind: .sunrise, isNow: false))
            }
        }
        timeline.sort { $0.date < $1.date }

        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.geomagnetic = geomagnetic
        self.timeZone = timeZone
        self.now = now
        self.current = assessed.first { $0.time == currentHourStart }
        self.currentKpBin = kp.bin(containing: now)
        self.tonight = nights[0]
        self.nights = nights
        self.timeline = timeline
        self.nowcast = nowcast
        self.kpCoverageEnd = kp.coverageEnd
    }
}

/// Splits the forecast into nights and writes each night's reasoning.
private struct NightBuilder {
    let placeName: String
    let latitude: Double
    let longitude: Double
    let geomagnetic: GeomagneticInfo
    let rules: ScoringRules
    let timeZone: TimeZone
    let kp: KpForecast
    let weather: WeatherForecast
    let assessed: [HourAssessment]
    let currentHourStart: Date
    let now: Date

    /// Noon-to-noon slots covering the forecast. Using noon boundaries keeps each
    /// night in one piece, and handles polar day and night without special cases.
    func windows(calendar: Calendar) -> [DateInterval] {
        guard let first = weather.hours.first?.time, let last = weather.hours.last?.time,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: first),
              var start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayBefore)
        else { return [] }
        var result: [DateInterval] = []
        while start <= last {
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { break }
            result.append(DateInterval(start: start, end: end))
            start = end
        }
        return result
    }

    func nightHours(in window: DateInterval, fromNow: Bool) -> [HourAssessment] {
        assessed.filter { hour in
            window.start <= hour.time && hour.time < window.end
                && hour.sunElevation < SolarPosition.horizon
                && (!fromNow || hour.time >= currentHourStart)
        }
    }

    func makeNight(window: DateInterval, isTonight: Bool) -> NightReport {
        let hours = nightHours(in: window, fromNow: isTonight)

        let horizonCrossings = SolarPosition.crossings(
            latitude: latitude, longitude: longitude,
            threshold: SolarPosition.horizon, from: window.start, to: window.end
        )
        let sunset = weather.days.compactMap(\.sunset).first { window.contains($0) }
            ?? horizonCrossings.first { !$0.isRising }?.date
        let sunrise = weather.days.compactMap(\.sunrise).first { window.contains($0) }
            ?? horizonCrossings.last { $0.isRising }?.date

        let darkCrossings = SolarPosition.crossings(
            latitude: latitude, longitude: longitude,
            threshold: SolarPosition.darkElevation, from: window.start, to: window.end
        )
        let darkStart = darkCrossings.first { !$0.isRising }?.date
        let darkEnd = darkCrossings.last { $0.isRising }?.date

        let verdict = hours.map(\.verdict).max() ?? .no
        let best = verdict == .no ? nil : hours.reduce(nil) { (best: HourAssessment?, hour) in
            guard let best else { return hour }
            return hour.score > best.score ? hour : best
        }
        let bestWindow = best.map { bestRun(around: $0, in: hours, darkEnd: darkEnd) }

        let darkish = hours.filter { $0.darkness >= .nauticalTwilight }
        // Summaries describe the hours you could actually watch: dark ones, else twilight, else all.
        let dark = hours.filter { $0.darkness.isDark }
        let viewing = !dark.isEmpty ? dark : !darkish.isEmpty ? darkish : hours
        let kpValues = viewing.compactMap(\.kp)
        let kpRange = kpValues.min().map { $0...(kpValues.max() ?? $0) }
        let cloudValues = viewing.compactMap(\.cloudCover)
        let cloudRange = cloudValues.min().map { $0...(cloudValues.max() ?? $0) }
        let kpCoverage = hours.isEmpty ? 0 : Double(hours.filter { $0.kp != nil }.count) / Double(hours.count)
        let stormScale = kp.bins
            .filter { $0.end > (hours.first?.time ?? window.start) && $0.start < (hours.last?.time ?? window.end) }
            .compactMap(\.noaaScale)
            .max()

        let blocker = verdict == .no ? Self.blocker(hours: hours) : nil

        let headline: String
        switch verdict {
        case .go:
            headline = bestWindow.map { AuroraFormat.timeRange($0.start, $0.end, in: timeZone) } ?? ""
        case .maybe:
            headline = best.map { "Photo check ~\(AuroraFormat.time($0.time, in: timeZone))" } ?? ""
        case .no:
            headline = blocker?.shortText ?? ""
        }

        return NightReport(
            window: window,
            isTonight: isTonight,
            sunset: sunset,
            sunrise: sunrise,
            darkStart: darkStart,
            darkEnd: darkEnd,
            hours: hours,
            verdict: verdict,
            score: hours.map(\.score).max() ?? 0,
            best: best,
            bestWindow: bestWindow,
            kpRange: kpRange,
            cloudRange: cloudRange,
            kpCoverage: kpCoverage,
            stormScale: stormScale,
            blocker: blocker,
            reasoning: reasoning(
                hours: hours, darkish: darkish, viewing: viewing, viewingIsDark: !dark.isEmpty,
                verdict: verdict, best: best, bestWindow: bestWindow,
                kpRange: kpRange, cloudRange: cloudRange, kpCoverage: kpCoverage, stormScale: stormScale,
                darkStart: darkStart, darkEnd: darkEnd, blocker: blocker
            ),
            headline: headline
        )
    }

    private func bestRun(around best: HourAssessment, in hours: [HourAssessment], darkEnd: Date?) -> DateInterval {
        guard let index = hours.firstIndex(of: best) else {
            return DateInterval(start: best.time, duration: 3_600)
        }
        func continues(_ a: Int, _ b: Int) -> Bool {
            hours[b].verdict == best.verdict && abs(hours[b].time.timeIntervalSince(hours[a].time)) <= 3_600
        }
        var lo = index, hi = index
        while lo > 0, continues(lo, lo - 1) { lo -= 1 }
        while hi < hours.count - 1, continues(hi, hi + 1) { hi += 1 }
        var end = hours[hi].time.addingTimeInterval(3_600)
        // A window that relies on darkness ends when the sky starts to brighten.
        if best.darkness.isDark, let darkEnd, darkEnd > hours[hi].time, darkEnd < end {
            end = darkEnd
        }
        return DateInterval(start: hours[lo].time, end: end)
    }

    private static func blocker(hours: [HourAssessment]) -> Blocker {
        let darkish = hours.filter { $0.darkness >= .nauticalTwilight }
        if darkish.isEmpty { return .noDarkness }
        if darkish.allSatisfy({ $0.kpLevel == .unknown }) { return .noKpForecast }
        let kpOK = darkish.contains { $0.kpLevel >= .moderate }
        let skyOK = darkish.contains { $0.sky != .overcast }
        switch (kpOK, skyOK) {
        case (false, false): return .lowKpAndClouds
        case (false, true): return .lowKp
        case (true, false): return .clouds
        case (true, true): return .mismatch
        }
    }

    private func reasoning(
        hours: [HourAssessment], darkish: [HourAssessment],
        viewing: [HourAssessment], viewingIsDark: Bool, verdict: Verdict,
        best: HourAssessment?, bestWindow: DateInterval?,
        kpRange: ClosedRange<Double>?, cloudRange: ClosedRange<Double>?,
        kpCoverage: Double, stormScale: String?,
        darkStart: Date?, darkEnd: Date?, blocker: Blocker?
    ) -> [String] {
        func time(_ date: Date) -> String { AuroraFormat.time(date, in: timeZone) }
        let need = AuroraFormat.kp(geomagnetic.requiredKp)
        let camera = max(0, geomagnetic.requiredKp + rules.cameraKpMargin)
        var lines: [String] = []

        let magLat = AuroraFormat.degrees(geomagnetic.magneticLatitude)
        if geomagnetic.isOutOfReach {
            lines.append("\(placeName) is at magnetic latitude \(magLat): too far from the auroral oval for even an extreme Kp 9 storm to reach the horizon.")
        } else if camera == 0 {
            lines.append("\(placeName) is at magnetic latitude \(magLat), close to the auroral oval: aurora reaches the horizon at about Kp \(need), so even quiet nights can show it.")
        } else {
            lines.append("\(placeName) is at magnetic latitude \(magLat), so aurora reaches the northern horizon at about Kp \(need). A camera can pick it up from about Kp \(AuroraFormat.kp(camera)).")
        }

        if let kpRange {
            let peak = viewing.first { $0.kp == kpRange.upperBound }
            let span = viewingIsDark ? "while it's dark" : "overnight"
            if kpRange.lowerBound == kpRange.upperBound {
                lines.append("NOAA forecasts Kp \(AuroraFormat.kp(kpRange.upperBound)) \(viewingIsDark ? "throughout the dark hours" : "through the night").")
            } else {
                let when = peak.map { ", peaking around \(time($0.time))" } ?? ""
                lines.append("NOAA forecasts Kp \(AuroraFormat.kp(kpRange.lowerBound))–\(AuroraFormat.kp(kpRange.upperBound)) \(span)\(when).")
            }
            if let stormScale {
                lines.append("NOAA expects a \(stormScale) geomagnetic storm.")
            }
            if kpCoverage < 1, let end = kp.coverageEnd {
                lines.append("The Kp forecast only runs until \(time(end)), so part of this night isn't covered yet.")
            }
        } else if !hours.isEmpty {
            lines.append("NOAA's 3-day Kp forecast doesn't reach this night yet.")
        }

        if let cloudRange {
            let clearest = viewing.first { $0.cloudCover == cloudRange.lowerBound }
            let span = viewingIsDark ? "while it's dark" : "overnight"
            if cloudRange.lowerBound == cloudRange.upperBound {
                lines.append("Cloud cover stays near \(AuroraFormat.percent(cloudRange.lowerBound)) \(span).")
            } else {
                let when = clearest.map { ", clearest around \(time($0.time))" } ?? ""
                lines.append("Cloud cover ranges \(AuroraFormat.percent(cloudRange.lowerBound))–\(AuroraFormat.percent(cloudRange.upperBound)) \(span)\(when).")
            }
        }

        if let darkStart, let darkEnd {
            if darkStart < now, darkEnd > now {
                lines.append("It's dark enough for aurora now, until \(time(darkEnd)) (sun below −12°).")
            } else {
                lines.append("Dark enough for aurora (sun below −12°) from \(time(darkStart)) to \(time(darkEnd)).")
            }
        } else if let darkEnd, darkEnd > now {
            lines.append("It's dark enough for aurora until \(time(darkEnd)) (sun below −12°).")
        } else if hours.isEmpty {
            lines.append("The sun doesn't set far enough for a dark sky.")
        } else if darkish.isEmpty || !hours.contains(where: { $0.darkness.isDark }) {
            lines.append("It never gets fully dark, only twilight, between sunset and sunrise.")
        }

        switch verdict {
        case .go:
            if let best, let bestWindow {
                let kpText = best.kp.map { "Kp \(AuroraFormat.kp($0))" } ?? "strong activity"
                let cloudText = best.cloudCover.map { "\(AuroraFormat.percent($0)) cloud" } ?? "clear skies"
                let position = (best.kp ?? 0) - geomagnetic.requiredKp >= 3
                    ? "It could reach overhead."
                    : "Look north; expect it low to mid-sky."
                lines.append("Best window \(AuroraFormat.timeRange(bestWindow.start, bestWindow.end, in: timeZone)), peaking at \(time(best.time)) with \(kpText) and \(cloudText). Get out of the tent! \(position)")
            }
        case .maybe:
            if let best {
                var caveats: [String] = []
                if best.kpLevel == .moderate { caveats.append("activity is marginal here") }
                if best.sky == .partlyCloudy { caveats.append("clouds may get in the way") }
                if best.sky == .unknown { caveats.append("there's no cloud forecast") }
                if best.darkness == .nauticalTwilight { caveats.append("the sky is still in twilight") }
                let kpText = best.kp.map { "Kp \(AuroraFormat.kp($0))" } ?? "Kp unknown"
                let cloudText = best.cloudCover.map { "\(AuroraFormat.percent($0)) cloud" } ?? "cloud unknown"
                let caveat = caveats.isEmpty ? "" : ", but \(caveats.joined(separator: " and "))"
                lines.append("Best chance around \(time(best.time)) (\(kpText), \(cloudText))\(caveat). Step out and take a few-second exposure facing north: a camera often sees aurora the eye can't.")
            }
        case .no:
            let peak = kpRange.map { AuroraFormat.kp($0.upperBound) } ?? "?"
            switch blocker {
            case .lowKp:
                lines.append("Main blocker: geomagnetic activity. Peak Kp \(peak) is below the Kp \(AuroraFormat.kp(camera)) even a camera needs here.")
            case .clouds:
                lines.append("Main blocker: clouds. Kp would be enough, but every dark hour is more than \(AuroraFormat.percent(rules.maxCloudCover)) cloudy.")
            case .lowKpAndClouds:
                lines.append("Both are against you: Kp tops out at \(peak) (about \(need) needed) and skies stay more than \(AuroraFormat.percent(rules.maxCloudCover)) cloudy.")
            case .noDarkness:
                lines.append("Without a dark sky there's nothing to see.")
            case .noKpForecast:
                lines.append("Check back once NOAA's forecast covers this night.")
            case .mismatch:
                lines.append("The clear spells and the stronger activity don't line up, so no hour passes.")
            case nil:
                break
            }
        }
        return lines
    }
}

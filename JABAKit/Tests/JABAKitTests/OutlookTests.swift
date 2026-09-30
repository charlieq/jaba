import Foundation
import Testing
@testable import JABAKit

struct OutlookTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = Canmore.timeZone
        return c
    }

    @Test func strongStormAfterMidnightOnAClearNightIsGo() throws {
        // Kp 6.33 from 06–09 UTC on Sep 30 = 00:00–03:00 MDT; quiet otherwise.
        let stormBin = utc("2026-09-30T06:00:00Z")
        let kp = syntheticKp { $0 == stormBin ? 6.33 : 2.0 }
        let outlook = canmoreOutlook(now: local("2026-09-29 15:00"), kp: kp, weather: syntheticWeather { _ in 0 })

        let tonight = outlook.tonight
        #expect(tonight.isTonight)
        #expect(tonight.verdict == .go)
        #expect(tonight.score >= 70)
        let best = try #require(tonight.best)
        #expect(calendar.component(.hour, from: best.time) < 3)
        let window = try #require(tonight.bestWindow)
        #expect(window.start == local("2026-09-30 00:00"))
        #expect(window.end == local("2026-09-30 03:00"))
        #expect(tonight.reasoning.last?.contains("Get out of the tent") == true)
        #expect(tonight.blocker == nil)
    }

    @Test func overcastNightIsBlockedByClouds() {
        let outlook = canmoreOutlook(now: local("2026-09-29 15:00"), kp: syntheticKp { _ in 7 }, weather: syntheticWeather { _ in 80 })
        #expect(outlook.tonight.verdict == .no)
        #expect(outlook.tonight.score == 0)
        #expect(outlook.tonight.blocker == .clouds)
        #expect(outlook.tonight.headline == "Too cloudy")
        #expect(outlook.tonight.best == nil)
    }

    @Test func quietNightIsBlockedByLowKp() {
        let outlook = canmoreOutlook(now: local("2026-09-29 15:00"), kp: syntheticKp { _ in 1 }, weather: syntheticWeather { _ in 0 })
        #expect(outlook.tonight.verdict == .no)
        #expect(outlook.tonight.blocker == .lowKp)
    }

    @Test func cloudyAndQuietReportsBoth() {
        let outlook = canmoreOutlook(now: local("2026-09-29 15:00"), kp: syntheticKp { _ in 1 }, weather: syntheticWeather { _ in 90 })
        #expect(outlook.tonight.blocker == .lowKpAndClouds)
    }

    @Test func marginalKpSuggestsAPhotoCheck() {
        let outlook = canmoreOutlook(now: local("2026-09-29 15:00"), kp: syntheticKp { _ in 4.0 }, weather: syntheticWeather { _ in 0 })
        #expect(outlook.tonight.verdict == .maybe)
        #expect((30...69).contains(outlook.tonight.score))
        #expect(outlook.tonight.headline.hasPrefix("Photo check"))
        #expect(outlook.tonight.reasoning.last?.contains("camera") == true)
    }

    @Test func beforeDawnTonightIsTheRestOfTheCurrentNight() throws {
        let now = local("2026-09-30 02:30")
        let outlook = canmoreOutlook(now: now, kp: syntheticKp { _ in 6.33 }, weather: syntheticWeather { _ in 0 })
        let tonight = outlook.tonight
        #expect(tonight.window.contains(now))
        #expect(tonight.hours.first?.time == local("2026-09-30 02:00"))
        let sunrise = try #require(tonight.sunrise)
        #expect(sunrise > now)
        #expect(tonight.verdict == .go)
    }

    @Test func midMorningLooksAheadToThisEvening() throws {
        let now = local("2026-09-30 10:00")
        let outlook = canmoreOutlook(now: now, kp: syntheticKp { _ in 6.33 }, weather: syntheticWeather { _ in 0 })
        let sunset = try #require(outlook.tonight.sunset)
        #expect(sunset > now)
        #expect(calendar.isDate(sunset, inSameDayAs: now))
    }

    @Test func sunTimesFallBackToSolarMathWhenMissing() throws {
        let outlook = canmoreOutlook(
            now: local("2026-09-29 15:00"), kp: syntheticKp { _ in 3 },
            weather: syntheticWeather(includeSunTimes: false) { _ in 0 }
        )
        let sunset = try #require(outlook.tonight.sunset)
        #expect(calendar.component(.hour, from: sunset) == 19)
        #expect(outlook.tonight.darkStart != nil)
        #expect(outlook.tonight.darkEnd != nil)
    }

    @Test func timelineCoversTheNextDayWithSunEvents() {
        let outlook = canmoreOutlook(now: local("2026-09-29 15:20"), kp: syntheticKp { _ in 3 }, weather: syntheticWeather { _ in 0 })
        let timeline = outlook.timeline
        #expect(timeline.first?.isNow == true)
        #expect(timeline.first?.date == local("2026-09-29 15:00"))
        #expect(timeline.filter { if case .hour = $0.kind { true } else { false } }.count == 25)
        #expect(timeline.contains { $0.kind == .sunset })
        #expect(timeline.contains { $0.kind == .sunrise })
        #expect(zip(timeline, timeline.dropFirst()).allSatisfy { $0.date <= $1.date })
    }

    @Test func laterNightsOnlyWhileKpForecastLasts() {
        // 26 bins = 78 h from Sep 28 00Z: all of tonight (Sep 29), and Sep 30 until local midnight.
        let outlook = canmoreOutlook(now: local("2026-09-29 15:00"), kp: syntheticKp(count: 26) { _ in 3 }, weather: syntheticWeather { _ in 0 })
        #expect(outlook.nights.count == 2)
        #expect(outlook.nights[0].isTonight)
        #expect(!outlook.nights[1].isTonight)
        #expect(outlook.nights[1].kpCoverage < 1)
        #expect(outlook.nights[1].reasoning.contains { $0.contains("isn't covered") })
    }

    @Test func realFeedsProduceAReport() throws {
        let kp = try KpForecast.parseNOAA(fixture("noaa-kp-forecast"))
        let weather = try WeatherForecast.parseOpenMeteo(fixture("open-meteo-canmore"))
        let outlook = canmoreOutlook(now: utc("2026-09-29T21:47:00Z"), kp: kp, weather: weather)
        #expect(!outlook.tonight.hours.isEmpty)
        #expect(outlook.tonight.reasoning.count >= 4)
        #expect(outlook.current != nil)
        print("— Canmore, fixture data —")
        print("Verdict \(outlook.tonight.verdict.label) \(outlook.tonight.score): \(outlook.tonight.headline)")
        outlook.tonight.reasoning.forEach { print("•", $0) }
        for night in outlook.nights {
            print(night.window.start, night.verdict.label, night.score, night.headline)
        }
    }
}

struct OutlookWordingTests {
    @Test func summariesOnlyCoverDarkHours() throws {
        // Clear only in the morning twilight; Kp peaks after the sky brightens.
        let weather = syntheticWeather { date in
            let hour = Calendar.current.dateComponents(in: Canmore.timeZone, from: date).hour ?? 0
            return hour == 7 ? 5 : 40
        }
        // A Kp 6 block from 07:00 MDT (13Z), when the sky is already brightening.
        let spike = KpBin(start: utc("2026-09-30T13:00:00Z"), kp: 6, kind: .predicted)
        let kp = KpForecast(bins: syntheticKp { _ in 4 }.bins + [spike])
        let outlook = canmoreOutlook(now: local("2026-09-29 15:00"), kp: kp, weather: weather)
        let night = outlook.tonight
        let darkEnd = try #require(night.darkEnd)
        // The spike only touches twilight hours, so it's left out of the range.
        #expect(night.kpRange?.upperBound == 4)
        #expect(night.cloudRange?.lowerBound == 40)
        #expect(night.reasoning.contains { $0.contains("while it's dark") })
        if let window = night.bestWindow, night.best?.darkness.isDark == true {
            #expect(window.end <= darkEnd.addingTimeInterval(1))
        }
    }

    @Test func kpWordingMatchesDisplayedNumbers() {
        // 1.33 vs 1.335 both display as 1.3: say "meets", not "just under".
        let hour = AuroraScorer(requiredKp: 1.335).assess(time: .now, kp: 1.33, cloudCover: 0, sunElevation: -20)
        #expect(hour.factors[0].summary.contains("meets"))
        #expect(hour.factors[2].summary.contains("−20°"))
    }
}

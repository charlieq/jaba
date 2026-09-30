import Foundation

/// How dark the sky is, from the sun's elevation below the horizon.
public enum Darkness: Int, Comparable, Sendable, CaseIterable {
    case daylight, civilTwilight, nauticalTwilight, astronomicalTwilight, night

    public init(sunElevation: Double) {
        if sunElevation > SolarPosition.horizon {
            self = .daylight
        } else if sunElevation > -6 {
            self = .civilTwilight
        } else if sunElevation > -12 {
            self = .nauticalTwilight
        } else if sunElevation > -18 {
            self = .astronomicalTwilight
        } else {
            self = .night
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Sun at or below −12°: dark enough for aurora.
    public var isDark: Bool { self >= .astronomicalTwilight }

    public var label: String {
        switch self {
        case .daylight: "Daylight"
        case .civilTwilight: "Civil twilight"
        case .nauticalTwilight: "Nautical twilight"
        case .astronomicalTwilight: "Astronomical twilight"
        case .night: "Dark"
        }
    }
}

public enum SolarPosition {
    /// Apparent sunrise/sunset elevation (refraction + solar radius).
    public static let horizon = -0.833
    /// Sun below this is dark enough for aurora (end of nautical twilight).
    public static let darkElevation = -12.0

    /// Solar elevation in degrees (NOAA solar calculator equations; good to ~0.01°, no refraction).
    public static func elevation(latitude: Double, longitude: Double, at date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525

        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032))
            .truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = meanAnomaly.radians
        let center = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
        let omega = (125.04 - 1_934.136 * t).radians
        let apparentLongitude = (meanLongitude + center - 0.00569 - 0.00478 * sin(omega)).radians
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = (meanObliquity + 0.00256 * cos(omega)).radians
        let declination = asin(sin(obliquity) * sin(apparentLongitude))

        let y = pow(tan(obliquity / 2), 2)
        let l0 = meanLongitude.radians
        let equationOfTime = 4 * (y * sin(2 * l0)
            - 2 * eccentricity * sin(m)
            + 4 * eccentricity * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * eccentricity * eccentricity * sin(2 * m)).degrees

        var minutesUTC = (julianDay + 0.5).truncatingRemainder(dividingBy: 1) * 1_440
        if minutesUTC < 0 { minutesUTC += 1_440 }
        var trueSolarTime = (minutesUTC + equationOfTime + 4 * longitude).truncatingRemainder(dividingBy: 1_440)
        if trueSolarTime < 0 { trueSolarTime += 1_440 }
        let hourAngle = (trueSolarTime / 4 < 0 ? trueSolarTime / 4 + 180 : trueSolarTime / 4 - 180).radians

        let lat = latitude.radians
        let cosZenith = sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)
        return 90 - acos(min(1, max(-1, cosZenith))).degrees
    }

    public struct Crossing: Hashable, Sendable {
        public let date: Date
        /// True when the sun is climbing through the threshold (dawn side).
        public let isRising: Bool
    }

    /// Times between `start` and `end` when the sun crosses `threshold` degrees.
    public static func crossings(
        latitude: Double, longitude: Double,
        threshold: Double, from start: Date, to end: Date,
        step: TimeInterval = 600
    ) -> [Crossing] {
        func above(_ date: Date) -> Bool {
            elevation(latitude: latitude, longitude: longitude, at: date) > threshold
        }
        var result: [Crossing] = []
        var t0 = start
        var wasAbove = above(t0)
        while t0 < end {
            let t1 = min(t0.addingTimeInterval(step), end)
            let isAbove = above(t1)
            if isAbove != wasAbove {
                var lo = t0, hi = t1
                while hi.timeIntervalSince(lo) > 20 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    if above(mid) == wasAbove { lo = mid } else { hi = mid }
                }
                result.append(Crossing(date: hi, isRising: isAbove))
            }
            wasAbove = isAbove
            t0 = t1
        }
        return result
    }
}

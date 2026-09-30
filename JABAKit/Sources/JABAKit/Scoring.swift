import Foundation

/// The "should I get out of the tent?" answer.
public enum Verdict: Int, Comparable, Sendable, CaseIterable {
    case no, maybe, go

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .no: "NO"
        case .maybe: "MAYBE"
        case .go: "GO"
        }
    }

    public var advice: String {
        switch self {
        case .no: "Stay in the tent"
        case .maybe: "Take a photo of the northern sky"
        case .go: "Get out of the tent"
        }
    }

    /// Scores are banded so the number and the verdict always agree.
    public var scoreRange: ClosedRange<Int> {
        switch self {
        case .no: 0...0
        case .maybe: 30...69
        case .go: 70...100
        }
    }
}

/// Geomagnetic activity relative to what this location needs.
public enum KpLevel: Int, Comparable, Sendable {
    /// No Kp forecast covers this hour.
    case unknown
    /// Too weak for anything, even a camera, to pick up.
    case tooLow
    /// Around the local threshold: faint, low on the horizon, often camera-only.
    case moderate
    /// Comfortably above the local threshold: visible to the eye.
    case high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum SkyLevel: Int, Comparable, Sendable {
    case unknown, overcast, partlyCloudy, clear

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Thresholds behind the verdict. "High" and "moderate" Kp are measured against
/// the Kp this location needs (from its magnetic latitude), not fixed Kp values.
public struct ScoringRules: Hashable, Sendable {
    /// Kp this far below the naked-eye threshold can still show up on a long camera exposure.
    public var cameraKpMargin = -1.0
    /// Kp this far above the threshold counts as "high".
    public var highKpMargin = 1.0
    /// Above this cloud cover (%) the sky is blocked: NO.
    public var maxCloudCover = 50.0
    /// Below this cloud cover (%) the sky is clear enough for GO.
    public var clearCloudCover = 10.0

    public init() {}

    public static let standard = ScoringRules()

    public func kpLevel(kp: Double?, requiredKp: Double) -> KpLevel {
        guard let kp else { return .unknown }
        let margin = kp - requiredKp
        if margin < cameraKpMargin { return .tooLow }
        if margin < highKpMargin { return .moderate }
        return .high
    }

    public func skyLevel(cloudCover: Double?) -> SkyLevel {
        guard let cloudCover else { return .unknown }
        if cloudCover > maxCloudCover { return .overcast }
        if cloudCover < clearCloudCover { return .clear }
        return .partlyCloudy
    }
}

/// One of the three inputs to an hour's verdict, with a plain-language explanation.
public struct Factor: Hashable, Sendable {
    public enum Kind: Sendable { case kp, clouds, darkness }
    public enum Status: Int, Comparable, Sendable {
        case bad, fair, good
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let kind: Kind
    public let status: Status
    public let summary: String
}

/// The verdict and score for a single hour.
public struct HourAssessment: Hashable, Sendable, Identifiable {
    public var id: Date { time }

    public let time: Date
    public let kp: Double?
    public let kpKind: KpBin.Kind?
    public let cloudCover: Double?
    public let temperature: Double?
    public let sunElevation: Double
    public let darkness: Darkness
    public let kpLevel: KpLevel
    public let sky: SkyLevel
    public let verdict: Verdict
    public let score: Int
    public let factors: [Factor]
}

public struct AuroraScorer: Sendable {
    public let requiredKp: Double
    public let rules: ScoringRules

    public init(requiredKp: Double, rules: ScoringRules = .standard) {
        self.requiredKp = requiredKp
        self.rules = rules
    }

    public func assess(
        time: Date,
        kp: Double?,
        kpKind: KpBin.Kind? = nil,
        cloudCover: Double?,
        temperature: Double? = nil,
        sunElevation: Double
    ) -> HourAssessment {
        let darkness = Darkness(sunElevation: sunElevation)
        let kpLevel = rules.kpLevel(kp: kp, requiredKp: requiredKp)
        let sky = rules.skyLevel(cloudCover: cloudCover)

        let verdict: Verdict
        if kpLevel <= .tooLow
            || sky == .overcast
            || darkness <= .civilTwilight
            || (darkness == .nauticalTwilight && kpLevel != .high) {
            verdict = .no
        } else if kpLevel == .high, sky == .clear, darkness.isDark {
            verdict = .go
        } else {
            verdict = .maybe
        }

        return HourAssessment(
            time: time,
            kp: kp,
            kpKind: kpKind,
            cloudCover: cloudCover,
            temperature: temperature,
            sunElevation: sunElevation,
            darkness: darkness,
            kpLevel: kpLevel,
            sky: sky,
            verdict: verdict,
            score: score(verdict: verdict, kp: kp, cloudCover: cloudCover, darkness: darkness),
            factors: [
                kpFactor(kp: kp, level: kpLevel),
                cloudFactor(cloudCover: cloudCover, sky: sky),
                darknessFactor(darkness: darkness, sunElevation: sunElevation, kpLevel: kpLevel),
            ]
        )
    }

    /// Places the hour within its verdict's band: Kp margin counts most, then clouds, then darkness.
    func score(verdict: Verdict, kp: Double?, cloudCover: Double?, darkness: Darkness) -> Int {
        let margin = (kp ?? 0) - requiredKp
        switch verdict {
        case .no:
            return 0
        case .maybe:
            let kpPart = clamp01((margin - rules.cameraKpMargin) / (rules.highKpMargin + 1 - rules.cameraKpMargin))
            let cloudPart = cloudCover.map { clamp01((rules.maxCloudCover - $0) / rules.maxCloudCover) } ?? 0.5
            let darkPart = darkness == .night ? 1 : darkness == .astronomicalTwilight ? 0.8 : 0.3
            let quality = 0.5 * kpPart + 0.35 * cloudPart + 0.15 * darkPart
            return 30 + Int((39 * quality).rounded())
        case .go:
            let kpPart = clamp01((margin - rules.highKpMargin) / 2)
            let cloudPart = cloudCover.map { clamp01((rules.clearCloudCover - $0) / rules.clearCloudCover) } ?? 0
            let darkPart = darkness == .night ? 1 : 0.6
            let quality = 0.5 * kpPart + 0.35 * cloudPart + 0.15 * darkPart
            return 70 + Int((30 * quality).rounded())
        }
    }

    private func kpFactor(kp: Double?, level: KpLevel) -> Factor {
        let need = AuroraFormat.kp(requiredKp)
        guard let kp else {
            return Factor(kind: .kp, status: .bad, summary: "No Kp forecast reaches this hour yet")
        }
        let value = AuroraFormat.kp(kp)
        switch level {
        case .unknown, .tooLow:
            return Factor(kind: .kp, status: .bad, summary: "Kp \(value) is too weak here (about Kp \(need) needed)")
        // Compare as displayed (one decimal) so the text never reads "1.3 is under 1.3".
        case .moderate where (kp * 10).rounded() < (requiredKp * 10).rounded():
            return Factor(kind: .kp, status: .fair, summary: "Kp \(value) is just under the Kp \(need) needed; a camera may still catch it")
        case .moderate:
            return Factor(kind: .kp, status: .fair, summary: "Kp \(value) meets the Kp \(need) needed; expect it low on the northern horizon")
        case .high:
            return Factor(kind: .kp, status: .good, summary: "Kp \(value) is well above the Kp \(need) needed here")
        }
    }

    private func cloudFactor(cloudCover: Double?, sky: SkyLevel) -> Factor {
        guard let cloudCover else {
            return Factor(kind: .clouds, status: .fair, summary: "No cloud forecast for this hour")
        }
        let value = AuroraFormat.percent(cloudCover)
        switch sky {
        case .unknown, .overcast:
            return Factor(kind: .clouds, status: .bad, summary: "\(value) cloud blocks the sky")
        case .partlyCloudy where cloudCover < 20:
            return Factor(kind: .clouds, status: .fair, summary: "Mostly clear (\(value) cloud)")
        case .partlyCloudy:
            return Factor(kind: .clouds, status: .fair, summary: "Partly cloudy (\(value)); look for gaps")
        case .clear:
            return Factor(kind: .clouds, status: .good, summary: "Clear skies (\(value) cloud)")
        }
    }

    private func darknessFactor(darkness: Darkness, sunElevation: Double, kpLevel: KpLevel) -> Factor {
        let sun = "sun at \(AuroraFormat.signedDegrees(sunElevation))"
        switch darkness {
        case .night:
            return Factor(kind: .darkness, status: .good, summary: "Fully dark (\(sun))")
        case .astronomicalTwilight:
            return Factor(kind: .darkness, status: .good, summary: "Dark enough (\(sun))")
        case .nauticalTwilight where kpLevel == .high:
            return Factor(kind: .darkness, status: .fair, summary: "Twilight (\(sun)); only strong aurora shows through")
        case .nauticalTwilight:
            return Factor(kind: .darkness, status: .bad, summary: "Twilight (\(sun)); too bright for weak aurora")
        case .civilTwilight, .daylight:
            return Factor(kind: .darkness, status: .bad, summary: "\(darkness.label); sky too bright (\(sun))")
        }
    }
}

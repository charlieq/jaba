import Foundation
import Testing
@testable import JABAKit

struct ScoringTests {
    // A location that needs Kp 4.5 for aurora on the horizon (roughly Canmore).
    let scorer = AuroraScorer(requiredKp: 4.5)
    let t = Date(timeIntervalSince1970: 0)

    func verdict(kp: Double?, cloud: Double?, sun: Double) -> Verdict {
        scorer.assess(time: t, kp: kp, cloudCover: cloud, sunElevation: sun).verdict
    }

    @Test func lowKpIsNoEvenWhenClearAndDark() {
        let hour = scorer.assess(time: t, kp: 2.0, cloudCover: 0, sunElevation: -30)
        #expect(hour.verdict == .no)
        #expect(hour.score == 0)
        #expect(hour.kpLevel == .tooLow)
    }

    @Test func overFiftyPercentCloudIsNo() {
        #expect(verdict(kp: 8, cloud: 51, sun: -30) == .no)
        #expect(verdict(kp: 8, cloud: 50, sun: -30) == .maybe)
    }

    @Test func daylightAndCivilTwilightAreAlwaysNo() {
        #expect(verdict(kp: 9, cloud: 0, sun: 10) == .no)
        #expect(verdict(kp: 9, cloud: 0, sun: -3) == .no)
    }

    @Test func nauticalTwilightNeedsHighKpAndCapsAtMaybe() {
        #expect(verdict(kp: 6.0, cloud: 0, sun: -8) == .maybe)
        #expect(verdict(kp: 5.0, cloud: 0, sun: -8) == .no)
    }

    @Test func highKpClearAndDarkIsGo() {
        let hour = scorer.assess(time: t, kp: 6.0, cloudCover: 5, sunElevation: -25)
        #expect(hour.verdict == .go)
        #expect((70...100).contains(hour.score))
        #expect(verdict(kp: 6.0, cloud: 5, sun: -14) == .go)
    }

    @Test func moderateKpIsMaybeEvenWhenPerfectlyClear() {
        // Just under the naked-eye threshold: camera territory.
        #expect(verdict(kp: 4.0, cloud: 0, sun: -25) == .maybe)
        // At the threshold but not a full Kp above it.
        #expect(verdict(kp: 5.0, cloud: 0, sun: -25) == .maybe)
    }

    @Test func partlyCloudyCapsAtMaybe() {
        #expect(verdict(kp: 7, cloud: 30, sun: -25) == .maybe)
        #expect(verdict(kp: 7, cloud: 15, sun: -25) == .maybe)
        #expect(verdict(kp: 7, cloud: 9.9, sun: -25) == .go)
    }

    @Test func missingDataNeverProducesGo() {
        #expect(verdict(kp: nil, cloud: 0, sun: -25) == .no)
        #expect(verdict(kp: 7, cloud: nil, sun: -25) == .maybe)
    }

    @Test func scoreAlwaysFallsInsideItsVerdictBand() {
        for kp in stride(from: 0.0, through: 9.0, by: 0.33) {
            for cloud in stride(from: 0.0, through: 100.0, by: 5.0) {
                for sun in [-30.0, -15, -8, -3, 5] {
                    let hour = scorer.assess(time: t, kp: kp, cloudCover: cloud, sunElevation: sun)
                    #expect(hour.verdict.scoreRange.contains(hour.score), "kp \(kp) cloud \(cloud) sun \(sun)")
                }
            }
        }
    }

    @Test func scoreRewardsStrongerActivityAndClearerSkies() {
        func score(_ kp: Double, _ cloud: Double) -> Int {
            scorer.assess(time: t, kp: kp, cloudCover: cloud, sunElevation: -25).score
        }
        #expect(score(8, 2) > score(6, 2))
        #expect(score(6, 0) > score(6, 8))
        #expect(score(5, 20) > score(5, 45))
    }

    @Test func factorsExplainEachInput() {
        let hour = scorer.assess(time: t, kp: 6.0, cloudCover: 5, sunElevation: -25)
        #expect(hour.factors.map(\.status) == [.good, .good, .good])
        #expect(hour.factors[0].summary.contains("6.0"))
    }
}

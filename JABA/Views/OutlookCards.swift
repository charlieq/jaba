import JABAKit
import SwiftUI

// MARK: - Nights

/// Tonight and the following nights, laid out like the Weather app's 10-day list.
/// The bar shows the night's Kp range on a 0–9 scale, with a tick at the Kp needed here.
struct NightsCard: View {
    let outlook: AuroraOutlook
    @State private var expanded: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(title: "\(outlook.nights.count)-Night Outlook", subtitle: "Overnight Kp range · tap a night for details")
                .padding(.bottom, 8)
            ForEach(outlook.nights) { night in
                Divider().overlay(.white.opacity(0.18))
                VStack(alignment: .leading, spacing: 10) {
                    NightRow(night: night, requiredKp: outlook.geomagnetic.requiredKp, timeZone: outlook.timeZone)
                    if expanded == night.id {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(night.reasoning.dropFirst().enumerated()), id: \.offset) { _, line in
                                Bullet(text: line)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) { expanded = expanded == night.id ? nil : night.id }
                }
            }
        }
        .card()
    }
}

private struct NightRow: View {
    let night: NightReport
    let requiredKp: Double
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(night.isTonight ? "Tonight" : AuroraFormat.weekday(night.window.start, in: timeZone))
                    .font(.title3.weight(.semibold))
                if let clouds = night.cloudRange {
                    Text("\(Image(systemName: "cloud.fill")) \(AuroraFormat.percent(clouds.lowerBound))–\(AuroraFormat.percent(clouds.upperBound))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 86, alignment: .leading)

            VStack(spacing: 2) {
                Image(systemName: night.verdict.symbol)
                    .symbolRenderingMode(.hierarchical)
                Text("\(night.score)").font(.caption.bold()).monospacedDigit()
            }
            .foregroundStyle(night.verdict.color)
            .frame(width: 40)

            if let range = night.kpRange {
                Text(AuroraFormat.kp(range.lowerBound))
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, alignment: .trailing)
                KpRangeBar(range: range, requiredKp: requiredKp)
                Text(AuroraFormat.kp(range.upperBound))
                    .font(.headline)
                    .frame(width: 32, alignment: .leading)
            } else {
                Text("No Kp forecast yet")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct KpRangeBar: View {
    let range: ClosedRange<Double>
    let requiredKp: Double
    private let scale = 9.0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let lo = min(1, range.lowerBound / scale), hi = min(1, range.upperBound / scale)
            let need = min(1, requiredKp / scale)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(gradient)
                    .mask(alignment: .leading) {
                        Capsule()
                            .frame(width: max(6, width * (hi - lo)))
                            .offset(x: width * lo)
                    }
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: 12)
                    .offset(x: width * need - 1.25)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
    }

    /// Gray well below the local threshold, amber near it, green above it.
    private var gradient: LinearGradient {
        func stop(_ kp: Double) -> Double { min(1, max(0, kp / scale)) }
        return LinearGradient(
            stops: [
                .init(color: .quietGray.opacity(0.6), location: stop(requiredKp - 1.5)),
                .init(color: .maybeAmber, location: stop(requiredKp - 0.5)),
                .init(color: .auroraGreen, location: stop(requiredKp + 1)),
                .init(color: .auroraViolet, location: stop(requiredKp + 3)),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

// MARK: - Nowcast

/// NOAA's 30-minute OVATION model for this spot: the "right now" check.
struct NowcastCard: View {
    let outlook: AuroraOutlook

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Right Now", subtitle: "NOAA 30-minute aurora model")
            if let nowcast = outlook.nowcast {
                HStack(spacing: 24) {
                    gauge(nowcast.inViewProbability, label: "In view")
                    gauge(nowcast.overheadProbability, label: "Overhead")
                    Text(interpretation(nowcast))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Valid around \(AuroraFormat.time(nowcast.forecastTime, in: outlook.timeZone)). \"In view\" is the highest chance within about 600 km, which you might see low on the horizon.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text("No recent nowcast. It needs a connection and is only useful for the next hour or so.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .card()
    }

    private func gauge(_ percent: Int, label: String) -> some View {
        VStack(spacing: 6) {
            Gauge(value: Double(percent), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text("\(percent)%").font(.caption.bold())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(color(percent))
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func color(_ percent: Int) -> Color {
        percent >= 30 ? .auroraGreen : percent >= 10 ? .maybeAmber : .quietGray
    }

    private func interpretation(_ nowcast: Nowcast) -> String {
        let p = nowcast.inViewProbability
        var text: String
        switch p {
        case 50...: text = "Strong aurora likely within view."
        case 20..<50: text = "Aurora likely on the horizon if skies are clear."
        case 5..<20: text = "Weak activity nearby; a camera might catch it."
        default: text = "Little aurora activity within view."
        }
        if let current = outlook.current {
            if !current.darkness.isDark {
                text += " It's too light here right now to see it."
            } else if let cloud = current.cloudCover, cloud > 50 {
                text += " Clouds (\(AuroraFormat.percent(cloud))) are in the way."
            }
        }
        return text
    }
}

// MARK: - Tiles

/// Square info tiles like the Weather app's UV index / sunset tiles.
struct InfoTiles: View {
    let outlook: AuroraOutlook

    var body: some View {
        let tz = outlook.timeZone
        let night = outlook.tonight
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
            Tile(
                title: "Magnetic Lat.", symbol: "location.north.circle.fill",
                value: AuroraFormat.degrees(outlook.geomagnetic.magneticLatitude),
                detail: outlook.geomagnetic.isOutOfReach
                    ? "Too far south for aurora, even in a Kp 9 storm."
                    : "Aurora reaches your horizon at about Kp \(AuroraFormat.kp(outlook.geomagnetic.requiredKp))."
            )
            Tile(
                title: "Kp Now", symbol: "sparkles",
                value: outlook.currentKpBin.map { AuroraFormat.kp($0.kp) } ?? "–",
                detail: kpNowDetail
            )
            Tile(
                title: "Sunset", symbol: "sunset.fill",
                value: night.sunset.map { AuroraFormat.time($0, in: tz) } ?? "–",
                detail: night.sunrise.map { "Sunrise \(AuroraFormat.time($0, in: tz))" } ?? "No sunrise tomorrow"
            )
            Tile(
                title: "Dark Sky", symbol: "moon.stars.fill",
                value: night.darkStart.map { AuroraFormat.time($0, in: tz) } ?? "–",
                detail: night.darkEnd.map { "Until \(AuroraFormat.time($0, in: tz)), sun below −12°" } ?? "Never fully dark tonight"
            )
        }
    }

    private var kpNowDetail: String {
        guard let bin = outlook.currentKpBin else { return "No current Kp data" }
        let source = bin.kind == .observed ? "Observed" : bin.kind == .estimated ? "Estimated" : "Forecast"
        let level = outlook.current?.kpLevel
        let meaning = switch level {
        case .high: "Strong enough to see here."
        case .moderate: "Marginal here; camera territory."
        default: "Too weak to see here."
        }
        return "\(source). \(meaning)"
    }
}

private struct Tile: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 34, weight: .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text(detail)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: 132, alignment: .topLeading)
        .card()
    }
}

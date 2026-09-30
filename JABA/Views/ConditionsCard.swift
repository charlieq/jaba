import JABAKit
import SwiftUI

/// The hourly strip, toggling between Kp index and cloud cover like the Weather app's Conditions card.
struct ConditionsCard: View {
    enum Metric: String, CaseIterable, Identifiable {
        case kp, clouds
        var id: Self { self }

        var symbol: String {
            switch self {
            case .kp: "sparkles"
            case .clouds: "cloud.fill"
            }
        }

        var title: String {
            switch self {
            case .kp: "Kp Index"
            case .clouds: "Cloud Cover"
            }
        }
    }

    let outlook: AuroraOutlook
    @Binding var metric: Metric
    @Namespace private var toggle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                CardTitle(title: "Conditions", subtitle: subtitle)
                Spacer()
                picker
            }
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(outlook.timeline) { entry in
                        HourColumn(entry: entry, metric: metric, requiredKp: outlook.geomagnetic.requiredKp, timeZone: outlook.timeZone)
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .card()
    }

    private var subtitle: String {
        switch metric {
        case .kp: "Kp Index · \(AuroraFormat.kp(outlook.geomagnetic.requiredKp)) needed here"
        case .clouds: "Cloud Cover (%)"
        }
    }

    private var footnote: String {
        switch metric {
        case .kp: "Dashes mark the Kp needed here. NOAA forecasts Kp in 3-hour blocks. Tinted hours rate GO or MAYBE."
        case .clouds: "Dashes mark 50% cloud; above that the sky is blocked. Tinted hours rate GO or MAYBE."
        }
    }

    private var picker: some View {
        HStack(spacing: 0) {
            ForEach(Metric.allCases) { item in
                Button {
                    withAnimation(.snappy) { metric = item }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 48, height: 34)
                        .background {
                            if metric == item {
                                Capsule().fill(.white.opacity(0.22)).matchedGeometryEffect(id: "selection", in: toggle)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(metric == item ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct HourColumn: View {
    let entry: TimelineEntry
    let metric: ConditionsCard.Metric
    let requiredKp: Double
    let timeZone: TimeZone

    private static let barHeight: CGFloat = 56
    private static let kpScale = 9.0

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            icon
                .font(.system(size: 22))
                .frame(height: 26)
            bar
                .frame(height: Self.barHeight)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 52)
        .padding(.vertical, 8)
        .background {
            if let hour, hour.verdict != .no {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hour.verdict.color.opacity(0.16))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var hour: HourAssessment? {
        if case let .hour(hour) = entry.kind { return hour }
        return nil
    }

    private var label: String {
        switch entry.kind {
        case .hour: entry.isNow ? "Now" : AuroraFormat.hour(entry.date, in: timeZone)
        case .sunset, .sunrise: AuroraFormat.time(entry.date, in: timeZone)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .sunset:
            Image(systemName: "sunset.fill").symbolRenderingMode(.multicolor)
        case .sunrise:
            Image(systemName: "sunrise.fill").symbolRenderingMode(.multicolor)
        case let .hour(hour):
            switch metric {
            case .kp:
                if hour.darkness == .daylight {
                    Image(systemName: "sun.max.fill").symbolRenderingMode(.multicolor)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(hour.kpLevel.color.opacity(hour.kpLevel >= .moderate ? 1 : 0.5))
                }
            case .clouds:
                Image(systemName: SkySymbol.name(cloudCover: hour.cloudCover, darkness: hour.darkness))
                    .symbolRenderingMode(.multicolor)
            }
        }
    }

    private var bar: some View {
        ZStack(alignment: .bottom) {
            if let spec = barSpec {
                Capsule().fill(.white.opacity(0.1)).frame(width: 8)
                Capsule().fill(spec.color.gradient)
                    .frame(width: 8, height: max(4, Self.barHeight * min(1, spec.fraction)))
                Rectangle().fill(.white.opacity(0.7))
                    .frame(width: 22, height: 1.5)
                    .offset(y: -Self.barHeight * min(1, spec.marker))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Bar fill (0…1), where to draw the threshold dash (0…1), and the bar color.
    private var barSpec: (fraction: Double, marker: Double, color: Color)? {
        guard let hour else { return nil }
        switch metric {
        case .kp:
            return ((hour.kp ?? 0) / Self.kpScale, requiredKp / Self.kpScale, hour.kpLevel.color)
        case .clouds:
            return ((hour.cloudCover ?? 0) / 100, 0.5, hour.sky.color)
        }
    }

    private var value: String {
        switch entry.kind {
        case .sunset: return "Sunset"
        case .sunrise: return "Sunrise"
        case let .hour(hour):
            switch metric {
            case .kp: return hour.kp.map { AuroraFormat.kp($0) } ?? "–"
            case .clouds: return hour.cloudCover.map(AuroraFormat.percent) ?? "–"
            }
        }
    }

    private var accessibilityText: String {
        guard let hour else { return "\(value) at \(label)" }
        let kp = hour.kp.map { "Kp \(AuroraFormat.kp($0))" } ?? "no Kp forecast"
        let cloud = hour.cloudCover.map { "\(AuroraFormat.percent($0)) cloud" } ?? "no cloud forecast"
        return "\(label): \(kp), \(cloud), \(hour.darkness.label), \(hour.verdict.label)"
    }
}

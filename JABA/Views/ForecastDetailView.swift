import JABAKit
import SwiftUI

/// Full-screen, swipeable forecast pages, like the Weather app's city pages.
struct ForecastPager: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var selection: UUID?

    var body: some View {
        TimelineView(.everyMinute) { context in
            TabView(selection: $selection) {
                ForEach(model.locations) { location in
                    ForecastDetailView(location: location, now: context.date)
                        .tag(Optional(location.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { bottomBar }
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            HStack {
                Button {
                    Task { await model.refresh(force: true) }
                } label: {
                    Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.title3.weight(.semibold))
                        .symbolEffect(.rotate, isActive: model.isRefreshing)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Refresh")

                Spacer()

                HStack(spacing: 10) {
                    ForEach(model.locations) { location in
                        Circle()
                            .fill(.white.opacity(location.id == selection ? 1 : 0.4))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .glassEffect(.regular, in: .capsule)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Locations")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}

struct ForecastDetailView: View {
    @Environment(AppModel.self) private var model
    let location: SavedLocation
    let now: Date
    @State private var metric: ConditionsCard.Metric = .kp

    var body: some View {
        let outlook = model.outlook(for: location, now: now)
        ScrollView {
            VStack(spacing: 14) {
                header(outlook)
                    .padding(.top, 90)
                    .padding(.bottom, 36)

                if let status = model.statusMessage(for: location, now: now) {
                    StatusBanner(text: status)
                }

                if let outlook {
                    TonightCard(outlook: outlook)
                    ConditionsCard(outlook: outlook, metric: $metric)
                    NightsCard(outlook: outlook)
                    NowcastCard(outlook: outlook)
                    InfoTiles(outlook: outlook)
                    SourcesFooter(fetchedAt: model.fetchedAt(location), kpFetchedAt: model.kp?.fetchedAt)
                } else if let error = model.data[location.id]?.error {
                    Text(error).card()
                } else {
                    ProgressView("Loading forecast…").frame(maxWidth: .infinity).card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh(force: true) }
        .foregroundStyle(.white)
        .background {
            SkyBackground(style: SkyStyle(location: location, outlook: outlook), animated: true)
                .ignoresSafeArea()
        }
    }

    private func header(_ outlook: AuroraOutlook?) -> some View {
        let night = outlook?.tonight
        return VStack(spacing: 0) {
            Text(location.name)
                .font(.system(size: 36, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(night.map { "\($0.score)" } ?? "–")
                .font(.system(size: 112, weight: .thin))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let night {
                Text("\(Text(night.verdict.label).foregroundStyle(night.verdict.color)) · \(night.verdict.advice)")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                detailLine(night)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 10)
        .frame(maxWidth: .infinity)
    }

    private func detailLine(_ night: NightReport) -> Text {
        let kp = night.kpRange.map { "Kp \(AuroraFormat.kp($0.upperBound))" } ?? "Kp –"
        switch night.verdict {
        case .go:
            let cloud = night.best?.cloudCover.map(AuroraFormat.percent) ?? "–"
            return Text("\(night.headline)  \(kp)  \(Image(systemName: "cloud.fill")) \(cloud)")
        case .maybe:
            let cloud = night.best?.cloudCover.map(AuroraFormat.percent) ?? "–"
            return Text("\(night.headline)  \(Image(systemName: "cloud.fill")) \(cloud)")
        case .no:
            return Text("\(night.headline) · peak \(kp)")
        }
    }
}

// MARK: - Tonight

/// The verdict with its reasoning, best time, and the factors behind it.
struct TonightCard: View {
    let outlook: AuroraOutlook

    private var night: NightReport { outlook.tonight }

    /// The hour to break down: the best one, or the dark hour that came closest.
    private var featured: HourAssessment? {
        if let best = night.best { return best }
        let dark = night.hours.filter { $0.darkness.isDark }
        return (dark.isEmpty ? night.hours : dark).min { a, b in
            let badA = a.factors.filter { $0.status == .bad }.count
            let badB = b.factors.filter { $0.status == .bad }.count
            return badA != badB ? badA < badB : a.time < b.time
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                CardTitle(title: "Tonight", subtitle: "Should you get out of the tent?")
                Spacer()
                Label(night.verdict.label, systemImage: night.verdict.symbol)
                    .font(.headline)
                    .foregroundStyle(night.verdict.color)
            }

            if let best = night.best, let window = night.bestWindow {
                BestTimeRow(best: best, window: window, timeZone: outlook.timeZone, verdict: night.verdict)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(night.reasoning.enumerated()), id: \.offset) { _, line in
                    Bullet(text: line)
                }
            }

            if let featured {
                Divider().overlay(.white.opacity(0.2))
                VStack(alignment: .leading, spacing: 8) {
                    Text("At \(AuroraFormat.time(featured.time, in: outlook.timeZone))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(featured.factors, id: \.summary) { factor in
                        Label {
                            Text(factor.summary).font(.subheadline)
                        } icon: {
                            Image(systemName: factor.status.symbol).foregroundStyle(factor.status.color)
                        }
                    }
                }
            }
        }
        .card()
    }
}

private struct BestTimeRow: View {
    let best: HourAssessment
    let window: DateInterval
    let timeZone: TimeZone
    let verdict: Verdict

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict == .go ? "BEST TIME" : "PHOTO CHECK")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(verdict.color)
                Text(AuroraFormat.timeRange(window.start, window.end, in: timeZone))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            stat(best.kp.map { AuroraFormat.kp($0) } ?? "–", "Kp")
            stat(best.cloudCover.map(AuroraFormat.percent) ?? "–", "Cloud")
            if let temp = Temperature.text(best.temperature) {
                stat(temp, "Temp")
            }
        }
        .padding(12)
        .background(verdict.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Footer

struct SourcesFooter: View {
    let fetchedAt: Date?
    let kpFetchedAt: Date?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("Kp:")
                Link("NOAA SWPC", destination: URL(string: "https://www.swpc.noaa.gov/products/3-day-forecast")!)
                Text("via")
                Link("gi.alaska.edu", destination: URL(string: "https://www.gi.alaska.edu/monitors/aurora-forecast")!)
                Text("· Weather:")
                Link("Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
            }
            if let fetchedAt {
                Text("Weather updated \(fetchedAt.formatted(.relative(presentation: .named)))"
                    + (kpFetchedAt.map { " · Kp updated \($0.formatted(.relative(presentation: .named)))" } ?? ""))
            }
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.6))
        .tint(.white.opacity(0.85))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

import JABAKit
import SwiftUI

struct LocationListView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var presented: SavedLocation?
    @State private var editMode: EditMode = .inactive
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    locationList
                } else {
                    SearchResultsView(results: results, isSearching: isSearching, error: searchError) { place in
                        model.add(place)
                        query = ""
                    }
                }
            }
            .background(LinearGradient(colors: [.nightTop, .nightBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("JABA")
            .toolbar {
                if editMode.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { withAnimation { editMode = .inactive } }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit List", systemImage: "pencil") { withAnimation { editMode = .active } }
                            Button("Alerts & Settings", systemImage: "bell.badge") { showSettings = true }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search for a city or town")
            .task(id: query) { await search() }
            .environment(\.editMode, $editMode)
        }
        .task { await model.refresh() }
        .fullScreenCover(item: $presented) { location in
            ForecastPager(selection: location.id)
                .environment(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(model)
        }
    }

    private var locationList: some View {
        TimelineView(.everyMinute) { context in
            List {
                if let status = model.statusMessage(now: context.date) {
                    StatusBanner(text: status)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(model.locations) { location in
                    Button {
                        presented = location
                    } label: {
                        LocationCard(location: location, outlook: model.outlook(for: location, now: context.date),
                                     error: model.data[location.id]?.error, now: context.date)
                    }
                    .buttonStyle(.plain)
                    .disabled(editMode.isEditing)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onDelete { model.remove(atOffsets: $0) }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }

                footer
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await model.refresh(force: true) }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if model.isRefreshing {
                ProgressView().padding(.bottom, 4)
            }
            Text("Kp forecast from NOAA SWPC (shown on gi.alaska.edu) · Weather from Open-Meteo")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await model.client.searchPlaces(matching: text)
            searchError = nil
        } catch {
            if !Task.isCancelled {
                results = []
                searchError = "Couldn't search right now. Check your connection."
            }
        }
    }
}

/// One row of the location list, styled after the Weather app's city cards.
struct LocationCard: View {
    let location: SavedLocation
    let outlook: AuroraOutlook?
    let error: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(outlook.map { "\($0.tonight.score)" } ?? "–")
                    .font(.system(size: 54, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 10)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                summary
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let outlook {
                    conditions(outlook)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 6)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(height: 128)
        .background { SkyBackground(style: SkyStyle(location: location, outlook: outlook)) }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let place = location.region ?? location.country ?? ""
        guard let outlook else { return place }
        let time = AuroraFormat.time(now, in: outlook.timeZone)
        return place.isEmpty ? time : "\(time) · \(place)"
    }

    @ViewBuilder
    private var summary: some View {
        if let night = outlook?.tonight {
            Text("\(Text(night.verdict.label).bold().foregroundStyle(night.verdict.color)) · \(night.headline)")
                .font(.subheadline.weight(.medium))
        } else if let error {
            Text(error).font(.footnote)
        } else {
            Text("Loading forecast…").font(.subheadline)
        }
    }

    private func conditions(_ outlook: AuroraOutlook) -> Text {
        let night = outlook.tonight
        let kp = night.kpRange.map { "Kp \(AuroraFormat.kp($0.upperBound))" } ?? "Kp –"
        let cloud = (night.best?.cloudCover ?? night.cloudRange?.lowerBound).map(AuroraFormat.percent) ?? "–"
        return Text("\(kp)  \(Image(systemName: "cloud.fill")) \(cloud)")
    }
}

struct SearchResultsView: View {
    let results: [Place]
    let isSearching: Bool
    let error: String?
    let onSelect: (Place) -> Void

    var body: some View {
        List {
            Group {
                if let error {
                    Label(error, systemImage: "wifi.slash").foregroundStyle(.secondary)
                } else if results.isEmpty {
                    if isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text("No places found").foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(Color.clear)
            ForEach(results) { place in
                Button {
                    onSelect(place)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(.body.weight(.semibold))
                            Text(place.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        needs(place)
                    }
                }
                .tint(.primary)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func needs(_ place: Place) -> some View {
        let geo = GeomagneticInfo(latitude: place.latitude, longitude: place.longitude)
        return Text(geo.isOutOfReach ? "Out of range" : "Kp \(AuroraFormat.kp(geo.requiredKp)) needed")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

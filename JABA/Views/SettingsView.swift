import JABAKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Alert me when it's GO", isOn: Binding(
                        get: { model.alertsEnabled },
                        set: { value in Task { await model.setAlertsEnabled(value) } }
                    ))
                    Toggle("Also alert for MAYBE (photo check)", isOn: Binding(
                        get: { model.alertOnMaybe },
                        set: { value in Task { await model.setAlertOnMaybe(value) } }
                    ))
                    .disabled(!model.alertsEnabled)
                    if model.notificationsDenied {
                        Button("Turn on notifications in Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("JABA schedules a notification 10 minutes before each GO window, so it goes off even if your phone has no signal. When JABA can refresh in the background, it also updates those alerts and tells you if NOAA's 30-minute model shows aurora in view. iOS decides how often background refreshes run, so open JABA in the evening for the latest forecast.")
                }

                Section {
                    ScoreRule(verdict: .go, text: "Kp at least 1 above what this location needs, under 10% cloud, and dark (sun below −12°).")
                    ScoreRule(verdict: .maybe, text: "Kp within about 1 of what's needed, or 10–50% cloud, or deep twilight during a strong storm. Step out and take a photo facing north; cameras pick up aurora the eye misses.")
                    ScoreRule(verdict: .no, text: "Kp more than 1 below what's needed, over 50% cloud, or too light: daylight, or twilight without a strong storm.")
                } header: {
                    Text("How the score works")
                } footer: {
                    Text("The Kp needed comes from each location's magnetic latitude. Scores run 70–100 for GO, 30–69 for MAYBE and 0 for NO. Within a band, Kp strength counts most, then clear skies, then darkness. Tonight's score is the best hour between sunset and sunrise.")
                }

                Section("Data sources") {
                    Link("NOAA SWPC 3-day Kp forecast", destination: URL(string: "https://www.swpc.noaa.gov/products/3-day-forecast")!)
                    Link("UAF Geophysical Institute aurora forecast", destination: URL(string: "https://www.gi.alaska.edu/monitors/aurora-forecast")!)
                    Link("NOAA 30-minute aurora forecast", destination: URL(string: "https://www.swpc.noaa.gov/products/aurora-30-minute-forecast")!)
                    Link("Open-Meteo weather", destination: URL(string: "https://open-meteo.com")!)
                }

                Section {
                    LabeledContent("JABA", value: "Julie's Aurora Borealis App")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ScoreRule: View {
    let verdict: Verdict
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(verdict.label, systemImage: verdict.symbol)
                .font(.subheadline.bold())
                .foregroundStyle(verdict.color)
                .frame(width: 92, alignment: .leading)
            Text(text).font(.subheadline)
        }
    }
}

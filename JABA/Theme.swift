import JABAKit
import SwiftUI

extension Color {
    static let auroraGreen = Color(red: 0.36, green: 0.95, blue: 0.62)
    static let auroraTeal = Color(red: 0.22, green: 0.86, blue: 0.84)
    static let auroraViolet = Color(red: 0.66, green: 0.45, blue: 1.0)
    static let maybeAmber = Color(red: 1.0, green: 0.80, blue: 0.36)
    static let quietGray = Color(white: 0.72)
    static let nightTop = Color(red: 0.03, green: 0.05, blue: 0.14)
    static let nightBottom = Color(red: 0.11, green: 0.15, blue: 0.27)
}

extension Verdict {
    var color: Color {
        switch self {
        case .go: .auroraGreen
        case .maybe: .maybeAmber
        case .no: .quietGray
        }
    }

    var symbol: String {
        switch self {
        case .go: "sparkles"
        case .maybe: "camera.fill"
        case .no: "moon.zzz.fill"
        }
    }
}

extension KpLevel {
    var color: Color {
        switch self {
        case .high: .auroraGreen
        case .moderate: .maybeAmber
        case .tooLow, .unknown: .quietGray
        }
    }
}

extension SkyLevel {
    var color: Color {
        switch self {
        case .clear: .auroraGreen
        case .partlyCloudy: .maybeAmber
        case .overcast, .unknown: .quietGray
        }
    }
}

extension Factor.Status {
    var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .fair: "exclamationmark.circle.fill"
        case .bad: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .good: .auroraGreen
        case .fair: .maybeAmber
        case .bad: Color(red: 1.0, green: 0.52, blue: 0.5)
        }
    }
}

enum SkySymbol {
    /// Weather-style cloud glyph for a cloud percentage, day or night.
    static func name(cloudCover: Double?, darkness: Darkness) -> String {
        let night = darkness >= .civilTwilight
        guard let cloud = cloudCover else { return "questionmark.circle" }
        switch cloud {
        case ..<10: return night ? "moon.stars.fill" : "sun.max.fill"
        case ..<50: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        default: return "cloud.fill"
        }
    }
}

enum Temperature {
    static func text(_ celsius: Double?) -> String? {
        celsius.map {
            Measurement(value: $0, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
    }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.nightTop.opacity(0.25))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// "Conditions" / "Temperature (°F)" style heading used by every card.
struct CardTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.bold())
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

struct StatusBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: text.hasPrefix("Offline") ? "wifi.slash" : "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity)
    }
}

struct Bullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

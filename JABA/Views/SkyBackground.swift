import JABAKit
import SwiftUI

/// What the sky backdrop should show: aurora strength and cloudiness for tonight's best moment.
struct SkyStyle {
    var aurora: Double
    var cloud: Double
    var seed: UInt64

    init(outlook: AuroraOutlook?, seed: UInt64) {
        let night = outlook?.tonight
        aurora = Double(night?.score ?? 0) / 100
        let featured = night?.best ?? night?.hours.first { $0.darkness.isDark } ?? night?.hours.first
        cloud = (featured?.cloudCover ?? night?.cloudRange?.lowerBound ?? 0) / 100
        self.seed = seed
    }

    init(location: SavedLocation, outlook: AuroraOutlook?) {
        let seed = UInt64(abs(location.latitude * 1_000)) &* 31 &+ UInt64(abs(location.longitude * 1_000))
        self.init(outlook: outlook, seed: seed)
    }
}

/// Night sky with stars, aurora curtains scaled by the score, and clouds scaled by cloud cover.
struct SkyBackground: View {
    let style: SkyStyle
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                sky(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            sky(time: 0)
        }
    }

    private func sky(time: Double) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let overcast = style.cloud
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [
                    mix(.nightTop, Color(red: 0.19, green: 0.21, blue: 0.26), overcast),
                    mix(.nightBottom, Color(red: 0.33, green: 0.36, blue: 0.42), overcast),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))

            var rng = SplitMix64(seed: style.seed)
            let starCount = Int(size.width * size.height / 2_600)
            for _ in 0..<starCount {
                let x = rng.unit() * size.width
                let y = rng.unit() * size.height * 0.75
                let radius = 0.4 + rng.unit() * 0.9
                let twinkle = 0.75 + 0.25 * sin(time * (0.6 + rng.unit()) + rng.unit() * 6.3)
                let opacity = (0.25 + rng.unit() * 0.6) * (1 - overcast) * twinkle
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(opacity))
                )
            }

            if style.aurora > 0 {
                drawAurora(in: &context, size: size, time: time, strength: style.aurora * (1 - overcast * 0.6))
            }
            if overcast > 0.05 {
                drawClouds(in: &context, size: size, time: time, amount: overcast, rng: &rng)
            }
        }
    }

    private func drawAurora(in context: inout GraphicsContext, size: CGSize, time: Double, strength: Double) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(6, size.width * 0.03)))
            let bands: [(y: Double, color: Color, phase: Double)] = [
                (0.20, .auroraGreen, 0.0),
                (0.28, .auroraTeal, 2.1),
                (0.14, .auroraViolet, 4.0),
            ]
            for band in bands {
                let baseY = size.height * band.y
                let rayHeight = size.height * 0.16
                var x = 0.0
                while x < size.width {
                    let u = x / max(size.width, 1)
                    let wave = sin(u * .pi * 2.6 + band.phase + time * 0.12) * size.height * 0.035
                        + sin(u * .pi * 7.1 + time * 0.21) * size.height * 0.012
                    let flicker = 0.55 + 0.45 * sin(u * 23 + band.phase * 3 + time * 0.8)
                    let y = baseY + wave
                    let ray = Path(CGRect(x: x, y: y - rayHeight, width: 5, height: rayHeight))
                    layer.fill(ray, with: .linearGradient(
                        Gradient(colors: [band.color.opacity(0), band.color.opacity(0.75 * strength * flicker)]),
                        startPoint: CGPoint(x: x, y: y - rayHeight), endPoint: CGPoint(x: x, y: y)
                    ))
                    x += 4
                }
            }
        }
    }

    private func drawClouds(in context: inout GraphicsContext, size: CGSize, time: Double, amount: Double, rng: inout SplitMix64) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(10, size.height * 0.08)))
            let count = 3 + Int(amount * 9)
            for _ in 0..<count {
                let w = size.width * (0.35 + rng.unit() * 0.5)
                let h = size.height * (0.12 + rng.unit() * 0.2)
                let drift = (time * 4 * (0.5 + rng.unit())).truncatingRemainder(dividingBy: size.width + w)
                let x = (rng.unit() * (size.width + w) + drift).truncatingRemainder(dividingBy: size.width + w) - w * 0.7
                let y = rng.unit() * size.height * 0.85 - h * 0.3
                layer.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)),
                    with: .color(Color(white: 0.78).opacity(0.18 + 0.3 * amount))
                )
            }
        }
    }

    private func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ra = a.resolve(in: EnvironmentValues()), rb = b.resolve(in: EnvironmentValues())
        let f = Float(min(1, max(0, t)))
        return Color(
            red: Double(ra.red + (rb.red - ra.red) * f),
            green: Double(ra.green + (rb.green - ra.green) * f),
            blue: Double(ra.blue + (rb.blue - ra.blue) * f)
        )
    }
}

/// Small deterministic RNG so each location keeps the same star field.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

import RideKit
import SwiftUI

/// The weather behind the riding screen's numbers: rain falling behind the digits, wind streaks,
/// a sun glow by the speed. Faint by design — the numbers always win — and it follows the weather
/// *now*, so it starts when the rain does. No lightning flashes: a sudden flash at the edge of
/// vision startles at speed (and flashing is a photosensitivity risk). Still with Reduce Motion.
struct WeatherAmbience: View {
    let sky: WeatherSky
    var isDaytime = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || !moves {
                Canvas { canvas, size in draw(in: &canvas, size: size, time: 0) }
            } else {
                TimelineView(.animation) { context in
                    Canvas { canvas, size in
                        draw(in: &canvas, size: size, time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var moves: Bool { [.rain, .storm, .wind].contains(sky) }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        switch sky {
        case .rain:
            tint(in: &canvas, size: size, Brand.Sky.rain[0], 0.35)
            rain(in: &canvas, size: size, time: time, drops: 46, speed: 0.9, opacity: 0.32)
        case .storm:
            tint(in: &canvas, size: size, Brand.Sky.storm[0], 0.5)
            rain(in: &canvas, size: size, time: time, drops: 80, speed: 1.3, opacity: 0.38)
        case .wind:
            tint(in: &canvas, size: size, Brand.Sky.wind[0], 0.3)
            wind(in: &canvas, size: size, time: time)
        case .heat:
            tint(in: &canvas, size: size, Brand.Sky.heat[0], 0.35)
            sun(in: &canvas, size: size, strength: 0.4)
        case .clear where isDaytime:
            sun(in: &canvas, size: size, strength: 0.22)
        case .partlyCloudy where isDaytime:
            sun(in: &canvas, size: size, strength: 0.12)
        default:
            break
        }
    }

    private func tint(in canvas: inout GraphicsContext, size: CGSize, _ color: Color, _ opacity: Double) {
        canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(opacity)))
    }

    /// Slanted streaks falling and wrapping, each drop at its own fixed column and phase.
    private func rain(in canvas: inout GraphicsContext, size: CGSize, time: Double, drops: Int, speed: Double, opacity: Double) {
        let length = 14.0, slant = 4.0
        var path = Path()
        for i in 0..<drops {
            let seed = Double(i) * 12.9898
            let x = (sin(seed) * 43_758.5453).truncatingRemainder(dividingBy: 1).magnitude * (size.width + slant)
            let phase = (cos(seed) * 12_345.678).truncatingRemainder(dividingBy: 1).magnitude
            let fall = (time * speed * (0.8 + phase * 0.4) + phase).truncatingRemainder(dividingBy: 1)
            let y = fall * (size.height + length) - length
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - slant, y: y + length))
        }
        canvas.stroke(path, with: .color(Brand.Sky.drop.opacity(opacity)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private func wind(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        var path = Path()
        for i in 0..<9 {
            let y = size.height * (0.12 + 0.09 * Double(i))
            let length = 34.0 + Double(i % 3) * 16
            let x = (time * (90 + Double(i) * 14) + Double(i) * 73).truncatingRemainder(dividingBy: size.width + length) - length
            path.move(to: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x + length, y: y - 2), control: CGPoint(x: x + length / 2, y: y + 3))
        }
        canvas.stroke(path, with: .color(Brand.Sky.drop.opacity(0.3)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    /// A soft warm glow behind the speed (top-left), like low sun on the cluster.
    private func sun(in canvas: inout GraphicsContext, size: CGSize, strength: Double) {
        let radius = max(size.width, size.height) * 0.55
        let center = CGPoint(x: size.width * 0.28, y: size.height * 0.2)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        canvas.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [Brand.Sky.sun.opacity(strength), Brand.Sky.sun.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius))
    }
}

extension WeatherSky {
    /// SF Symbol for the readout beside the speed (multicolour, like the Weather app).
    func symbol(isDaytime: Bool) -> String {
        switch self {
        case .clear: isDaytime ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDaytime ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .wind: "wind"
        case .heat: "sun.max.fill"
        }
    }

    /// One word for the weather line: "21° · Rain".
    var word: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .rain: "Rain"
        case .storm: "Storm"
        case .wind: "Windy"
        case .heat: "Hot"
        }
    }

    /// The 3D illustration's asset name (Assets.xcassets/Weather).
    func illustration(isDaytime: Bool) -> String {
        switch self {
        case .clear: isDaytime ? "weather-clear" : "weather-clear-night"
        case .partlyCloudy: isDaytime ? "weather-partly" : "weather-partly-night"
        case .cloudy: "weather-cloudy"
        case .rain: "weather-rain"
        case .storm: "weather-storm"
        case .wind: "weather-wind"
        case .heat: "weather-heat"
        }
    }
}

import SwiftUI
import UIKit

/// The "Milestone" look: the Indian highway km-stone. Highway yellow on asphalt while riding,
/// a chalk-white journal after. Compiled into the app and the widget extension.
enum Brand {
    // MARK: Palette — one accent, one neutral pair, one signal colour. Nothing else.

    /// The milestone cap. Use as a **fill** with `asphalt` text on it (10.6:1); never as text on white (1.6:1).
    static let highwayYellow = Color(hex: 0xF5C400)
    /// Near-black with a little warmth: road surface, primary text on yellow.
    static let asphalt = Color(hex: 0x1B1A17)
    /// Warm off-white: the stone's body, journal backgrounds.
    static let chalk = Color(hex: 0xF6F3EA)

    /// Tint for text and controls: deep ochre on light (5.5:1 on white), highway yellow on dark.
    static let accent = Color(light: 0x8A6100, dark: 0xF5C400)
    /// Recording, stop and destructive actions only.
    static let signal = Color(light: 0xC22E22, dark: 0xFF5A4A)

    // MARK: Type — signboard-wide numbers, system text for everything else.

    /// Big glanceable readouts (speed). Wide like a highway sign, tabular so digits don't jump.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    /// Secondary stats (distance, time, km on cards).
    static let stat = Font.title2.weight(.bold).width(.expanded)

    /// Small caps-style labels under stats: "DISTANCE", "TIME".
    static let label = Font.caption.weight(.semibold).width(.expanded)
}

/// The km-stone silhouette: a slab with a half-round top.
struct MilestoneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A small milestone: coloured cap over a chalk body. `filled == false` draws an outline (wishlist).
struct MilestoneMark: View {
    var cap: Color = Brand.highwayYellow
    var filled = true

    var body: some View {
        GeometryReader { geo in
            let capHeight = geo.size.width * 0.75
            ZStack(alignment: .top) {
                MilestoneShape().fill(filled ? Brand.chalk : .clear)
                MilestoneShape()
                    .fill(cap)
                    .mask(alignment: .top) { Rectangle().frame(height: capHeight) }
                MilestoneShape().stroke(Brand.asphalt, lineWidth: max(1, geo.size.width * 0.08))
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

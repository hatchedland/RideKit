import SwiftUI
import UIKit

/// Draws map markers as images, so Google Maps markers look like the rest of the app:
/// a coloured balloon with an SF Symbol, and the name underneath.
@MainActor
enum MapPinRenderer {
    struct Rendered {
        var image: UIImage
        /// Which point of the image sits on the coordinate (0…1), for `GMSMarker.groundAnchor`.
        var anchor: CGPoint
    }

    private struct Key: Hashable {
        var style: MapPin.Style
        var systemImage: String
        var tint: Color
        var label: String?
        var dark: Bool
    }

    private static var cache: [Key: Rendered] = [:]

    static func image(for pin: MapPin, dark: Bool) -> Rendered {
        let key = Key(style: pin.style, systemImage: pin.systemImage, tint: pin.tint,
                      label: pin.showsLabel && !pin.title.isEmpty ? pin.title : nil, dark: dark)
        if let cached = cache[key] { return cached }
        let rendered = render(key)
        if cache.count > 500 { cache.removeAll() }
        cache[key] = rendered
        return rendered
    }

    private static func render(_ key: Key) -> Rendered {
        let tint = UIColor(key.tint)
        let (markerSize, symbolSize): (CGSize, CGFloat) = switch key.style {
        case .balloon: (CGSize(width: 34, height: 42), 15)
        case .badge: (CGSize(width: 24, height: 24), 11)
        case .rider: (CGSize(width: 40, height: 40), 18)
        }

        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let labelText = key.label.map { String($0.prefix(28)) }
        let labelSize = labelText.map { ($0 as NSString).size(withAttributes: [.font: font]) } ?? .zero
        let width = max(markerSize.width, ceil(labelSize.width) + 8)
        let height = markerSize.height + (labelText == nil ? 0 : ceil(labelSize.height) + 2)
        let size = CGSize(width: width, height: height)

        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let originX = (width - markerSize.width) / 2
            let markerRect = CGRect(origin: CGPoint(x: originX, y: 0), size: markerSize)
            let symbolColor = contrastingColor(on: tint)

            switch key.style {
            case .balloon:
                let circle = CGRect(x: markerRect.minX + 1, y: 1, width: markerSize.width - 2, height: markerSize.width - 2)
                let path = UIBezierPath(ovalIn: circle)
                // The tail points at the exact coordinate.
                let tail = UIBezierPath()
                tail.move(to: CGPoint(x: circle.midX - 7, y: circle.maxY - 5))
                tail.addLine(to: CGPoint(x: circle.midX, y: markerRect.maxY - 1))
                tail.addLine(to: CGPoint(x: circle.midX + 7, y: circle.maxY - 5))
                tail.close()
                path.append(tail)
                cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.35).cgColor)
                tint.setFill()
                path.fill()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor.white.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 1.5
                path.stroke()
                drawSymbol(key.systemImage, size: symbolSize, color: symbolColor, in: circle)
            case .badge:
                let circle = markerRect.insetBy(dx: 1, dy: 1)
                tint.setFill()
                UIBezierPath(ovalIn: circle).fill()
                drawSymbol(key.systemImage, size: symbolSize, color: symbolColor, in: circle)
            case .rider:
                let circle = markerRect.insetBy(dx: 1.5, dy: 1.5)
                let path = UIBezierPath(ovalIn: circle)
                cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.4).cgColor)
                tint.setFill()
                path.fill()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor(Brand.asphalt).setStroke()
                path.lineWidth = 2.5
                path.stroke()
                drawSymbol(key.systemImage, size: symbolSize, color: UIColor(Brand.asphalt), in: circle)
            }

            if let labelText {
                let origin = CGPoint(x: (width - labelSize.width) / 2, y: markerSize.height + 1)
                let textColor: UIColor = key.dark ? .white : UIColor(Brand.asphalt)
                let halo: UIColor = key.dark ? UIColor(Brand.asphalt) : .white
                // A halo keeps the name readable over roads and water.
                (labelText as NSString).draw(at: origin, withAttributes: [
                    .font: font, .foregroundColor: textColor, .strokeColor: halo, .strokeWidth: 6,
                ])
                (labelText as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: textColor])
            }
        }

        let anchor: CGPoint = switch key.style {
        case .balloon: CGPoint(x: 0.5, y: markerSize.height / height)
        case .badge, .rider: CGPoint(x: 0.5, y: (markerSize.height / 2) / height)
        }
        return Rendered(image: image, anchor: anchor)
    }

    private static func drawSymbol(_ name: String, size: CGFloat, color: UIColor, in rect: CGRect) {
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .bold)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let origin = CGPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)
        symbol.draw(at: origin)
    }

    /// Asphalt on light fills (highway yellow), white on dark ones: the brand rule of no yellow-on-light text.
    private static func contrastingColor(on fill: UIColor) -> UIColor {
        var white: CGFloat = 0
        fill.resolvedColor(with: .current).getWhite(&white, alpha: nil)
        return white > 0.6 ? UIColor(Brand.asphalt) : .white
    }
}

// Draws Ride Tracker's own icons (spot categories) as single-colour vector PDFs for the asset
// catalog, plus a preview sheet:
//
//   swift design/make-icons.swift <Assets.xcassets/Icons folder> [preview.png]
//
// Style, so every icon feels like one family: a 24 pt grid, 2 pt round strokes, open shapes like
// road-sign pictograms, solid fills only for small accents. The PDFs are template images: the app
// tints them like SF Symbols.
import AppKit

typealias Draw = (CGContext) -> Void

let stroke: CGFloat = 2

func line(_ c: CGContext, _ points: [CGPoint]) {
    c.move(to: points[0]); points.dropFirst().forEach { c.addLine(to: $0) }; c.strokePath()
}
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// Coordinates are in a 24×24 box with y going down (flipped below), like SF Symbols' grid.
let icons: [(name: String, draw: Draw)] = [
    // MARK: Tab bar

    // Ride: the road ahead, edges converging, centre dashes shrinking into the distance.
    ("tab-ride", { c in
        line(c, [p(3, 21), p(9.5, 3)])
        line(c, [p(21, 21), p(14.5, 3)])
        line(c, [p(12, 17.5), p(12, 21)])
        line(c, [p(12, 10.5), p(12, 13)])
        line(c, [p(12, 5), p(12, 6.5)])
    }),
    // Spots: a pin standing on its patch of ground.
    ("tab-spots", { c in
        let center = p(12, 8.5), r: CGFloat = 5.5, tip = p(12, 19)
        let theta = asin(r / (tip.y - center.y))
        let pin = CGMutablePath()
        pin.move(to: tip)
        pin.addArc(center: center, radius: r, startAngle: .pi / 2 + (.pi / 2 - theta), endAngle: .pi / 2 - (.pi / 2 - theta), clockwise: false)
        pin.closeSubpath()
        c.addPath(pin); c.strokePath()
        c.addEllipse(in: CGRect(x: 10.25, y: 6.75, width: 3.5, height: 3.5)); c.fillPath()
        c.addEllipse(in: CGRect(x: 5, y: 19, width: 14, height: 3.5)); c.strokePath()
    }),
    // Rides: a winding route from a start dot to a flag.
    ("tab-rides", { c in
        c.addEllipse(in: CGRect(x: 2, y: 18, width: 4, height: 4)); c.fillPath()
        c.move(to: p(4, 20))
        c.addCurve(to: p(12, 13), control1: p(10, 21), control2: p(5, 13))
        c.addCurve(to: p(17, 7), control1: p(18, 13), control2: p(13, 8))
        c.strokePath()
        // A pennant: a chequered flag turns to mush at tab-bar size.
        line(c, [p(17, 10), p(17, 2.5)])
        line(c, [p(17, 2.5), p(22, 4.5), p(17, 6.5)])
    }),
    // Friends: two riding helmets, one a little behind the other. Only the visible part of the back
    // helmet is drawn (template PDFs can't erase), with a small gap where it passes behind.
    ("tab-friends", { c in
        let front = p(9.5, 13), frontR: CGFloat = 6.5
        func shell(_ center: CGPoint, _ r: CGFloat, bottom: CGFloat) {
            let path = CGMutablePath()
            path.move(to: p(center.x - r, bottom)); path.addLine(to: p(center.x - r, center.y))
            path.addArc(center: center, radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addLine(to: p(center.x + r, bottom)); path.closeSubpath()
            c.addPath(path); c.strokePath()
        }
        // Back helmet: sample its outline and keep what's clear of the front helmet.
        let back = p(16, 8.5), backR: CGFloat = 5
        var visible: [CGPoint] = []
        for i in 0...40 {
            let angle = CGFloat.pi + CGFloat.pi * CGFloat(i) / 40
            let point = p(back.x + backR * cos(angle), back.y + backR * sin(angle))
            if hypot(point.x - front.x, point.y - front.y) > frontR + 2.2 { visible.append(point) }
        }
        visible.append(p(back.x + backR, 14))
        if visible.count > 1 { line(c, visible) }
        line(c, [p(back.x + 1.2, back.y + 0.5), p(back.x + backR, back.y + 0.5)])
        // Front helmet, with its visor.
        shell(front, frontR, bottom: 21.5)
        line(c, [p(front.x - 1, front.y + 0.5), p(front.x + frontR, front.y + 0.5)])
    }),
    // Settings: three sliders, set differently.
    ("tab-settings", { c in
        for (y, knob) in [(5.0, 15.0), (12.0, 8.0), (19.0, 13.0)] as [(CGFloat, CGFloat)] {
            line(c, [p(3, y), p(knob - 2.5, y)])
            line(c, [p(knob + 2.5, y), p(21, y)])
            c.addEllipse(in: CGRect(x: knob - 2.5, y: y - 2.5, width: 5, height: 5)); c.strokePath()
        }
    }),

    // MARK: Spot categories

    // Viewpoint: two peaks and the sun over them.
    ("category-viewpoint", { c in
        line(c, [p(2, 20), p(9, 9), p(13, 15), p(16, 11), p(22, 20)])
        line(c, [p(2, 20), p(22, 20)])
        c.addEllipse(in: CGRect(x: 15, y: 2.5, width: 5, height: 5)); c.strokePath()
    }),
    // Food & chai: a cutting-chai glass (narrow at the base), chai line, two curls of steam.
    ("category-food", { c in
        line(c, [p(6, 9), p(8, 21), p(16, 21), p(18, 9), p(6, 9)])
        line(c, [p(7.2, 14), p(16.8, 14)])
        c.move(to: p(10, 6.5)); c.addCurve(to: p(10, 2.5), control1: p(8.5, 5.5), control2: p(11.5, 3.5)); c.strokePath()
        c.move(to: p(14, 6.5)); c.addCurve(to: p(14, 2.5), control1: p(12.5, 5.5), control2: p(15.5, 3.5)); c.strokePath()
    }),
    // Fuel: a pump with its display and the hose curling to the nozzle.
    ("category-fuel", { c in
        c.addPath(CGPath(roundedRect: CGRect(x: 4, y: 3, width: 10, height: 18), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)); c.strokePath()
        c.addRect(CGRect(x: 6.5, y: 6, width: 5, height: 4)); c.strokePath()
        line(c, [p(2.5, 21), p(15.5, 21)])
        c.move(to: p(14, 8)); c.addLine(to: p(18, 8)); c.addCurve(to: p(20, 11), control1: p(19.5, 8), control2: p(20, 9.5))
        c.addLine(to: p(20, 17)); c.addCurve(to: p(17.5, 17), control1: p(20, 18.5), control2: p(17.5, 18.5)); c.addLine(to: p(17.5, 13)); c.strokePath()
    }),
    // Temple / monument: a stepped gopuram on its base, with the kalasam on top.
    ("category-monument", { c in
        line(c, [p(3, 21), p(21, 21)])
        line(c, [p(5, 21), p(5, 17), p(7, 17), p(7, 13), p(9, 13), p(9, 9), p(11, 9), p(11, 6), p(13, 6), p(13, 9),
                 p(15, 9), p(15, 13), p(17, 13), p(17, 17), p(19, 17), p(19, 21)])
        c.addEllipse(in: CGRect(x: 10.8, y: 2, width: 2.4, height: 2.4)); c.fillPath()
        line(c, [p(10.5, 21), p(10.5, 18), p(13.5, 18), p(13.5, 21)])
    }),
    // Stay: a tent with its door open, pegged to the ground.
    ("category-stay", { c in
        line(c, [p(2, 20), p(12, 4), p(22, 20)])
        line(c, [p(2, 20), p(22, 20)])
        line(c, [p(12, 11), p(9, 20)])
        line(c, [p(12, 11), p(15, 20)])
    }),
    // Mechanic: an open-ended spanner, corner to corner.
    ("category-mechanic", { c in
        c.translateBy(x: 12, y: 12); c.rotate(by: -.pi / 4); c.translateBy(x: -12, y: -12)
        c.addPath(CGPath(roundedRect: CGRect(x: 10.25, y: 8, width: 3.5, height: 13), cornerWidth: 1.75, cornerHeight: 1.75, transform: nil)); c.strokePath()
        c.move(to: p(9.5, 8.5)); c.addArc(center: p(12, 5.5), radius: 4, startAngle: .pi * 0.75, endAngle: .pi * 0.25, clockwise: false)
        c.move(to: p(10.5, 1.8)); c.addLine(to: p(10.5, 5.5)); c.addLine(to: p(13.5, 5.5)); c.addLine(to: p(13.5, 1.8)); c.strokePath()
    }),
    // Lake / waterfall: water falling off a ledge into ripples.
    ("category-nature", { c in
        line(c, [p(3, 6), p(9, 6), p(9, 15)])
        line(c, [p(12, 6), p(12, 15)])
        line(c, [p(15, 6), p(15, 13)])
        for (y, x0, x1) in [(18.0, 4.0, 20.0), (21.5, 7.0, 17.0)] as [(CGFloat, CGFloat, CGFloat)] {
            c.move(to: p(x0, y))
            var x = x0
            while x < x1 { c.addQuadCurve(to: p(x + 4, y), control: p(x + 2, y - 2)); x += 4 }
            c.strokePath()
        }
    }),
    // Other: an outlined map pin, "a place". (A km-stone outline with a dot read as a padlock.)
    ("category-other", { c in
        let center = p(12, 9.5), r: CGFloat = 6.5, tip = p(12, 22)
        let theta = asin(r / (tip.y - center.y))
        let path = CGMutablePath()
        path.move(to: tip)
        path.addArc(center: center, radius: r, startAngle: .pi / 2 + (.pi / 2 - theta), endAngle: .pi / 2 - (.pi / 2 - theta), clockwise: false)
        path.closeSubpath()
        c.addPath(path); c.strokePath()
        c.addEllipse(in: CGRect(x: 9.75, y: 7.25, width: 4.5, height: 4.5)); c.strokePath()
    }),
]

func setUp(_ c: CGContext, scale: CGFloat, height: CGFloat) {
    // Flip to the top-left origin the drawings use.
    c.translateBy(x: 0, y: height); c.scaleBy(x: scale, y: -scale)
    c.setLineWidth(stroke); c.setLineCap(.round); c.setLineJoin(.round)
    c.setStrokeColor(.black); c.setFillColor(.black)
}

let args = CommandLine.arguments.dropFirst()
guard let folder = args.first else { print("usage: make-icons.swift <Icons folder> [preview.png]"); exit(1) }
let fm = FileManager.default
try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
try #"{"info":{"author":"xcode","version":1},"properties":{"provides-namespace":false}}"#
    .write(toFile: "\(folder)/Contents.json", atomically: true, encoding: .utf8)

for icon in icons {
    let set = "\(folder)/\(icon.name).imageset"
    try fm.createDirectory(atPath: set, withIntermediateDirectories: true)
    var box = CGRect(x: 0, y: 0, width: 24, height: 24)
    let data = NSMutableData()
    let pdf = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    pdf.beginPDFPage(nil)
    setUp(pdf, scale: 1, height: 24)
    icon.draw(pdf)
    pdf.endPDFPage(); pdf.closePDF()
    try data.write(toFile: "\(set)/\(icon.name).pdf")
    let contents = """
    {"images":[{"filename":"\(icon.name).pdf","idiom":"universal"}],"info":{"author":"xcode","version":1},\
    "properties":{"preserves-vector-representation":true,"template-rendering-intent":"template"}}
    """
    try contents.write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
}
print("wrote \(icons.count) icons to \(folder)")

// Preview: each icon at 4× on chalk, in a row, to review the family together.
if let preview = args.dropFirst().first {
    let cell: CGFloat = 120, scale: CGFloat = 4
    let width = Int(cell) * icons.count, height = Int(cell)
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.965, green: 0.953, blue: 0.918, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (i, icon) in icons.enumerated() {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(i) * cell + (cell - 24 * scale) / 2, y: (cell - 24 * scale) / 2)
        setUp(ctx, scale: scale, height: 24 * scale)
        ctx.setStrokeColor(CGColor(srgbRed: 0.106, green: 0.102, blue: 0.09, alpha: 1))
        ctx.setFillColor(CGColor(srgbRed: 0.106, green: 0.102, blue: 0.09, alpha: 1))
        icon.draw(ctx)
        ctx.restoreGState()
    }
    try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
    print("wrote \(preview)")
}

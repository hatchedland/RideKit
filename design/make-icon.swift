// Renders the "Milestone" app icon: swift design/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let yellow = rgb(0xF5C400), asphalt = rgb(0x1B1A17), chalk = rgb(0xF6F3EA), road = rgb(0x2A2925)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Background: asphalt.
ctx.setFillColor(asphalt); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// The road the stone stands beside: a band across the bottom with a dashed yellow centre line.
ctx.setFillColor(road); ctx.fill(CGRect(x: 0, y: 0, width: size, height: 250))
ctx.setFillColor(yellow)
for i in stride(from: -40.0, to: Double(size), by: 190) {
    ctx.fill(CGRect(x: i, y: 112, width: 110, height: 26))
}

// The milestone: slab with a half-round top, yellow cap, chalk body.
let w: CGFloat = 470, h: CGFloat = 640
let rect = CGRect(x: (size - w) / 2, y: 190, width: w, height: h)
let r = w / 2
let stone = CGMutablePath()
stone.move(to: CGPoint(x: rect.minX, y: rect.minY))
stone.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
stone.addArc(center: CGPoint(x: rect.midX, y: rect.maxY - r), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
stone.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
stone.closeSubpath()

ctx.saveGState()
ctx.addPath(stone); ctx.clip()
ctx.setFillColor(chalk); ctx.fill(rect)
let capHeight: CGFloat = r + 70
ctx.setFillColor(yellow); ctx.fill(CGRect(x: rect.minX, y: rect.maxY - capHeight, width: w, height: capHeight))
ctx.restoreGState()

// Engraving on the body: a map pin, because spots are the point of every ride.
let bodyTop = rect.maxY - capHeight
let pinR: CGFloat = 80
let pinCenter = CGPoint(x: rect.midX, y: bodyTop - 50 - pinR)
let tip = CGPoint(x: rect.midX, y: pinCenter.y - pinR * 2.35)
let pin = CGMutablePath()
let theta = asin(pinR / (pinCenter.y - tip.y))
pin.move(to: tip)
pin.addArc(center: pinCenter, radius: pinR, startAngle: -.pi / 2 - (.pi / 2 - theta), endAngle: -.pi / 2 + (.pi / 2 - theta) + 2 * .pi, clockwise: false)
pin.closeSubpath()
ctx.setFillColor(asphalt); ctx.addPath(pin); ctx.fillPath()
let hole: CGFloat = 60
ctx.setFillColor(yellow); ctx.fillEllipse(in: CGRect(x: pinCenter.x - hole / 2, y: pinCenter.y - hole / 2, width: hole, height: hole))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

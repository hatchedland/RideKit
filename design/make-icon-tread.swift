// Renders the "tread to pin" app icon in 3D: a two-wheeler's tread mark (raised, glossy chevrons on a
// darker rubber band) curves up an asphalt road and ends at a map pin, where the ride stopped.
// Ride → stop → place, the app's story in one mark (chosen 2026-11-17, replacing the km-stone).
//
//   swift design/make-icon-tread.swift [output.png] [size] [yellow|saffron]   (needs Xcode: SceneKit + Metal)
//
// Procedural like make-icon-3d.swift: no image files, the road grain is Core Image noise.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SceneKit

let args = Array(CommandLine.arguments.dropFirst())
let out = args.first ?? "AppIcon-Tread.png"
let size = args.count > 1 ? Int(args[1]) ?? 1024 : 1024
let palette = args.count > 2 ? args[2] : "yellow"

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let paint = palette == "saffron" ? color(0xFF7A1A) : color(0xF5C400)
let asphalt = color(0x1B1A17)

// MARK: Textures

let ci = CIContext()

func noise(seed: CGFloat, scale: CGFloat, contrast: Float) -> CGImage {
    let random = CIFilter.randomGenerator().outputImage!
        .transformed(by: CGAffineTransform(translationX: seed * 137, y: seed * 71))
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = random.clampedToExtent()
    blur.radius = Float(scale) * 0.6
    let mono = CIFilter.colorControls()
    mono.inputImage = blur.outputImage
    mono.saturation = 0
    mono.contrast = contrast
    return ci.createCGImage(mono.outputImage!, from: CGRect(x: 0, y: 0, width: 1024, height: 1024))!
}

func tinted(_ image: CGImage, low: NSColor, high: NSColor) -> CGImage {
    let map = CIFilter.falseColor()
    map.inputImage = CIImage(cgImage: image)
    map.color0 = CIColor(color: low)!
    map.color1 = CIColor(color: high)!
    return ci.createCGImage(map.outputImage!, from: CIImage(cgImage: image).extent)!
}

let roadGrain = noise(seed: 4, scale: 1.1, contrast: 1.8)
let rubberGrain = noise(seed: 11, scale: 0.8, contrast: 1.4)

func material(diffuse: Any, roughness: CGFloat, normal: CGImage? = nil, normalIntensity: CGFloat = 1,
              repeatBy: CGFloat = 1) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = diffuse
    m.roughness.contents = roughness
    m.metalness.contents = 0
    if let normal {
        m.normal.contents = normal
        m.normal.intensity = normalIntensity
    }
    for property in [m.diffuse, m.normal] {
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.contentsTransform = SCNMatrix4MakeScale(repeatBy, repeatBy, 1)
    }
    return m
}

let roadMat = material(diffuse: tinted(roadGrain, low: color(0x0D0D0C), high: color(0x24231F)), roughness: 0.95,
                       normal: roadGrain, normalIntensity: 0.8, repeatBy: 5)
// The tyre's mark: darker, slightly glossy rubber laid on the road.
let rubberMat = material(diffuse: tinted(rubberGrain, low: color(0x020202), high: color(0x080808)), roughness: 1.0,
                         normal: rubberGrain, normalIntensity: 0.6, repeatBy: 2)
// Chevrons and pin: enamel road paint, like the old stone's cap.
let paintMat = material(diffuse: paint, roughness: 0.38)
let holeMat = material(diffuse: asphalt, roughness: 0.8)

// MARK: Geometry

let scene = SCNScene()
scene.background.contents = asphalt

let road = SCNNode(geometry: SCNPlane(width: 60, height: 60))
road.geometry?.materials = [roadMat]
road.eulerAngles.x = -.pi / 2
scene.rootNode.addChildNode(road)

/// The track's centre line: a gentle S from the bottom left corner up to the pin.
struct Curve {
    let p0 = SIMD2<Double>(-4.6, 7.8), p1 = SIMD2<Double>(3.6, 5.2), p2 = SIMD2<Double>(-3.4, 0.6), p3 = SIMD2<Double>(0.9, -1.6)
    func point(_ t: Double) -> SIMD2<Double> {
        let u = 1 - t
        return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
    }
    func tangent(_ t: Double) -> SIMD2<Double> {
        let u = 1 - t
        let d = 3 * u * u * (p1 - p0) + 6 * u * t * (p2 - p1) + 3 * t * t * (p3 - p2)
        return d / (d.x * d.x + d.y * d.y).squareRoot()
    }
}
let curve = Curve()

// Walk the curve in equal steps so the chevrons are evenly spaced.
var samples: [(point: SIMD2<Double>, tangent: SIMD2<Double>)] = []
let spacing = 0.78, trackWidth = 2.0
var travelled = 0.0, last = curve.point(0)
for i in 0...4000 {
    let t = Double(i) / 4000
    let p = curve.point(t)
    travelled += ((p - last).x * (p - last).x + (p - last).y * (p - last).y).squareRoot()
    last = p
    if travelled >= spacing || i == 0 {
        travelled = 0
        samples.append((p, curve.tangent(t)))
    }
}
// Stop short of the pin so the track runs into its foot.
samples.removeLast(2)

for (index, sample) in samples.enumerated() {
    let heading = atan2(sample.tangent.x, sample.tangent.y)   // angle in the road plane
    let group = SCNNode()
    group.position = SCNVector3(sample.point.x, 0, sample.point.y)
    group.eulerAngles.y = CGFloat(heading)

    // Rubber band under the chevrons, overlapping its neighbours so it reads as one mark.
    let band = SCNNode(geometry: SCNBox(width: trackWidth, height: 0.012, length: spacing + 0.08, chamferRadius: 0.005))
    band.geometry?.materials = [rubberMat]
    band.position.y = 0.006
    group.addChildNode(band)

    // A chevron points the way the bike went (towards the pin): two raised bars meeting at an apex.
    // The mark fades in from the corner: the newest tread is crisp, the oldest just starting.
    let fade = min(1, 0.35 + Double(index) / Double(max(1, samples.count - 1)) * 1.3)
    for side in [-1.0, 1.0] {
        let bar = SCNNode(geometry: SCNBox(width: 1.0, height: 0.1 * fade + 0.03, length: 0.26, chamferRadius: 0.06))
        bar.geometry?.materials = [paintMat]
        bar.eulerAngles.y = CGFloat(side * 0.62)
        bar.position = SCNVector3(side * 0.38, 0.05, -0.2)
        bar.opacity = CGFloat(fade)
        group.addChildNode(bar)
    }
    scene.rootNode.addChildNode(group)
}

// The pin where the ride stopped: a classic map pin standing on the road, hole cut through.
let pinRadius: CGFloat = 1.7
let pinPath = NSBezierPath()
let centre = NSPoint(x: 0, y: pinRadius * 2.45)
let tip = NSPoint(x: 0, y: 0)
let theta = asin(pinRadius / (centre.y - tip.y)) * 180 / .pi
pinPath.move(to: tip)
pinPath.appendArc(withCenter: centre, radius: pinRadius, startAngle: -90 - (90 - theta), endAngle: -90 + (90 - theta), clockwise: true)
pinPath.close()
pinPath.append(NSBezierPath(ovalIn: NSRect(x: -pinRadius * 0.42, y: centre.y - pinRadius * 0.42,
                                           width: pinRadius * 0.84, height: pinRadius * 0.84)).reversed)
pinPath.flatness = 0.005
let pinShape = SCNShape(path: pinPath, extrusionDepth: 0.8)
pinShape.chamferRadius = 0.14
pinShape.chamferMode = .both
pinShape.materials = [paintMat]
let pin = SCNNode(geometry: pinShape)
let end = curve.point(1)
pin.position = SCNVector3(end.x, 0, end.y)
pin.eulerAngles.y = -0.18
scene.rootNode.addChildNode(pin)

// A dark disc where the pin meets the road, so it sits on the tarmac instead of floating.
let foot = SCNNode(geometry: SCNCylinder(radius: 0.45, height: 0.01))
foot.geometry?.materials = [holeMat]
foot.position = SCNVector3(end.x, 0.004, end.y)
scene.rootNode.addChildNode(foot)

// MARK: Light and camera

func light(_ type: SCNLight.LightType, intensity: CGFloat, temperature: CGFloat, shadows: Bool = false) -> SCNLight {
    let l = SCNLight()
    l.type = type
    l.intensity = intensity
    l.temperature = temperature
    if shadows {
        l.castsShadow = true
        l.shadowMode = .deferred
        l.shadowSampleCount = 16
        l.shadowRadius = 5
        l.shadowColor = NSColor.black.withAlphaComponent(0.7)
    }
    return l
}

// Warm low sun from behind the pin on the left (long shadow towards the viewer), cool rim, soft fill.
let key = SCNNode()
key.light = light(.directional, intensity: 2000, temperature: 5200, shadows: true)
key.eulerAngles = SCNVector3(-0.95, -2.5, 0)
scene.rootNode.addChildNode(key)

let front = SCNNode()
front.light = light(.directional, intensity: 2600, temperature: 5600)
front.eulerAngles = SCNVector3(-0.45, 0.25, 0)
scene.rootNode.addChildNode(front)

let fill = SCNNode()
fill.light = light(.ambient, intensity: 240, temperature: 5500)
scene.rootNode.addChildNode(fill)

let camera = SCNCamera()
camera.fieldOfView = 38
camera.wantsHDR = true
camera.wantsExposureAdaptation = false
camera.bloomIntensity = 0.12
camera.vignettingIntensity = 0.35
camera.vignettingPower = 1.1
camera.screenSpaceAmbientOcclusionIntensity = 1.0
let cameraNode = SCNNode()
cameraNode.camera = camera
cameraNode.position = SCNVector3(0.0, 14.5, 13.5)
cameraNode.look(at: SCNVector3(0.5, 2.3, 1.2))
scene.rootNode.addChildNode(cameraNode)

// MARK: Render

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal isn't available") }
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
renderer.autoenablesDefaultLighting = false
let image = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)

// App icons have no transparency: flatten onto asphalt.
var rect = CGRect(x: 0, y: 0, width: size, height: size)
guard let rendered = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
      let flat = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("Couldn't flatten the render") }
flat.setFillColor(asphalt.cgColor)
flat.fill(rect)
flat.draw(rendered, in: rect)
let rep = NSBitmapImageRep(cgImage: flat.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(size)×\(size))")

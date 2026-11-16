// Renders the "Milestone" logo in 3D: a weathered km-stone with a glossy highway-yellow cap and a
// map pin carved into it, standing beside an asphalt road with a dashed yellow centre line.
//
//   swift design/make-icon-3d.swift [output.png] [size]      (needs Xcode: SceneKit + Metal)
//
// Everything is procedural (no image files): stone grain and bump come from Core Image noise, so the
// render is reproducible and tweakable here. Same palette as Shared/Brand.swift.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SceneKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-3D.png"
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let yellow = color(0xF5C400), asphalt = color(0x1B1A17), chalk = color(0xF6F3EA)

// MARK: Procedural textures

let ci = CIContext()

/// Grey noise: `scale` sets the grain size, `contrast` how rough it looks.
func noise(seed: CGFloat, scale: CGFloat, contrast: Float, brightness: Float = 0, side: Int = 1024) -> CGImage {
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
    mono.brightness = brightness
    return ci.createCGImage(mono.outputImage!, from: CGRect(x: 0, y: 0, width: side, height: side))!
}

/// Tints a grey texture: dark parts go to `low`, light parts to `high`.
func tinted(_ image: CGImage, low: NSColor, high: NSColor) -> CGImage {
    let map = CIFilter.falseColor()
    map.inputImage = CIImage(cgImage: image)
    map.color0 = CIColor(color: low)!
    map.color1 = CIColor(color: high)!
    return ci.createCGImage(map.outputImage!, from: CIImage(cgImage: image).extent)!
}

/// Fine grain over coarse weathering, the way old painted stone looks.
func stoneDetail(seed: CGFloat) -> CGImage {
    let coarse = CIImage(cgImage: noise(seed: seed, scale: 18, contrast: 1.6))
    let fine = CIImage(cgImage: noise(seed: seed + 9, scale: 1.4, contrast: 2.2))
    let mix = CIFilter.multiplyBlendMode()
    mix.inputImage = fine
    mix.backgroundImage = coarse
    return ci.createCGImage(mix.outputImage!, from: CGRect(x: 0, y: 0, width: 1024, height: 1024))!
}

let stoneGrain = stoneDetail(seed: 1)
let roadGrain = noise(seed: 4, scale: 1.1, contrast: 1.8)

// MARK: Materials

func material(diffuse: Any, roughness: CGFloat, metalness: CGFloat = 0, normal: CGImage? = nil, normalIntensity: CGFloat = 1) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = diffuse
    m.roughness.contents = roughness
    m.metalness.contents = metalness
    if let normal {
        m.normal.contents = normal
        m.normal.intensity = normalIntensity
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
    }
    m.diffuse.wrapS = .repeat
    m.diffuse.wrapT = .repeat
    return m
}

// Chalk body: off-white with grey speckle and a little bump, so it reads as stone, not plastic.
let chalkMat = material(diffuse: tinted(stoneGrain, low: color(0xD8D2C4), high: chalk), roughness: 0.9,
                        normal: stoneGrain, normalIntensity: 0.35)
// Yellow cap: enamel road paint, smooth with a soft sheen. (A noise texture here reads as rust.)
let capMat = material(diffuse: yellow, roughness: 0.42)
// The carving: dark, matte, slightly rough.
let carveMat = material(diffuse: asphalt, roughness: 0.85)
let carveHoleMat = material(diffuse: yellow, roughness: 0.4)
let roadMat = material(diffuse: tinted(roadGrain, low: color(0x141311), high: color(0x34322D)), roughness: 0.95,
                       normal: roadGrain, normalIntensity: 0.8)
roadMat.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 4, 1)
roadMat.normal.contentsTransform = SCNMatrix4MakeScale(4, 4, 1)
let paintMat = material(diffuse: yellow, roughness: 0.5)
let groundMat = material(diffuse: color(0x0E0D0B), roughness: 1)

// MARK: Geometry

let scene = SCNScene()
scene.background.contents = asphalt

let stoneWidth: CGFloat = 4.4, stoneHeight: CGFloat = 7.2, depth: CGFloat = 1.5
let radius = stoneWidth / 2
let capHeight = radius + 0.7

/// The stone's outline (slab with a half-round top), cut between two heights.
func stonePath(from bottom: CGFloat, to top: CGFloat) -> NSBezierPath {
    // The outline as a polygon with a finely sampled arch (a flattened Bézier gives a faceted roof).
    let band = NSRect(x: -radius - 1, y: bottom, width: stoneWidth + 2, height: top - bottom)
    let clipped = NSBezierPath()
    var points = [NSPoint(x: radius, y: 0), NSPoint(x: -radius, y: 0), NSPoint(x: -radius, y: stoneHeight - radius)]
    let steps = 96
    for i in 1..<steps {
        let angle = CGFloat.pi - CGFloat.pi * CGFloat(i) / CGFloat(steps)
        points.append(NSPoint(x: radius * cos(angle), y: stoneHeight - radius + radius * sin(angle)))
    }
    points.append(NSPoint(x: radius, y: stoneHeight - radius))
    // Sutherland–Hodgman against the band's bottom and top edges.
    func clip(_ poly: [NSPoint], keep: (NSPoint) -> Bool, cross: (NSPoint, NSPoint) -> NSPoint) -> [NSPoint] {
        var result: [NSPoint] = []
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            if keep(b) {
                if !keep(a) { result.append(cross(a, b)) }
                result.append(b)
            } else if keep(a) {
                result.append(cross(a, b))
            }
        }
        return result
    }
    func atY(_ y: CGFloat) -> (NSPoint, NSPoint) -> NSPoint {
        { a, b in NSPoint(x: a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y), y: y) }
    }
    var poly = clip(points, keep: { $0.y >= band.minY }, cross: atY(band.minY))
    poly = clip(poly, keep: { $0.y <= band.maxY }, cross: atY(band.maxY))
    guard let first = poly.first else { return clipped }
    clipped.move(to: first)
    poly.dropFirst().forEach { clipped.line(to: $0) }
    clipped.close()
    return clipped
}

func extruded(_ path: NSBezierPath, depth: CGFloat, chamfer: CGFloat, materials: [SCNMaterial]) -> SCNNode {
    path.flatness = 0.01
    let shape = SCNShape(path: path, extrusionDepth: depth)
    shape.chamferRadius = chamfer
    shape.chamferMode = .front
    shape.materials = materials
    return SCNNode(geometry: shape)
}

let stone = SCNNode()
let seam = stoneHeight - capHeight
// Body and cap are separate pieces so each gets its own material; the tiny overlap hides the joint.
stone.addChildNode(extruded(stonePath(from: 0, to: seam + 0.01), depth: depth, chamfer: 0.12, materials: [chalkMat, chalkMat, chalkMat]))
stone.addChildNode(extruded(stonePath(from: seam, to: stoneHeight), depth: depth, chamfer: 0.12, materials: [capMat, capMat, capMat]))

// The carved pin on the body's face: dark inset with a yellow hole, as on the 2D icon.
let pinRadius: CGFloat = 0.62
let pinCenter = NSPoint(x: 0, y: seam - 0.45 - pinRadius)
let tip = NSPoint(x: 0, y: pinCenter.y - pinRadius * 2.35)
let theta = asin(pinRadius / (pinCenter.y - tip.y)) * 180 / .pi
let pinPath = NSBezierPath()
pinPath.move(to: tip)
pinPath.appendArc(withCenter: pinCenter, radius: pinRadius, startAngle: -90 - (90 - theta), endAngle: -90 + (90 - theta), clockwise: true)
pinPath.close()
let pin = extruded(pinPath, depth: 0.06, chamfer: 0.02, materials: [carveMat, carveMat, carveMat])
pin.position = SCNVector3(0, 0, depth / 2 + 0.005)
stone.addChildNode(pin)
let hole = SCNNode(geometry: SCNCylinder(radius: pinRadius * 0.38, height: 0.07))
hole.geometry?.materials = [carveHoleMat]
hole.eulerAngles.x = .pi / 2
hole.position = SCNVector3(pinCenter.x, pinCenter.y, depth / 2 + 0.03)
stone.addChildNode(hole)

stone.eulerAngles.y = -0.38
stone.position = SCNVector3(-0.6, 0, 0)
scene.rootNode.addChildNode(stone)

// Ground and road: the stone stands on the verge; the road runs past it towards the viewer.
let ground = SCNNode(geometry: SCNPlane(width: 60, height: 60))
ground.geometry?.materials = [groundMat]
ground.eulerAngles.x = -.pi / 2
scene.rootNode.addChildNode(ground)

let roadNode = SCNNode()
let roadPlane = SCNNode(geometry: SCNPlane(width: 7, height: 40))
roadPlane.geometry?.materials = [roadMat]
roadPlane.eulerAngles.x = -.pi / 2
roadPlane.position = SCNVector3(0, 0.005, 0)
roadNode.addChildNode(roadPlane)
for i in -6...6 {
    let dash = SCNNode(geometry: SCNBox(width: 0.32, height: 0.02, length: 1.4, chamferRadius: 0.02))
    dash.geometry?.materials = [paintMat]
    dash.position = SCNVector3(0, 0.015, Float(i) * 2.6)
    roadNode.addChildNode(dash)
}
roadNode.eulerAngles.y = -0.5
roadNode.position = SCNVector3(4.2, 0, -1.0)
scene.rootNode.addChildNode(roadNode)

// MARK: Light and camera

func light(_ type: SCNLight.LightType, intensity: CGFloat, temperature: CGFloat = 6500, shadows: Bool = false) -> SCNLight {
    let l = SCNLight()
    l.type = type
    l.intensity = intensity
    l.temperature = temperature
    if shadows {
        l.castsShadow = true
        l.shadowMode = .deferred
        l.shadowSampleCount = 16
        l.shadowRadius = 6
        l.shadowColor = NSColor.black.withAlphaComponent(0.65)
    }
    return l
}

// Warm late-afternoon key from the front left, cool rim from behind, soft fill.
let key = SCNNode()
key.light = light(.directional, intensity: 2400, temperature: 4600, shadows: true)
key.eulerAngles = SCNVector3(-0.75, -0.6, 0)
scene.rootNode.addChildNode(key)

let rim = SCNNode()
rim.light = light(.directional, intensity: 1400, temperature: 8000)
rim.eulerAngles = SCNVector3(-0.35, 2.5, 0)
scene.rootNode.addChildNode(rim)

let fill = SCNNode()
fill.light = light(.ambient, intensity: 260, temperature: 5500)
scene.rootNode.addChildNode(fill)

let camera = SCNCamera()
camera.fieldOfView = 34
camera.wantsHDR = true
camera.wantsExposureAdaptation = false
camera.bloomIntensity = 0.15
camera.vignettingIntensity = 0.55
camera.vignettingPower = 1.2
camera.screenSpaceAmbientOcclusionIntensity = 1.2
let cameraNode = SCNNode()
cameraNode.camera = camera
// Close enough that the stone fills most of the icon: at 60 pt on a home screen, a small stone gets lost.
cameraNode.position = SCNVector3(1.8, 4.8, 16.2)
cameraNode.look(at: SCNVector3(0.3, 3.3, 0))
scene.rootNode.addChildNode(cameraNode)

// MARK: Render

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal isn't available") }
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
renderer.autoenablesDefaultLighting = false
let image = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)

// App icons have no transparency: flatten onto asphalt with Core Graphics (AppKit won't draw into
// an alpha-less bitmap).
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

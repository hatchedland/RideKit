// Renders the blank 3D km-stone the Rides list writes each ride's distance on: weathered chalk stone,
// glossy highway-yellow enamel cap, soft contact shadow, transparent background.
//
//   swift design/make-stone-3d.swift <output.png>     (needs Xcode: SceneKit + Metal)
//
// Prints where the front face's cap and body land in the image (0–1), which `DistanceStone` uses to
// place the text. Same materials and light as design/make-icon-3d.swift.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SceneKit

let out = CommandLine.arguments.dropFirst().first ?? "DistanceStone.png"
let width = 420, height = 540

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let yellow = color(0xF5C400), chalk = color(0xF6F3EA)

// Stone grain: fine speckle over coarse weathering (Core Image noise, no image files).
let ci = CIContext()
func noise(seed: CGFloat, scale: CGFloat, contrast: Float) -> CIImage {
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
    return mono.outputImage!
}
let grainImage: CGImage = {
    let mix = CIFilter.multiplyBlendMode()
    mix.inputImage = noise(seed: 9, scale: 1.3, contrast: 2.0)
    mix.backgroundImage = noise(seed: 1, scale: 26, contrast: 0.5)
    return ci.createCGImage(mix.outputImage!, from: CGRect(x: 0, y: 0, width: 512, height: 512))!
}()
let tintedGrain: CGImage = {
    let map = CIFilter.falseColor()
    map.inputImage = CIImage(cgImage: grainImage)
    map.color0 = CIColor(color: color(0xCFC5B0))!
    map.color1 = CIColor(color: color(0xEFEADD))!
    return ci.createCGImage(map.outputImage!, from: CGRect(x: 0, y: 0, width: 512, height: 512))!
}()

func material(_ diffuse: Any, roughness: CGFloat, normal: CGImage? = nil, intensity: CGFloat = 1) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = diffuse
    m.roughness.contents = roughness
    m.metalness.contents = 0.0
    if let normal { m.normal.contents = normal; m.normal.intensity = intensity }
    return m
}
let stoneMat = material(tintedGrain, roughness: 0.95, normal: grainImage, intensity: 0.7)
let capMat = material(yellow, roughness: 0.38)

// The km-stone outline (slab with a half-round top), extruded, with bevelled front edges.
let stoneWidth: CGFloat = 4.4, stoneHeight: CGFloat = 5.6, depth: CGFloat = 1.6
let radius = stoneWidth / 2
let capHeight = stoneHeight * 0.42

func outline(from bottom: CGFloat, to top: CGFloat) -> NSBezierPath {
    var points = [NSPoint(x: radius, y: 0), NSPoint(x: -radius, y: 0), NSPoint(x: -radius, y: stoneHeight - radius)]
    for i in 1..<96 {
        let a = CGFloat.pi - CGFloat.pi * CGFloat(i) / 96
        points.append(NSPoint(x: radius * cos(a), y: stoneHeight - radius + radius * sin(a)))
    }
    points.append(NSPoint(x: radius, y: stoneHeight - radius))
    func clip(_ poly: [NSPoint], keep: (NSPoint) -> Bool, y: CGFloat) -> [NSPoint] {
        var result: [NSPoint] = []
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let cross = { NSPoint(x: a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y), y: y) }
            if keep(b) { if !keep(a) { result.append(cross()) }; result.append(b) } else if keep(a) { result.append(cross()) }
        }
        return result
    }
    var poly = clip(points, keep: { $0.y >= bottom }, y: bottom)
    poly = clip(poly, keep: { $0.y <= top }, y: top)
    let path = NSBezierPath()
    path.move(to: poly[0]); poly.dropFirst().forEach { path.line(to: $0) }; path.close()
    return path
}

func extruded(_ path: NSBezierPath, _ mat: SCNMaterial) -> SCNNode {
    let shape = SCNShape(path: path, extrusionDepth: depth)
    shape.chamferRadius = 0.1
    shape.chamferMode = .both
    shape.materials = [mat, mat, mat]
    return SCNNode(geometry: shape)
}

let scene = SCNScene()
let stone = SCNNode()
let seam = stoneHeight - capHeight
stone.addChildNode(extruded(outline(from: 0, to: seam + 0.01), stoneMat))
stone.addChildNode(extruded(outline(from: seam, to: stoneHeight), capMat))
let yaw: CGFloat = -0.42
stone.eulerAngles.y = yaw
scene.rootNode.addChildNode(stone)

// An invisible floor that only catches the stone's shadow.
let floor = SCNNode(geometry: SCNPlane(width: 30, height: 30))
let shadowCatcher = SCNMaterial()
shadowCatcher.lightingModel = .shadowOnly
floor.geometry?.materials = [shadowCatcher]
floor.eulerAngles.x = -.pi / 2
scene.rootNode.addChildNode(floor)

func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ temperature: CGFloat, shadows: Bool = false) -> SCNLight {
    let l = SCNLight()
    l.type = type; l.intensity = intensity; l.temperature = temperature
    if shadows {
        l.castsShadow = true; l.shadowMode = .deferred; l.shadowSampleCount = 16; l.shadowRadius = 8
        l.shadowColor = NSColor.black.withAlphaComponent(0.55)
    }
    return l
}
let key = SCNNode(); key.light = light(.directional, 1100, 6000, shadows: true)
key.eulerAngles = SCNVector3(-0.75, -0.95, 0); scene.rootNode.addChildNode(key)
let rim = SCNNode(); rim.light = light(.directional, 700, 7500)
rim.eulerAngles = SCNVector3(-0.3, 2.4, 0); scene.rootNode.addChildNode(rim)
let fill = SCNNode(); fill.light = light(.ambient, 220, 6000); scene.rootNode.addChildNode(fill)

let camera = SCNCamera()
camera.fieldOfView = 26
camera.wantsHDR = true
camera.wantsExposureAdaptation = false
let cameraNode = SCNNode()
cameraNode.camera = camera
// Framed on the stone as turned: its middle sits right of the origin after the yaw.
cameraNode.position = SCNVector3(-0.2, 3.4, 17.5)
cameraNode.look(at: SCNVector3(0.55, 2.7, 0))
scene.rootNode.addChildNode(cameraNode)

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal isn't available") }
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
renderer.autoenablesDefaultLighting = false
scene.background.contents = NSColor.clear
let image = renderer.snapshot(atTime: 0, with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
var rect = CGRect(x: 0, y: 0, width: width, height: height)
let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

// Where the front face is in the image, for placing text: project its corners.
func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    let local = SCNVector3(x, y, depth / 2)
    let world = stone.convertPosition(local, to: nil)
    let p = renderer.projectPoint(world)
    return CGPoint(x: p.x / CGFloat(width), y: 1 - p.y / CGFloat(height))
}
let topLeft = project(-radius, stoneHeight), bottomRight = project(radius, 0)
let seamLeft = project(-radius, seam), seamRight = project(radius, seam)
print("wrote \(out) (\(width)×\(height))")
print(String(format: "front face x %.3f…%.3f, top %.3f, seam %.3f…%.3f, bottom %.3f, yaw %.2f rad",
             topLeft.x, bottomRight.x, topLeft.y, seamLeft.y, seamRight.y, bottomRight.y, yaw))

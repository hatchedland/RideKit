// Renders the riding screen's 3D weather illustrations: a glossy sun, a puffy moon, soft clouds,
// glossy rain drops, a highway-yellow lightning bolt, curled wind ribbons. Transparent background,
// same light as design/make-stone-3d.swift, so they sit with the km-stone and the app icon.
//
//   swift design/make-weather-3d.swift [asset-catalog-dir] [pixels]     (needs Xcode: SceneKit + Metal)
//
// Writes one imageset per sky into <dir>/Weather (default ios/RideTracker/Resources/Assets.xcassets),
// rendered at 3x for a 120 pt image. Everything is procedural, so it's reproducible and tweakable here.
import AppKit
import SceneKit

let catalog = CommandLine.arguments.dropFirst().first ?? "ios/RideTracker/Resources/Assets.xcassets"
let side = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 360 : 360

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func material(_ hex: UInt32, roughness: CGFloat, glow: UInt32? = nil, glowIntensity: CGFloat = 0.35) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = color(hex)
    m.roughness.contents = roughness
    m.metalness.contents = 0.0
    if let glow {
        m.emission.contents = color(glow)
        m.emission.intensity = glowIntensity
    }
    return m
}

func node(_ geometry: SCNGeometry, _ mat: SCNMaterial, at p: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
    geometry.materials = [mat]
    let n = SCNNode(geometry: geometry)
    n.position = p
    return n
}

func extruded(_ path: NSBezierPath, depth: CGFloat, chamfer: CGFloat, _ mat: SCNMaterial) -> SCNNode {
    path.flatness = 0.002   // smooth curves; SceneKit tessellates the path at this tolerance
    let shape = SCNShape(path: path, extrusionDepth: depth)
    shape.chamferRadius = chamfer
    shape.chamferMode = .both
    shape.materials = [mat, mat, mat]
    return SCNNode(geometry: shape)
}

// MARK: Pieces

/// Glossy sun with rounded rays.
func sun(_ body: UInt32, glow: UInt32, radius: CGFloat = 1.0) -> SCNNode {
    let n = SCNNode()
    let mat = material(body, roughness: 0.28, glow: glow, glowIntensity: 0.45)
    n.addChildNode(node(SCNSphere(radius: radius), mat))
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        let ray = node(SCNCapsule(capRadius: radius * 0.11, height: radius * 0.5), mat,
                       at: SCNVector3(cos(a) * radius * 1.5, sin(a) * radius * 1.5, 0))
        ray.eulerAngles = SCNVector3(0, 0, a - .pi / 2)
        n.addChildNode(ray)
    }
    return n
}

/// A puffy cloud: overlapping spheres on a rounded base.
func cloud(_ hex: UInt32, roughness: CGFloat = 0.85) -> SCNNode {
    let n = SCNNode()
    let mat = material(hex, roughness: roughness)
    n.addChildNode(node(SCNBox(width: 2.7, height: 0.9, length: 1.1, chamferRadius: 0.45), mat, at: SCNVector3(0, -0.25, 0)))
    for (x, y, r) in [(-0.95, 0.0, 0.62), (-0.25, 0.35, 0.85), (0.6, 0.18, 0.72), (1.15, -0.1, 0.5)] as [(CGFloat, CGFloat, CGFloat)] {
        n.addChildNode(node(SCNSphere(radius: r), mat, at: SCNVector3(x, y, 0)))
    }
    return n
}

/// Glossy elongated drops, slanted like falling rain.
func drops(_ count: Int, below y: CGFloat) -> SCNNode {
    let n = SCNNode()
    let mat = material(0x5AAEFF, roughness: 0.12, glow: 0x1F6FD6, glowIntensity: 0.15)
    let xs: [CGFloat] = [-0.9, -0.2, 0.5, 1.1, -0.55, 0.15, 0.85]
    let ys: [CGFloat] = [0, -0.25, -0.05, -0.3, -0.75, -0.95, -0.7]
    for i in 0..<min(count, xs.count) {
        let drop = node(SCNSphere(radius: 0.15), mat, at: SCNVector3(xs[i], y + ys[i], 0.2))
        drop.scale = SCNVector3(0.85, 1.6, 0.85)
        drop.eulerAngles = SCNVector3(0, 0, 0.28)
        n.addChildNode(drop)
    }
    return n
}

func bolt() -> SCNNode {
    let p = NSBezierPath()
    let pts: [NSPoint] = [NSPoint(x: 0.15, y: 0.75), NSPoint(x: -0.45, y: -0.15), NSPoint(x: -0.02, y: -0.15),
                          NSPoint(x: -0.25, y: -0.95), NSPoint(x: 0.5, y: 0.1), NSPoint(x: 0.07, y: 0.1), NSPoint(x: 0.35, y: 0.75)]
    p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }; p.close()
    let n = extruded(p, depth: 0.22, chamfer: 0.05, material(0xF5C400, roughness: 0.3, glow: 0xF5A800, glowIntensity: 0.5))
    return n
}

/// Crescent: outer circle minus an offset circle, traced as two arcs.
func moon() -> SCNNode {
    let r1: CGFloat = 1.0, d: CGFloat = 0.6, r2: CGFloat = 0.85
    let x = (d * d + r1 * r1 - r2 * r2) / (2 * d), y = (r1 * r1 - x * x).squareRoot()
    let a1 = atan2(y, x) * 180 / .pi
    let a2 = atan2(y, x - d) * 180 / .pi
    let p = NSBezierPath()
    p.appendArc(withCenter: .zero, radius: r1, startAngle: a1, endAngle: 360 - a1, clockwise: false)
    p.appendArc(withCenter: NSPoint(x: d, y: 0), radius: r2, startAngle: 360 - a2, endAngle: a2, clockwise: true)
    p.close()
    let n = extruded(p, depth: 0.5, chamfer: 0.12, material(0xF3E3A4, roughness: 0.45, glow: 0xC9A955, glowIntensity: 0.25))
    n.eulerAngles = SCNVector3(0, 0, 0.35)
    return n
}

/// Three ribbons, each a line ending in a curl.
func wind() -> SCNNode {
    let n = SCNNode()
    let mat = material(0xD6EEF4, roughness: 0.4)
    for (i, (y, length)) in [(0.55, 2.2), (0.0, 2.8), (-0.55, 1.9)].enumerated() {
        let path = CGMutablePath()
        let end = -1.4 + length - 0.35
        path.move(to: CGPoint(x: -1.4, y: y))
        path.addLine(to: CGPoint(x: end, y: y))
        // A smooth hook curling up and back.
        path.addCurve(to: CGPoint(x: end + 0.32, y: y + 0.34), control1: CGPoint(x: end + 0.2, y: y),
                      control2: CGPoint(x: end + 0.32, y: y + 0.14))
        path.addCurve(to: CGPoint(x: end + 0.02, y: y + 0.5), control1: CGPoint(x: end + 0.32, y: y + 0.48),
                      control2: CGPoint(x: end + 0.14, y: y + 0.55))
        let outline = path.copy(strokingWithWidth: 0.2, lineCap: .round, lineJoin: .round, miterLimit: 2)
        let ribbon = extruded(NSBezierPath(cgPath: outline), depth: 0.16, chamfer: 0.06, mat)
        ribbon.position = SCNVector3(CGFloat(i % 2) * 0.25, 0, 0)
        n.addChildNode(ribbon)
    }
    return n
}

// MARK: Scenes

func scene(_ build: (SCNNode) -> Void) -> SCNScene {
    let scene = SCNScene()
    let root = SCNNode()
    build(root)
    root.eulerAngles = SCNVector3(0.12, -0.22, 0)   // a little turned, like the stone
    scene.rootNode.addChildNode(root)

    func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ temperature: CGFloat) -> SCNLight {
        let l = SCNLight(); l.type = type; l.intensity = intensity; l.temperature = temperature; return l
    }
    let key = SCNNode(); key.light = light(.directional, 1100, 6000); key.eulerAngles = SCNVector3(-0.7, -0.6, 0)
    let rim = SCNNode(); rim.light = light(.directional, 650, 7500); rim.eulerAngles = SCNVector3(-0.3, 2.5, 0)
    let fill = SCNNode(); fill.light = light(.ambient, 320, 6200)
    [key, rim, fill].forEach(scene.rootNode.addChildNode)
    scene.background.contents = NSColor.clear
    return scene
}

let skies: [(name: String, build: (SCNNode) -> Void)] = [
    ("weather-clear", { $0.addChildNode(sun(0xFFC83A, glow: 0xFF9F1A)) }),
    ("weather-clear-night", { $0.addChildNode(moon()) }),
    ("weather-partly", {
        let s = sun(0xFFC83A, glow: 0xFF9F1A, radius: 0.75); s.position = SCNVector3(0.75, 0.75, -0.8); $0.addChildNode(s)
        let c = cloud(0xF4F6FA); c.position = SCNVector3(-0.15, -0.35, 0.3); c.scale = SCNVector3(0.85, 0.85, 0.85); $0.addChildNode(c)
    }),
    ("weather-partly-night", {
        let m = moon(); m.position = SCNVector3(0.75, 0.75, -0.8); m.scale = SCNVector3(0.75, 0.75, 0.75); $0.addChildNode(m)
        let c = cloud(0xE3E7EF); c.position = SCNVector3(-0.15, -0.35, 0.3); c.scale = SCNVector3(0.85, 0.85, 0.85); $0.addChildNode(c)
    }),
    ("weather-cloudy", { $0.addChildNode(cloud(0xE9EDF3)) }),
    ("weather-rain", {
        let c = cloud(0xA9B4C4); c.position = SCNVector3(0, 0.45, 0); $0.addChildNode(c)
        $0.addChildNode(drops(7, below: -0.55))
    }),
    ("weather-storm", {
        let c = cloud(0x575B72, roughness: 0.75); c.position = SCNVector3(0, 0.45, -0.1); $0.addChildNode(c)
        let b = bolt(); b.position = SCNVector3(0.1, -0.75, 0.35); $0.addChildNode(b)
        let d = drops(3, below: -0.55); d.position = SCNVector3(-0.25, 0, 0); $0.addChildNode(d)
    }),
    ("weather-wind", { $0.addChildNode(wind()) }),
    ("weather-heat", { $0.addChildNode(sun(0xFF7A2A, glow: 0xFF3D00)) }),
]

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal isn't available") }
let folder = URL(fileURLWithPath: catalog).appendingPathComponent("Weather")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try #"{"info":{"author":"xcode","version":1},"properties":{"provides-namespace":false}}"#
    .write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for sky in skies {
    let s = scene(sky.build)
    let camera = SCNCamera()
    camera.fieldOfView = 30
    camera.wantsHDR = true
    camera.wantsExposureAdaptation = false
    let cameraNode = SCNNode(); cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0.4, 9.2)
    cameraNode.look(at: SCNVector3(0, 0, 0))
    s.rootNode.addChildNode(cameraNode)

    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = s
    renderer.pointOfView = cameraNode
    renderer.autoenablesDefaultLighting = false
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
    var rect = CGRect(x: 0, y: 0, width: side, height: side)
    let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!

    let set = folder.appendingPathComponent("\(sky.name).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        .write(to: set.appendingPathComponent("\(sky.name).png"))
    let contents = #"{"images":[{"filename":"\#(sky.name).png","idiom":"universal","scale":"3x"}],"info":{"author":"xcode","version":1}}"#
    try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(set.lastPathComponent)")
}

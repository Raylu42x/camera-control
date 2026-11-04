// Draws the app icon and writes the full macOS AppIcon set.
// Usage: swift scripts/make-icon.swift CameraControl/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size s: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let u = s / 1024
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

    // Tile: macOS icon grid leaves ~100pt margin; gradient purple → pink.
    let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 30 * u, color: color(0, 0, 0, 0.35))
    ctx.addPath(rounded(tile, 185 * u)); ctx.setFillColor(color(0.4, 0.2, 0.85)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rounded(tile, 185 * u)); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [color(0.33, 0.2, 0.9), color(0.95, 0.3, 0.55)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    ctx.restoreGState()

    // Camera body.
    let body = CGRect(x: 220 * u, y: 300 * u, width: 584 * u, height: 400 * u)
    ctx.addPath(rounded(CGRect(x: 400 * u, y: 660 * u, width: 224 * u, height: 90 * u), 30 * u))
    ctx.setFillColor(color(1, 1, 1, 0.95)); ctx.fillPath()
    ctx.addPath(rounded(body, 80 * u)); ctx.fillPath()

    // Lens: dark ring with a glossy center.
    let c = CGPoint(x: 512 * u, y: 500 * u)
    func circle(_ r: CGFloat, _ col: CGColor) {
        ctx.setFillColor(col); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    circle(165 * u, color(0.15, 0.1, 0.3))
    circle(120 * u, color(0.35, 0.25, 0.85))
    circle(70 * u, color(0.1, 0.05, 0.25))
    ctx.setFillColor(color(1, 1, 1, 0.8))
    ctx.fillEllipse(in: CGRect(x: c.x - 75 * u, y: c.y + 30 * u, width: 50 * u, height: 50 * u))

    // Red "live" dot.
    ctx.setFillColor(color(1, 0.2, 0.25))
    ctx.fillEllipse(in: CGRect(x: 690 * u, y: 600 * u, width: 60 * u, height: 60 * u))

    // Sparkle (four-point star) top-left.
    func sparkle(_ p: CGPoint, _ r: CGFloat) {
        ctx.move(to: CGPoint(x: p.x, y: p.y + r))
        ctx.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
        ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p)
        ctx.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
        ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: p)
        ctx.setFillColor(color(1, 0.95, 0.6)); ctx.fillPath()
    }
    sparkle(CGPoint(x: 250 * u, y: 790 * u), 85 * u)
    sparkle(CGPoint(x: 820 * u, y: 250 * u), 55 * u)
    return ctx.makeImage()!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        let rep = NSBitmapImageRep(cgImage: drawIcon(size: CGFloat(px)))
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("wrote \(images.count) icons to \(outDir)")

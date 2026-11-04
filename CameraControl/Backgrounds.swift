import AppKit
import CoreImage

/// Procedurally drawn virtual backgrounds, rendered once per preset at canvas size.
enum Backgrounds {
    private static let lock = NSLock()
    private static var cache: [BackgroundPreset: CIImage] = [:]

    static func image(_ preset: BackgroundPreset) -> CIImage {
        lock.lock(); defer { lock.unlock() }
        if let img = cache[preset] { return img }
        var img = CIImage(cgImage: draw(preset))
        // Soften the scene a little so it reads as "behind" you.
        if ![.greenScreen, .matrix, .weather].contains(preset) {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: 2.5).cropped(to: canvasRect)
        }
        cache[preset] = img
        return img
    }

    private static func draw(_ preset: BackgroundPreset) -> CGImage {
        let w = Int(canvasSize.width), h = Int(canvasSize.height)
        let W = CGFloat(w), H = CGFloat(h)
        var rng = SeededRandom(seed: 42)
        return makeImage(width: w, height: h) { ctx in
            switch preset {
            case .newsStudio:
                linearGradient(ctx, [rgb(0.02, 0.05, 0.16), rgb(0.05, 0.18, 0.42), rgb(0.02, 0.06, 0.2)],
                               from: CGPoint(x: 0, y: 0), to: CGPoint(x: W, y: H))
                // Big glowing globe-ish rings.
                ctx.setLineWidth(3)
                for i in 0..<7 {
                    ctx.setStrokeColor(rgb(0.3, 0.6, 1, 0.12 + CGFloat(i) * 0.02).cgColor)
                    let r = 120 + CGFloat(i) * 55
                    ctx.strokeEllipse(in: CGRect(x: W * 0.72 - r, y: H * 0.55 - r * 0.8, width: r * 2, height: r * 1.6))
                }
                // Video wall panels.
                for col in 0..<4 {
                    for row in 0..<3 {
                        let rect = CGRect(x: 60 + CGFloat(col) * 150, y: 300 + CGFloat(row) * 105, width: 138, height: 95)
                        fill(ctx, rect, rgb(0.1, 0.35, 0.75, 0.25 + rng.next() * 0.25), radius: 6)
                    }
                }
                // Desk glow along the bottom.
                radialGradient(ctx, [rgb(0.4, 0.7, 1, 0.45), rgb(0.4, 0.7, 1, 0)], center: CGPoint(x: W / 2, y: 0), radius: 520)
                fill(ctx, CGRect(x: 0, y: 0, width: W, height: 120), rgb(0.02, 0.04, 0.1, 0.85))
                fill(ctx, CGRect(x: 0, y: 118, width: W, height: 4), rgb(0.35, 0.65, 1, 0.9))

            case .city:
                linearGradient(ctx, [rgb(0.15, 0.05, 0.3), rgb(0.02, 0.02, 0.08)],
                               from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: 0))
                radialGradient(ctx, [rgb(1, 0.95, 0.8), rgb(1, 0.95, 0.8, 0)], center: CGPoint(x: W * 0.8, y: H * 0.82), radius: 60)
                var x: CGFloat = 0
                while x < W {
                    let bw = 50 + rng.next() * 90, bh = 180 + rng.next() * 380
                    fill(ctx, CGRect(x: x, y: 0, width: bw, height: bh), rgb(0.04, 0.03, 0.1))
                    var wy: CGFloat = 20
                    while wy < bh - 20 {
                        var wx = x + 8
                        while wx < x + bw - 12 {
                            if rng.next() > 0.55 {
                                fill(ctx, CGRect(x: wx, y: wy, width: 7, height: 10), rgb(1, 0.85, 0.45, 0.4 + rng.next() * 0.6))
                            }
                            wx += 14
                        }
                        wy += 20
                    }
                    x += bw + 4
                }

            case .sunset:
                linearGradient(ctx, [rgb(0.25, 0.1, 0.45), rgb(0.95, 0.35, 0.4), rgb(1, 0.7, 0.35)],
                               from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: H * 0.3))
                radialGradient(ctx, [rgb(1, 0.95, 0.6), rgb(1, 0.8, 0.4, 0)], center: CGPoint(x: W / 2, y: H * 0.32), radius: 260)
                fill(ctx, CGRect(x: W / 2 - 110, y: H * 0.32 - 110, width: 220, height: 220), rgb(1, 0.9, 0.55), radius: 110)
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: H * 0.3))
                linearGradient(ctx, [rgb(0.45, 0.15, 0.35), rgb(0.12, 0.04, 0.2)],
                               from: CGPoint(x: 0, y: H * 0.3), to: CGPoint(x: 0, y: 0))
                for i in 0..<10 {
                    let y = H * 0.3 - 8 - CGFloat(i) * 18
                    let half = 120 - CGFloat(i) * 9
                    fill(ctx, CGRect(x: W / 2 - half, y: y, width: half * 2, height: 4), rgb(1, 0.8, 0.5, 0.5))
                }
                ctx.restoreGState()

            case .space:
                fill(ctx, CGRect(x: 0, y: 0, width: W, height: H), rgb(0.01, 0.01, 0.04))
                radialGradient(ctx, [rgb(0.6, 0.2, 0.8, 0.55), rgb(0.6, 0.2, 0.8, 0)], center: CGPoint(x: W * 0.3, y: H * 0.6), radius: 420)
                radialGradient(ctx, [rgb(0.1, 0.5, 0.9, 0.45), rgb(0.1, 0.5, 0.9, 0)], center: CGPoint(x: W * 0.75, y: H * 0.35), radius: 380)
                for _ in 0..<500 {
                    let s = rng.next() * 2.4 + 0.4
                    fill(ctx, CGRect(x: rng.next() * W, y: rng.next() * H, width: s, height: s), rgb(1, 1, 1, 0.4 + rng.next() * 0.6), radius: s / 2)
                }
                // A ringed planet.
                fill(ctx, CGRect(x: W * 0.78, y: H * 0.68, width: 140, height: 140), rgb(0.95, 0.6, 0.35), radius: 70)
                ctx.setStrokeColor(rgb(1, 0.85, 0.6, 0.8).cgColor)
                ctx.setLineWidth(6)
                ctx.strokeEllipse(in: CGRect(x: W * 0.78 - 50, y: H * 0.68 + 50, width: 240, height: 40))

            case .beach:
                linearGradient(ctx, [rgb(0.35, 0.7, 1), rgb(0.75, 0.9, 1)],
                               from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: H * 0.45))
                radialGradient(ctx, [rgb(1, 1, 0.85), rgb(1, 1, 0.85, 0)], center: CGPoint(x: W * 0.2, y: H * 0.85), radius: 140)
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: H * 0.25, width: W, height: H * 0.2))
                linearGradient(ctx, [rgb(0.0, 0.45, 0.7), rgb(0.15, 0.75, 0.8)],
                               from: CGPoint(x: 0, y: H * 0.45), to: CGPoint(x: 0, y: H * 0.25))
                ctx.restoreGState()
                fill(ctx, CGRect(x: 0, y: 0, width: W, height: H * 0.26), rgb(0.96, 0.86, 0.65))
                fill(ctx, CGRect(x: 0, y: H * 0.25, width: W, height: 6), rgb(1, 1, 1, 0.7))

            case .synthwave:
                linearGradient(ctx, [rgb(0.05, 0.0, 0.15), rgb(0.5, 0.05, 0.45), rgb(1, 0.4, 0.4)],
                               from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: H * 0.4))
                fill(ctx, CGRect(x: W / 2 - 150, y: H * 0.4 - 40, width: 300, height: 300), rgb(1, 0.75, 0.3), radius: 150)
                for i in 0..<6 {
                    fill(ctx, CGRect(x: W / 2 - 160, y: H * 0.4 + CGFloat(i) * 22, width: 320, height: CGFloat(6 - i) + 2), rgb(0.5, 0.05, 0.45))
                }
                fill(ctx, CGRect(x: 0, y: 0, width: W, height: H * 0.4), rgb(0.06, 0.0, 0.12))
                ctx.setStrokeColor(rgb(1, 0.2, 0.9, 0.9).cgColor)
                ctx.setLineWidth(2)
                let horizon = H * 0.4
                for i in -16...16 {
                    ctx.move(to: CGPoint(x: W / 2 + CGFloat(i) * 20, y: horizon))
                    ctx.addLine(to: CGPoint(x: W / 2 + CGFloat(i) * 160, y: 0))
                }
                var y = horizon
                var step: CGFloat = 6
                while y > 0 {
                    ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y))
                    y -= step; step *= 1.35
                }
                ctx.strokePath()

            case .greenScreen:
                fill(ctx, CGRect(x: 0, y: 0, width: W, height: H), rgb(0, 0.85, 0.25))

            case .weather:
                drawWeatherMap(ctx, W: W, H: H, rng: &rng)

            case .snow:
                linearGradient(ctx, [rgb(0.05, 0.08, 0.2), rgb(0.25, 0.35, 0.55)],
                               from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: 0))
                radialGradient(ctx, [rgb(0.95, 0.95, 1, 0.9), rgb(0.95, 0.95, 1, 0)], center: CGPoint(x: W * 0.15, y: H * 0.85), radius: 70)
                // Rolling snowy hills with pine trees.
                for (i, hill) in [(0.0, 0.32, rgb(0.82, 0.86, 0.95)), (0.45, 0.24, rgb(0.92, 0.94, 1)), (-0.2, 0.16, rgb(1, 1, 1))].enumerated() {
                    ctx.setFillColor(hill.2.cgColor)
                    ctx.move(to: CGPoint(x: 0, y: 0))
                    var x: CGFloat = 0
                    while x <= W {
                        ctx.addLine(to: CGPoint(x: x, y: H * hill.1 + sin(x / 180 + hill.0 * 6) * 30))
                        x += 20
                    }
                    ctx.addLine(to: CGPoint(x: W, y: 0))
                    ctx.fillPath()
                    for _ in 0..<(6 - i * 2) {
                        let tx = rng.next() * W, ty = H * hill.1 - 20, th = 70 + rng.next() * 60
                        ctx.setFillColor(rgb(0.1, 0.25 + CGFloat(i) * 0.05, 0.2).cgColor)
                        ctx.move(to: CGPoint(x: tx - th * 0.3, y: ty)); ctx.addLine(to: CGPoint(x: tx, y: ty + th))
                        ctx.addLine(to: CGPoint(x: tx + th * 0.3, y: ty)); ctx.fillPath()
                    }
                }

            case .matrix:
                fill(ctx, CGRect(x: 0, y: 0, width: W, height: H), .black)

            case .clouds:
                linearGradient(ctx, [rgb(0.25, 0.55, 0.95), rgb(0.7, 0.85, 1)],
                               from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: 0))
                radialGradient(ctx, [rgb(1, 1, 0.9, 0.9), rgb(1, 1, 0.9, 0)], center: CGPoint(x: W * 0.85, y: H * 0.85), radius: 160)

            case .aquarium:
                linearGradient(ctx, [rgb(0.1, 0.55, 0.75), rgb(0.02, 0.15, 0.35)],
                               from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: 0))
                // Light rays from the surface.
                for i in 0..<6 {
                    let x = CGFloat(i) * 240 + rng.next() * 80
                    ctx.setFillColor(rgb(0.8, 1, 1, 0.07).cgColor)
                    ctx.move(to: CGPoint(x: x, y: H)); ctx.addLine(to: CGPoint(x: x + 90, y: H))
                    ctx.addLine(to: CGPoint(x: x + 260, y: 0)); ctx.addLine(to: CGPoint(x: x + 120, y: 0)); ctx.fillPath()
                }
                fill(ctx, CGRect(x: 0, y: 0, width: W, height: 70), rgb(0.85, 0.75, 0.5))
                // Seaweed.
                ctx.setLineWidth(9); ctx.setLineCap(.round)
                for i in 0..<14 {
                    let x = CGFloat(i) * 95 + rng.next() * 40, h = 120 + rng.next() * 200
                    ctx.setStrokeColor(rgb(0.1, 0.5 + rng.next() * 0.2, 0.25).cgColor)
                    ctx.move(to: CGPoint(x: x, y: 50))
                    ctx.addCurve(to: CGPoint(x: x + 10, y: 50 + h), control1: CGPoint(x: x + 40, y: 50 + h * 0.3),
                                 control2: CGPoint(x: x - 40, y: 50 + h * 0.7))
                    ctx.strokePath()
                }
            }
        }
    }
}

/// Fictional cities on the weather map: name, position, temperature and forecast emoji.
let weatherCities: [(name: String, x: CGFloat, y: CGFloat, temp: Int, icon: String)] = [
    ("Pixelburg", 170, 530, 72, "☀️"), ("Zoomsville", 300, 330, 64, "🌧️"), ("Webcam City", 190, 150, 41, "🌨️"),
    ("Bufferton", 1060, 560, 58, "⛅"), ("Mute Harbor", 1110, 340, 61, "⛈️"), ("Port Latency", 990, 160, 77, "☀️"),
]

private func drawWeatherMap(_ ctx: CGContext, W: CGFloat, H: CGFloat, rng: inout SeededRandom) {
    linearGradient(ctx, [rgb(0.12, 0.35, 0.65), rgb(0.05, 0.2, 0.45)], from: CGPoint(x: 0, y: H), to: .zero)
    // Two blobby continents.
    for (cx, cy, r) in [(W * 0.22, H * 0.5, 330.0), (W * 0.8, H * 0.48, 320.0)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.setFillColor(rgb(0.35, 0.62, 0.3).cgColor)
        let steps = 18
        for s in 0...steps {
            let a = CGFloat(s) / CGFloat(steps) * .pi * 2
            let rr = r * (0.75 + rng.next() * 0.35)
            let p = CGPoint(x: cx + cos(a) * rr * 0.75, y: cy + sin(a) * rr)
            s == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
        }
        ctx.closePath(); ctx.fillPath()
    }
    // Dashed borders.
    ctx.setStrokeColor(rgb(1, 1, 1, 0.35).cgColor); ctx.setLineWidth(2); ctx.setLineDash(phase: 0, lengths: [8, 6])
    for x in [W * 0.18, W * 0.27, W * 0.78, W * 0.86] {
        ctx.move(to: CGPoint(x: x, y: H * 0.15)); ctx.addLine(to: CGPoint(x: x + 30, y: H * 0.85))
    }
    ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
    // A cold front.
    ctx.setStrokeColor(rgb(0.3, 0.6, 1).cgColor); ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: 60, y: 260)); ctx.addCurve(to: CGPoint(x: 420, y: 420), control1: CGPoint(x: 200, y: 200), control2: CGPoint(x: 300, y: 480))
    ctx.strokePath()
    // City dots, names and temperatures.
    for c in weatherCities {
        fill(ctx, CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10), .white, radius: 5)
        drawText(c.name, in: CGRect(x: c.x - 80, y: c.y - 44, width: 160, height: 28), font: font(20, weight: .bold), color: .white, center: true)
        let box = CGRect(x: c.x + 40, y: c.y - 2, width: 74, height: 40)
        fill(ctx, box, rgb(0, 0, 0, 0.45), radius: 8)
        drawText("\(c.temp)°", in: box, font: font(28, weight: .heavy), color: rgb(1, 0.85, 0.3), center: true)
    }
    // Banner.
    let banner = CGRect(x: W - 330, y: H - 70, width: 300, height: 46)
    fill(ctx, banner, rgb(0.85, 0.05, 0.1), radius: 6)
    drawText("LOCAL FORECAST", in: banner, font: font(26, condensed: true), color: .white, center: true)
}

/// Tiny deterministic RNG so the procedural scenes look the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

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
        if preset != .greenScreen {
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
            }
        }
    }
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

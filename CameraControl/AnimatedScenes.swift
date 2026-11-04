import AppKit
import CoreImage

/// Moving backgrounds: the static part comes from `Backgrounds`; this adds what moves.
final class AnimatedScenes {
    private lazy var flake: CIImage = softDot(radius: 6, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    private lazy var bubble: CIImage = {
        CIImage(cgImage: makeImage(width: 24, height: 24) { ctx in
            ctx.setStrokeColor(rgb(0.9, 1, 1, 0.7).cgColor); ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
            fill(ctx, CGRect(x: 6, y: 13, width: 5, height: 5), rgb(1, 1, 1, 0.8), radius: 2.5)
        })
    }()
    private lazy var cloudSprites: [CIImage] = (0..<4).map { seed in
        var rng = SeededRandom(seed: UInt64(seed + 7))
        let cg = makeImage(width: 420, height: 200) { ctx in
            for _ in 0..<9 {
                let r = 40 + rng.next() * 50
                let x = 60 + rng.next() * 260, y = 50 + rng.next() * 60
                fill(ctx, CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6), rgb(1, 1, 1, 0.9), radius: r * 0.8)
            }
        }
        return CIImage(cgImage: cg).clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: CGRect(x: 0, y: 0, width: 420, height: 200))
    }

    // Code rain is drawn on the CPU from pre-rendered glyphs (far cheaper than text layout per frame).
    private static let rainChars = Array("アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789ﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘ")
    private lazy var rainGlyphs: [(green: CGImage, white: CGImage)] = Self.rainChars.map { ch in
        func glyph(_ color: NSColor) -> CGImage {
            makeImage(width: 20, height: 24) { _ in
                drawText(String(ch), in: CGRect(x: 0, y: 0, width: 20, height: 24),
                         font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium), color: color, center: true)
            }
        }
        return (glyph(rgb(0.2, 1, 0.45)), glyph(rgb(0.85, 1, 0.9)))
    }
    private lazy var rainContext: CGContext = CGContext(
        data: nil, width: Int(canvasSize.width), height: Int(canvasSize.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    func image(_ preset: BackgroundPreset, time t: Double) -> CIImage {
        let W = canvasSize.width, H = canvasSize.height
        var out = Backgrounds.image(preset)
        switch preset {
        case .snow:
            for i in 0..<90 {
                var rng = SeededRandom(seed: UInt64(i * 31 + 5))
                let speed = 30 + rng.next() * 70, size = 0.4 + rng.next()
                let y = H + 10 - CGFloat((t * Double(speed) + Double(rng.next() * H)).truncatingRemainder(dividingBy: Double(H + 20)))
                let x = rng.next() * W + CGFloat(sin(t * Double(0.5 + rng.next()) + Double(i))) * 25
                out = flake.placed(center: CGPoint(x: x, y: y), width: 12 * size).composited(over: out)
            }

        case .clouds:
            for i in 0..<7 {
                var rng = SeededRandom(seed: UInt64(i * 13 + 3))
                let speed = 12 + rng.next() * 25, scale = 0.6 + rng.next() * 0.8
                let x = CGFloat((Double(rng.next() * (W + 500)) + t * Double(speed)).truncatingRemainder(dividingBy: Double(W + 500))) - 450
                let y = H * 0.35 + rng.next() * H * 0.55
                out = cloudSprites[i % cloudSprites.count]
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y)))
                    .composited(over: out)
            }

        case .aquarium:
            let fish = ["🐠", "🐟", "🐡", "🐠", "🦈", "🐟", "🐙"]
            for (i, f) in fish.enumerated() {
                var rng = SeededRandom(seed: UInt64(i * 17 + 1))
                let speed = (f == "🐙" ? 15 : 40 + rng.next() * 60) * (rng.next() > 0.5 ? 1 : -1)
                let span = Double(W + 300)
                var x = (Double(rng.next()) * span + t * Double(speed)).truncatingRemainder(dividingBy: span)
                if x < 0 { x += span }
                let y = 130 + rng.next() * (H - 260) + CGFloat(sin(t * 1.3 + Double(i))) * 15
                let size: CGFloat = f == "🦈" ? 150 : 60 + rng.next() * 50
                // Emoji fish face left; flip the ones swimming right.
                var sprite = EmojiCache.shared.image(f)
                if speed > 0 { sprite = sprite.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
                out = sprite.placed(center: CGPoint(x: CGFloat(x) - 150, y: y), width: size).composited(over: out)
            }
            for i in 0..<24 {
                var rng = SeededRandom(seed: UInt64(i * 7 + 11))
                let speed = 40 + rng.next() * 60
                let y = CGFloat((t * Double(speed) + Double(rng.next() * H)).truncatingRemainder(dividingBy: Double(H))) + 60
                let x = rng.next() * W + CGFloat(sin(t * 2 + Double(i))) * 6
                out = bubble.placed(center: CGPoint(x: x, y: y), width: 10 + rng.next() * 14).composited(over: out)
            }

        case .weather:
            for (i, c) in weatherCities.enumerated() {
                let bob = CGFloat(sin(t * 2 + Double(i))) * 6
                let spin = c.icon == "☀️" ? CGFloat(t * 0.6) : 0
                out = EmojiCache.shared.image(c.icon)
                    .placed(center: CGPoint(x: c.x - 60, y: c.y + 30 + bob), width: 78, rotation: spin)
                    .composited(over: out)
            }

        case .matrix:
            out = codeRain(time: t)

        default:
            break
        }
        return out.cropped(to: canvasRect)
    }

    private func codeRain(time t: Double) -> CIImage {
        let ctx = rainContext
        let W = canvasSize.width, H = canvasSize.height
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let columns = Int(W / 20), trail = 18
        for col in 0..<columns {
            var rng = SeededRandom(seed: UInt64(col * 97 + 1))
            let speed = 6 + rng.next() * 14                  // rows per second
            let rows = Double(H / 24) + Double(trail)
            let head = (t * Double(speed) + Double(rng.next()) * rows).truncatingRemainder(dividingBy: rows)
            for k in 0..<trail {
                let row = Int(head) - k
                guard row >= 0 else { continue }
                let y = H - CGFloat(row + 1) * 24
                guard y > -24, y < H else { continue }
                // Characters flicker to new symbols a few times a second.
                let pick = Int((Double(col * 31 + row * 7) + floor(t * 3 + Double(k))).truncatingRemainder(dividingBy: Double(rainGlyphs.count)))
                let g = rainGlyphs[abs(pick)]
                ctx.setAlpha(k == 0 ? 1 : max(0.08, 1 - CGFloat(k) / CGFloat(trail)))
                ctx.draw(k == 0 ? g.white : g.green, in: CGRect(x: CGFloat(col) * 20, y: y, width: 20, height: 24))
            }
        }
        ctx.setAlpha(1)
        return CIImage(cgImage: ctx.makeImage()!)
    }
}

/// A soft round sprite, transparent at the edge.
func softDot(radius r: CGFloat, color: CIColor) -> CIImage {
    CIFilter(name: "CIRadialGradient", parameters: [
        kCIInputCenterKey: CIVector(x: r, y: r), "inputRadius0": r * 0.3, "inputRadius1": r,
        "inputColor0": color, "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)])!
        .outputImage!.cropped(to: CGRect(x: 0, y: 0, width: r * 2, height: r * 2))
}

import AppKit
import CoreImage

/// Text graphics (news package, captions, "be right back" card). Each graphic is
/// rendered once per distinct text and cached; only positions change per frame.
final class OverlayRenderer {
    private var cache: [String: CIImage] = [:]

    private let navy = rgb(0.04, 0.1, 0.28)
    private let red = rgb(0.82, 0.04, 0.09)
    private let gold = rgb(1, 0.78, 0.05)
    static let tickerHeight: CGFloat = 46
    private let tickerLabelWidth: CGFloat = 150

    private func cached(_ key: String, _ make: () -> CGImage) -> CIImage {
        if let img = cache[key] { return img }
        if cache.count > 64 { cache.removeAll() }
        let img = CIImage(cgImage: make())
        cache[key] = img
        return img
    }

    // MARK: News package

    func lowerThird(tag: String, name: String, title: String) -> CIImage {
        cached("lt|\(tag)|\(name)|\(title)") {
            let tagFont = font(22, condensed: true), nameFont = font(46, condensed: true), titleFont = font(22, weight: .medium)
            let tagW = textSize(tag, tagFont).width + 32
            let barW = max(textSize(name, nameFont).width + 64, textSize(title, titleFont).width + 56, 560)
            return makeImage(width: Int(barW + 20), height: 170) { ctx in
                // Tag strip on top, then name bar, then title bar.
                if !tag.isEmpty {
                    let r = CGRect(x: 0, y: 128, width: tagW, height: 38)
                    fill(ctx, r, red)
                    drawText(tag.uppercased(), in: r.insetBy(dx: 16, dy: 0), font: tagFont, color: .white)
                }
                let nameRect = CGRect(x: 0, y: 64, width: barW, height: 64)
                ctx.saveGState()
                ctx.clip(to: nameRect)
                linearGradient(ctx, [rgb(1, 1, 1), rgb(0.86, 0.89, 0.95)], from: CGPoint(x: 0, y: 128), to: CGPoint(x: 0, y: 64))
                ctx.restoreGState()
                fill(ctx, CGRect(x: 0, y: 64, width: 10, height: 64), red)
                drawText(name, in: CGRect(x: 26, y: 64, width: barW, height: 64), font: nameFont, color: navy)
                let titleRect = CGRect(x: 0, y: 28, width: barW, height: 36)
                fill(ctx, titleRect, navy)
                drawText(title, in: titleRect.insetBy(dx: 26, dy: 0), font: titleFont, color: .white)
            }
        }
    }

    /// Scrolling ticker across the bottom; `time` drives the scroll.
    func ticker(text: String, time: Double) -> CIImage {
        let h = Self.tickerHeight
        let bar = cached("tickerbar") {
            makeImage(width: Int(canvasSize.width), height: Int(h)) { ctx in
                fill(ctx, CGRect(x: 0, y: 0, width: canvasSize.width, height: h), rgb(0.02, 0.05, 0.15, 0.94))
                fill(ctx, CGRect(x: 0, y: h - 3, width: canvasSize.width, height: 3), red)
            }
        }
        let label = cached("tickerlabel") {
            makeImage(width: Int(tickerLabelWidth), height: Int(h)) { ctx in
                fill(ctx, CGRect(x: 0, y: 0, width: tickerLabelWidth, height: h - 3), gold)
                drawText("LATEST", in: CGRect(x: 0, y: 0, width: tickerLabelWidth, height: h - 3),
                         font: font(24, condensed: true), color: navy, center: true)
            }
        }
        let tickerFont = font(23, weight: .semibold)
        let strip = cached("strip|\(text)") {
            let s = text + "   •   "
            let w = textSize(s, tickerFont).width
            return makeImage(width: Int(ceil(w)), height: Int(h)) { _ in
                drawText(s, in: CGRect(x: 0, y: 0, width: w, height: h - 3), font: tickerFont, color: .white)
            }
        }
        let stripW = strip.extent.width
        let offset = CGFloat((time * 110).truncatingRemainder(dividingBy: Double(stripW)))
        var moving = CIImage.empty()
        var x = tickerLabelWidth - offset
        while x < canvasSize.width {
            moving = strip.transformed(by: CGAffineTransform(translationX: x, y: 0)).composited(over: moving)
            x += stripW
        }
        moving = moving.cropped(to: CGRect(x: tickerLabelWidth, y: 0, width: canvasSize.width - tickerLabelWidth, height: h))
        return label.composited(over: moving.composited(over: bar))
    }

    func liveBug(channel: String, clock: String) -> CIImage {
        cached("bug|\(channel)|\(clock)") {
            let liveFont = font(24, condensed: true), chFont = font(22, condensed: true), clockFont = font(20, weight: .semibold)
            let liveW: CGFloat = 92
            let chW = textSize(channel, chFont).width + 28
            let clockW = textSize(clock, clockFont).width + 24
            let h: CGFloat = 40
            return makeImage(width: Int(liveW + chW + clockW), height: Int(h)) { ctx in
                fill(ctx, CGRect(x: 0, y: 0, width: liveW, height: h), red)
                fill(ctx, CGRect(x: 14, y: h / 2 - 6, width: 12, height: 12), .white, radius: 6)
                drawText("LIVE", in: CGRect(x: 34, y: 0, width: liveW, height: h), font: liveFont, color: .white)
                fill(ctx, CGRect(x: liveW, y: 0, width: chW, height: h), navy)
                drawText(channel, in: CGRect(x: liveW + 14, y: 0, width: chW, height: h), font: chFont, color: .white)
                fill(ctx, CGRect(x: liveW + chW, y: 0, width: clockW, height: h), rgb(0, 0, 0, 0.6))
                drawText(clock, in: CGRect(x: liveW + chW + 12, y: 0, width: clockW, height: h), font: clockFont, color: .white)
            }
        }
    }

    // MARK: Caption and hold card

    func caption(_ text: String) -> CIImage {
        cached("cap|\(text)") {
            let f = font(36, weight: .bold)
            let size = textSize(text, f)
            let w = min(size.width + 48, canvasSize.width - 80), h = size.height + 24
            return makeImage(width: Int(w), height: Int(h)) { ctx in
                fill(ctx, CGRect(x: 0, y: 0, width: w, height: h), rgb(0, 0, 0, 0.62), radius: 16)
                drawText(text, in: CGRect(x: 0, y: 0, width: w, height: h), font: f, color: .white, center: true)
            }
        }
    }

    /// Full-frame "be right back" text layer (transparent, goes over a blurred or gradient backdrop).
    func holdCard(title: String, subtitle: String) -> CIImage {
        cached("hold|\(title)|\(subtitle)") {
            makeImage(width: Int(canvasSize.width), height: Int(canvasSize.height)) { _ in
                let mid = canvasSize.height / 2
                drawText(title, in: CGRect(x: 0, y: mid, width: canvasSize.width, height: 110),
                         font: font(84, weight: .heavy), color: .white, center: true)
                drawText(subtitle, in: CGRect(x: 0, y: mid - 70, width: canvasSize.width, height: 60),
                         font: font(34, weight: .medium), color: rgb(1, 1, 1, 0.85), center: true)
            }
        }
    }

    /// What viewers see while the camera is switched off.
    func offCard() -> CIImage {
        cached("off") {
            makeImage(width: Int(canvasSize.width), height: Int(canvasSize.height)) { ctx in
                fill(ctx, canvasRect, rgb(0.06, 0.06, 0.08))
                drawText("Camera off", in: CGRect(x: 0, y: canvasSize.height / 2 - 30, width: canvasSize.width, height: 60),
                         font: font(30, weight: .semibold), color: rgb(1, 1, 1, 0.45), center: true)
            }
        }
    }

    /// Title, big countdown and subtitle for the "starting soon" card (transparent).
    func startingSoon(title: String, clock: String, subtitle: String) -> CIImage {
        cached("soon|\(title)|\(clock)|\(subtitle)") {
            makeImage(width: Int(canvasSize.width), height: Int(canvasSize.height)) { _ in
                let mid = canvasSize.height / 2
                drawText(title, in: CGRect(x: 0, y: mid + 90, width: canvasSize.width, height: 100),
                         font: font(76, weight: .heavy), color: .white, center: true)
                drawText(clock, in: CGRect(x: 0, y: mid - 70, width: canvasSize.width, height: 160),
                         font: NSFont.monospacedDigitSystemFont(ofSize: 140, weight: .black), color: .white, center: true)
                drawText(subtitle, in: CGRect(x: 0, y: mid - 150, width: canvasSize.width, height: 60),
                         font: font(32, weight: .medium), color: rgb(1, 1, 1, 0.85), center: true)
            }
        }
    }

    /// A full-frame message on a dark background (e.g. waiting for screen permission).
    func message(_ text: String) -> CIImage {
        cached("msg|\(text)") {
            makeImage(width: Int(canvasSize.width), height: Int(canvasSize.height)) { ctx in
                fill(ctx, canvasRect, rgb(0.1, 0.1, 0.14))
                drawText(text, in: CGRect(x: 0, y: canvasSize.height / 2 - 30, width: canvasSize.width, height: 60),
                         font: font(26, weight: .medium), color: rgb(1, 1, 1, 0.7), center: true)
            }
        }
    }

    func holdBackdrop() -> CIImage {
        cached("holdbg") {
            makeImage(width: Int(canvasSize.width), height: Int(canvasSize.height)) { ctx in
                linearGradient(ctx, [rgb(0.35, 0.15, 0.7), rgb(0.9, 0.3, 0.5)],
                               from: .zero, to: CGPoint(x: canvasSize.width, y: canvasSize.height))
            }
        }
    }
}

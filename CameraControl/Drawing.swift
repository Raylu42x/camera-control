import AppKit
import CoreImage

/// Draws into an sRGB bitmap with AppKit available (bottom-left origin).
func makeImage(width: Int, height: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func font(_ size: CGFloat, weight: NSFont.Weight = .bold, condensed: Bool = false) -> NSFont {
    if condensed, let f = NSFont(name: "HelveticaNeue-CondensedBold", size: size) { return f }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

func textSize(_ s: String, _ f: NSFont) -> CGSize {
    (s as NSString).size(withAttributes: [.font: f])
}

/// Draws text with its bounding box vertically centered in `rect`, starting at rect.minX
/// (or centered horizontally when `center` is true).
func drawText(_ s: String, in rect: CGRect, font f: NSFont, color: NSColor, center: Bool = false) {
    let size = textSize(s, f)
    let x = center ? rect.midX - size.width / 2 : rect.minX
    let y = rect.midY - size.height / 2
    (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: f, .foregroundColor: color])
}

func fill(_ ctx: CGContext, _ rect: CGRect, _ color: NSColor, radius: CGFloat = 0) {
    ctx.setFillColor(color.cgColor)
    if radius > 0 {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    } else {
        ctx.fill(rect)
    }
}

func linearGradient(_ ctx: CGContext, _ colors: [NSColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radialGradient(_ ctx: CGContext, _ colors: [NSColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Emoji rendered once at 160px and cached; scale the CIImage to the size you need.
final class EmojiCache {
    static let shared = EmojiCache()
    static let baseSize: CGFloat = 160
    private let lock = NSLock()
    private var cache: [String: CIImage] = [:]

    func image(_ emoji: String) -> CIImage {
        lock.lock(); defer { lock.unlock() }
        if let img = cache[emoji] { return img }
        let s = Int(Self.baseSize)
        let cg = makeImage(width: s, height: s) { _ in
            drawText(emoji, in: CGRect(x: 0, y: 0, width: s, height: s),
                     font: NSFont.systemFont(ofSize: Self.baseSize * 0.8), color: .white, center: true)
        }
        let img = CIImage(cgImage: cg)
        cache[emoji] = img
        return img
    }
}

extension CIImage {
    /// Scales and centers the image so it covers `rect`, then crops to it.
    func aspectFill(_ rect: CGRect, zoom: CGFloat = 1) -> CIImage {
        let e = extent
        let scale = max(rect.width / e.width, rect.height / e.height) * zoom
        let w = e.width * scale, h = e.height * scale
        return transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: rect.midX - w / 2, y: rect.midY - h / 2)))
            .cropped(to: rect)
    }

    /// Places the image (any size) so it is `size` wide, centered at `center`.
    func placed(center: CGPoint, width: CGFloat, rotation: CGFloat = 0) -> CIImage {
        let e = extent
        let s = width / e.width
        return transformed(by: CGAffineTransform(translationX: -e.midX, y: -e.midY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }

    func withAlpha(_ a: CGFloat) -> CIImage {
        // CIColorMatrix works on unpremultiplied color, so only alpha needs scaling.
        applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
    }
}

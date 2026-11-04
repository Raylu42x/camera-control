import AppKit
import CoreImage

/// Recent cut-outs of the person, for clones and ghost trails. Frames are copied into
/// our own buffers so the camera's buffer pool is never held up.
final class FrameHistory {
    private static let depth = 17
    private var frames: [CIImage] = []
    private var pool: CVPixelBufferPool?

    func push(_ cutout: CIImage, context: CIContext) {
        if pool == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(canvasSize.width),
                kCVPixelBufferHeightKey: Int(canvasSize.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: Self.depth + 2] as CFDictionary,
                                    attrs as CFDictionary, &pool)
        }
        guard let pool else { return }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let pb else { return }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        context.render(cutout, to: pb, bounds: canvasRect, colorSpace: sRGB)
        frames.append(CIImage(cvPixelBuffer: pb, options: [.colorSpace: sRGB]))
        if frames.count > Self.depth { frames.removeFirst() }
    }

    func clear() { frames.removeAll() }

    private func ago(_ n: Int) -> CIImage? { frames.count > n ? frames[frames.count - 1 - n] : nil }

    /// Two delayed copies standing either side of you.
    func clones() -> CIImage {
        let offset = canvasSize.width * 0.27
        var out = CIImage.empty()
        if let a = ago(8) { out = a.transformed(by: CGAffineTransform(translationX: -offset, y: 0)).composited(over: out) }
        if let b = ago(16) { out = b.transformed(by: CGAffineTransform(translationX: offset, y: 0)).composited(over: out) }
        return out.cropped(to: canvasRect)
    }

    /// Fading echoes of where you just were; oldest is faintest.
    func trail() -> CIImage {
        var out = CIImage.empty()
        for (k, n) in [16, 12, 8, 4].enumerated() {
            guard let f = ago(n) else { continue }
            let tinted = f.applyingFilter("CIColorMonochrome", parameters: [
                kCIInputColorKey: CIColor(red: 0.5, green: 0.8, blue: 1), kCIInputIntensityKey: 0.6])
            out = tinted.withAlpha(0.18 + CGFloat(k) * 0.12).composited(over: out)
        }
        return out
    }
}

/// A glowing outline around the person that slowly cycles through colors.
func neonOutline(mask: CIImage, time: Double) -> CIImage {
    let grown = mask.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 7])
    let ring = grown.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: mask])
    let hue = CGFloat((time * 0.15).truncatingRemainder(dividingBy: 1))
    let c = NSColor(hue: hue, saturation: 0.9, brightness: 1, alpha: 1).usingColorSpace(.sRGB)!
    let line = CIImage(color: CIColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent))
        .cropped(to: canvasRect)
        .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: ring])
    let glow = line.clampedToExtent().applyingGaussianBlur(sigma: 12).cropped(to: canvasRect)
    return line.composited(over: glow.composited(over: glow))
}

// MARK: - Face fun

/// Pixelates faces or puts a black bar over the eyes, news "anonymous source" style.
func witnessProtection(_ img: CIImage, faces: [TrackedFace], mode: WitnessMode) -> CIImage {
    var out = img
    for f in faces {
        switch mode {
        case .off:
            return img
        case .pixelate:
            let r = f.rect.insetBy(dx: -f.rect.width * 0.2, dy: -f.rect.height * 0.3).intersection(canvasRect)
            out = img.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: max(14, f.rect.width / 7), kCIInputCenterKey: CIVector(x: r.midX, y: r.midY)])
                .cropped(to: r)
                .composited(over: out)
        case .eyeBar:
            let eyes = f.eyes
            let center = CGPoint(x: (eyes[0].x + eyes[1].x) / 2, y: (eyes[0].y + eyes[1].y) / 2)
            let angle = atan2(eyes[1].y - eyes[0].y, eyes[1].x - eyes[0].x)
            let w = f.rect.width * 1.3, h = f.rect.height * 0.2
            out = CIImage(color: .black)
                .cropped(to: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                .transformed(by: CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                .composited(over: out)
        }
    }
    return out
}

private let laserBeam: CIImage = {
    let w = 1024, h = 48
    let cg = makeImage(width: w, height: h) { ctx in
        let H = CGFloat(h)
        // Across the beam: transparent → red → white-hot core → red → transparent.
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(1, 0, 0, 0), rgb(1, 0.1, 0.05, 0.9), rgb(1, 0.95, 0.9, 1), rgb(1, 0.1, 0.05, 0.9), rgb(1, 0, 0, 0)].map(\.cgColor) as CFArray,
                           locations: [0, 0.3, 0.5, 0.7, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        // Fade out along its length.
        ctx.setBlendMode(.destinationIn)
        linearGradient(ctx, [rgb(1, 1, 1, 1), rgb(1, 1, 1, 0)], from: .zero, to: CGPoint(x: CGFloat(w), y: 0))
    }
    return CIImage(cgImage: cg)
}()

/// Red laser beams shooting from each eye, following head tilt.
func laserEyes(_ img: CIImage, faces: [TrackedFace], time: Double) -> CIImage {
    var out = img
    let flicker = 0.85 + 0.15 * sin(time * 45)
    for f in faces {
        let eyes = f.eyes.sorted { $0.x < $1.x }
        for (k, eye) in eyes.enumerated() {
            // Left eye fires down-left, right eye down-right.
            let angle = (k == 0 ? CGFloat.pi * 1.15 : -CGFloat.pi * 0.15) + f.roll
            let thickness = max(0.4, f.rect.width / 260) * flicker
            let beam = laserBeam
                .transformed(by: CGAffineTransform(translationX: 0, y: -24)
                    .concatenating(CGAffineTransform(scaleX: 1.6, y: thickness))
                    .concatenating(CGAffineTransform(rotationAngle: angle))
                    .concatenating(CGAffineTransform(translationX: eye.x, y: eye.y)))
            let r = f.rect.width * 0.16 * flicker
            let glow = CIFilter(name: "CIRadialGradient", parameters: [
                kCIInputCenterKey: CIVector(x: eye.x, y: eye.y), "inputRadius0": 0, "inputRadius1": r,
                "inputColor0": CIColor(red: 1, green: 0.95, blue: 0.9, alpha: 1), "inputColor1": CIColor(red: 1, green: 0, blue: 0, alpha: 0)])!
                .outputImage!.cropped(to: CGRect(x: eye.x - r, y: eye.y - r, width: r * 2, height: r * 2))
            out = glow.composited(over: beam.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out]))
        }
    }
    return out.cropped(to: canvasRect)
}

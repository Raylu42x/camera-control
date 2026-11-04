import AppKit
import CoreImage

/// Animates between the live video and a card (camera off, be right back, starting soon).
/// `progress` runs 0 (all video) → 1 (all card).
func transition(_ style: OffStyle, progress raw: Double, video: CIImage, card: CIImage, time: Double, looks: Looks) -> CIImage {
    if raw >= 1 { return card }
    if raw <= 0 { return video }
    let p = CGFloat(raw * raw * (3 - 2 * raw))   // smoothstep
    let W = canvasSize.width, H = canvasSize.height
    let center = CGPoint(x: W / 2, y: H / 2)
    let black = CIImage.black.cropped(to: canvasRect)

    switch style {
    case .fade:
        return video.dissolve(to: card, p)

    case .tvOff:
        // Squash to a bright line, shrink the line to a dot, then fade into the card.
        let sy = max(0.004, 1 - min(1, p / 0.6))
        let sx = p < 0.6 ? 1 : max(0.003, 1 - (p - 0.6) / 0.35)
        var tv = video.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: p * 2.5])
            .transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(scaleX: sx, y: sy))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            .composited(over: black)
        if p > 0.55 {
            let r = 60 * (1 - p) / 0.45
            tv = softDot(radius: max(r, 1), color: CIColor(red: 0.9, green: 0.95, blue: 1, alpha: 1))
                .transformed(by: CGAffineTransform(translationX: center.x - r, y: center.y - r))
                .composited(over: tv)
        }
        return (p > 0.9 ? tv.dissolve(to: card, (p - 0.9) / 0.1) : tv).cropped(to: canvasRect)

    case .glitch:
        // Increasingly broken signal, flickering to the card more and more often.
        var rng = SeededRandom(seed: UInt64(time * 20))
        if rng.next() < p * p { return card }
        return looks.glitch(video, intensity: Double(0.4 + p), time: time)

    case .pixels:
        let px = video.clampedToExtent().applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: 1 + p * p * 90, kCIInputCenterKey: CIVector(x: center.x, y: center.y)])
            .cropped(to: canvasRect)
        return p > 0.7 ? px.dissolve(to: card, (p - 0.7) / 0.3) : px

    case .iris:
        let r = (1 - p) * hypot(W, H) / 2
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: center.x, y: center.y), "inputRadius0": max(0, r - 2), "inputRadius1": max(1, r),
            "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: canvasRect)
        return video.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: card, kCIInputMaskImageKey: mask])

    case .spin:
        let t = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: p * .pi * 3))
            .concatenating(CGAffineTransform(scaleX: max(0.001, 1 - p), y: max(0.001, 1 - p)))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return video.transformed(by: t).composited(over: card).cropped(to: canvasRect)
    }
}

/// Slowly shifting two-color gradient behind the "starting soon" countdown.
func startingSoonBackdrop(time: Double) -> CIImage {
    func color(_ hue: Double) -> CIColor {
        let c = NSColor(hue: CGFloat(hue.truncatingRemainder(dividingBy: 1)), saturation: 0.7, brightness: 0.75, alpha: 1)
            .usingColorSpace(.sRGB)!
        return CIColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }
    let h = time * 0.02
    return CIFilter(name: "CILinearGradient", parameters: [
        "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: canvasSize.width, y: canvasSize.height),
        "inputColor0": color(h), "inputColor1": color(h + 0.25)])!.outputImage!.cropped(to: canvasRect)
}

extension CIImage {
    func dissolve(to target: CIImage, _ t: CGFloat) -> CIImage {
        applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: target, kCIInputTimeKey: min(1, max(0, t))])
    }
}

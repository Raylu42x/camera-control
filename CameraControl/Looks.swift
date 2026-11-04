import AppKit
import CoreImage

/// The heavier stylized looks: old film, glitch, ASCII art and halftone print.
final class Looks {
    static let asciiCell: CGFloat = 12
    private static let asciiChars = Array(" .:-=+*#%@")

    /// One infinitely tiled layer per character (white on black, dark → bright), aligned
    /// to the cell grid at the origin.
    private lazy var glyphTiles: [CIImage] = Self.asciiChars.map { ch in
        let c = Self.asciiCell
        let cg = makeImage(width: Int(c), height: Int(c)) { ctx in
            fill(ctx, CGRect(x: 0, y: 0, width: c, height: c), .black)
            drawText(String(ch), in: CGRect(x: 0, y: 0, width: c, height: c),
                     font: NSFont.monospacedSystemFont(ofSize: c * 1.05, weight: .bold), color: .white, center: true)
        }
        return CIImage(cgImage: cg).applyingFilter("CIAffineTile", parameters: [kCIInputTransformKey: CGAffineTransform.identity])
    }

    func oldFilm(_ img: CIImage, intensity i: Double, time: Double) -> CIImage {
        var rng = SeededRandom(seed: UInt64(time * 24))
        let W = canvasSize.width, H = canvasSize.height
        var out = img
            .applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.6 + i * 0.4])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: (rng.next() - 0.5) * 0.35 * i])
            .applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: W / 2, y: H / 2), kCIInputRadiusKey: 760,
                kCIInputIntensityKey: 0.9, "inputFalloff": 0.5])
            // Gate weave: the frame wobbles a little, like film in a projector.
            .transformed(by: CGAffineTransform(translationX: 0, y: (rng.next() - 0.5) * 5 * i))
        for _ in 0..<Int(1 + rng.next() * 3 * i) {
            let scratch = CIImage(color: CIColor(red: 1, green: 0.97, blue: 0.85, alpha: 0.35))
                .cropped(to: CGRect(x: rng.next() * W, y: 0, width: 1.5, height: H))
            out = scratch.composited(over: out)
        }
        for _ in 0..<Int(rng.next() * 7 * i) {
            let center = CIVector(x: rng.next() * W, y: rng.next() * H)
            let r = 1 + rng.next() * 4
            let speck = CIFilter(name: "CIRadialGradient", parameters: [
                kCIInputCenterKey: center, "inputRadius0": 0, "inputRadius1": r,
                "inputColor0": CIColor(red: 0.05, green: 0.03, blue: 0, alpha: 0.8), "inputColor1": CIColor.clear])!
                .outputImage!.cropped(to: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            out = speck.composited(over: out)
        }
        return grain(over: out, amount: 0.05 + i * 0.07, rng: &rng).cropped(to: canvasRect)
    }

    func glitch(_ img: CIImage, intensity i: Double, time: Double) -> CIImage {
        var rng = SeededRandom(seed: UInt64(time * 14))
        let W = canvasSize.width, H = canvasSize.height
        let burst = rng.next() < 0.15 + i * 0.35
        let shift = (burst ? 16 : 4) * (0.5 + i)
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, dx: CGFloat) -> CIImage {
            img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputBiasVector": zero])
                .transformed(by: CGAffineTransform(translationX: dx, y: 0))
        }
        var out = channel(1, 0, 0, dx: shift)
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: channel(0, 1, 0, dx: 0)])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: channel(0, 0, 1, dx: -shift)])
            .cropped(to: canvasRect)
        if burst {
            // Tear horizontal bands sideways.
            for _ in 0..<Int(3 + rng.next() * 7 * i) {
                let band = CGRect(x: 0, y: rng.next() * H, width: W, height: 6 + rng.next() * 60)
                out = out.cropped(to: band)
                    .transformed(by: CGAffineTransform(translationX: (rng.next() - 0.5) * 180 * i, y: 0))
                    .composited(over: out)
            }
            if rng.next() < 0.4 {
                let block = CGRect(x: rng.next() * W, y: rng.next() * H, width: 80 + rng.next() * 320, height: 10 + rng.next() * 40)
                out = img.cropped(to: block).applyingFilter("CIColorInvert").composited(over: out)
            }
        }
        return out.cropped(to: canvasRect)
    }

    /// ASCII art from stock filters: average each cell, bucket its brightness into one
    /// level per character, and stamp that character's tile through the level's mask.
    /// Strength blends the tint from terminal green to the video's own colors.
    func ascii(_ img: CIImage, intensity i: Double) -> CIImage {
        let c = Self.asciiCell
        // Shrink so one pixel = one cell, then blow back up with hard edges on the grid.
        let cells = img.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 1 / c, kCIInputAspectRatioKey: 1])
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: c, y: c))
            .cropped(to: canvasRect)
        let lum = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        let gray = cells.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": lum, "inputGVector": lum, "inputBVector": lum, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        // 1 where brightness > t, else 0.
        func above(_ t: CGFloat) -> CIImage {
            let gain: CGFloat = 1000
            return gray.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0), "inputBiasVector": CIVector(x: -t * gain, y: -t * gain, z: -t * gain, w: 0)])
                .applyingFilter("CIColorClamp")
        }
        let n = glyphTiles.count
        var glyphs = CIImage.black.cropped(to: canvasRect)
        // Level 0 is the space character, so start at 1.
        for k in 1..<n {
            let low = above(CGFloat(k) / CGFloat(n))
            let mask = k == n - 1 ? low : low.applyingFilter("CIDifferenceBlendMode", parameters: [
                kCIInputBackgroundImageKey: above(CGFloat(k + 1) / CGFloat(n))])
            let stamped = glyphTiles[k].applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
            glyphs = stamped.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: glyphs])
        }
        let green = CIImage(color: CIColor(red: 0.2, green: 1, blue: 0.4)).cropped(to: canvasRect)
        let tint = cells.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.6])
            .applyingFilter("CIMix", parameters: [kCIInputBackgroundImageKey: green, kCIInputAmountKey: i])
        return glyphs.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: tint])
            .cropped(to: canvasRect)
    }

    func halftone(_ img: CIImage, intensity i: Double) -> CIImage {
        img.applyingFilter("CICMYKHalftone", parameters: [
            kCIInputWidthKey: 5 + i * 14, kCIInputAngleKey: 0.3, kCIInputSharpnessKey: 0.75,
            kCIInputCenterKey: CIVector(x: canvasSize.width / 2, y: canvasSize.height / 2),
            "inputGCR": 1, "inputUCR": 0.5])
            .cropped(to: canvasRect)
    }
}

/// Film-style noise laid over `img`; a fresh random offset each frame keeps it alive.
func grain(over img: CIImage, amount: Double, rng: inout SeededRandom) -> CIImage {
    guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return img }
    let one = CIVector(x: 1, y: 0, z: 0, w: 0)
    return noise.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": one, "inputGVector": one, "inputBVector": one,
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: amount)])
        .transformed(by: CGAffineTransform(translationX: rng.next() * 500, y: rng.next() * 500))
        .cropped(to: canvasRect)
        .composited(over: img)
}

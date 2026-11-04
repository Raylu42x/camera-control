import CoreImage
import CoreMedia
import CoreVideo
import Metal
import QuartzCore

/// Turns raw camera frames into the finished 1280×720 output. Runs on the camera queue;
/// settings arrive from the main thread through `update(_:)`.
final class Pipeline {
    let ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [.cacheIntermediates: false])
    let particles = ParticleSystem()
    /// Called about once a second with the output frame rate and the average
    /// camera-to-finished-frame latency in milliseconds.
    var onStats: ((_ fps: Int, _ latencyMs: Int) -> Void)?

    private let lock = NSLock()
    private var _settings = EffectSettings.load()
    private var _customBackground: CIImage?

    private let segmenter = Segmenter()
    private let faces = FaceTracker()
    private let overlays = OverlayRenderer()
    private var pool: CVPixelBufferPool?
    private var previous = EffectSettings()
    /// Frame captured when freeze or "be right back" is switched on.
    private var held: CIImage?
    private var heldBackdrop: CIImage?
    private var newsShownAt: Double = 0
    private var frameCount = 0
    private var latencySum = 0.0
    private var fpsWindowStart = CACurrentMediaTime()
    private let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var settings: EffectSettings { lock.withLock { _settings } }

    func update(_ s: EffectSettings) { lock.withLock { _settings = s } }

    func setCustomBackground(_ cg: CGImage?) {
        let img = cg.map { CIImage(cgImage: $0).aspectFill(canvasRect) }
        lock.withLock { _customBackground = img }
    }

    func process(_ input: CVPixelBuffer, captured: CMTime) -> CVPixelBuffer? {
        let s = settings
        let now = CACurrentMediaTime()
        defer {
            previous = s
            countFrame(now, latency: (CMClockGetTime(CMClockGetHostTimeClock()) - captured).seconds)
        }

        // 1. Camera: fill the canvas, zoom, mirror, color adjust.
        var cam = CIImage(cvPixelBuffer: input).aspectFill(canvasRect, zoom: s.zoom)
        if s.mirror {
            cam = cam.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -canvasSize.width, y: 0))
        }
        if s.brightness != 0 || s.contrast != 1 || s.saturation != 1 {
            cam = cam.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: s.brightness, kCIInputContrastKey: s.contrast, kCIInputSaturationKey: s.saturation])
        }

        if s.sticker != .none || s.filter.isDistortion {
            faces.update(with: cam)
        } else {
            faces.clear()
        }

        // 2. Background replacement behind the person.
        var base = cam
        if s.backgroundMode != .none, let mask = segmenter.mask(for: cam) {
            let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: canvasRect)
            base = cam.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background(for: s, camera: cam), kCIInputMaskImageKey: soft])
        }

        // 3. Look filter and face stickers.
        base = applyFilter(base, s, time: now)
        if s.sticker != .none {
            base = stickers(s.sticker, over: base)
        }

        // 4. Freeze / be right back.
        if (s.freeze && !previous.freeze) || (s.blank && !previous.blank) {
            held = snapshot(base)
            heldBackdrop = held.flatMap {
                snapshot($0.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: canvasRect)
                    .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.0]))
            }
        }
        if s.freeze, let held { base = held }
        if s.blank {
            base = overlays.holdCard(title: s.blankTitle, subtitle: s.blankSubtitle)
                .composited(over: heldBackdrop ?? overlays.holdBackdrop())
        }

        // 5. Broadcast graphics, captions, reactions.
        var out = base
        var lowerThirdTop: CGFloat = 0
        if s.newsEnabled {
            if !previous.newsEnabled { newsShownAt = now }
            if s.tickerEnabled, !s.tickerText.isEmpty {
                out = overlays.ticker(text: s.tickerText, time: now).composited(over: out)
            }
            let lt = overlays.lowerThird(tag: s.newsTag, name: s.newsName, title: s.newsTitle)
            let t = min(1, (now - newsShownAt) / 0.45)
            let ease = 1 - pow(1 - t, 3)
            let x = 50 - (1 - ease) * (lt.extent.width + 60)
            let y = s.tickerEnabled ? OverlayRenderer.tickerHeight + 4 : 24
            out = lt.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: out)
            lowerThirdTop = y + lt.extent.height
            if s.showLiveBug {
                let bug = overlays.liveBug(channel: s.channelName, clock: clockFormatter.string(from: Date()))
                out = bug.transformed(by: CGAffineTransform(translationX: 40, y: canvasSize.height - 40 - bug.extent.height))
                    .composited(over: out)
            }
        }
        if s.captionEnabled, !s.captionText.isEmpty {
            let cap = overlays.caption(s.captionText)
            let y = s.captionPosition == .top
                ? canvasSize.height - (s.newsEnabled && s.showLiveBug ? 100 : 44) - cap.extent.height
                : max(44, lowerThirdTop + 16)
            out = cap.transformed(by: CGAffineTransform(translationX: (canvasSize.width - cap.extent.width) / 2, y: y))
                .composited(over: out)
        }
        out = particles.render(over: out)

        return render(out.cropped(to: canvasRect).composited(over: CIImage.black.cropped(to: canvasRect)))
    }

    // MARK: - Pieces

    private func background(for s: EffectSettings, camera: CIImage) -> CIImage {
        switch s.backgroundMode {
        case .none, .blur:
            return camera.clampedToExtent().applyingGaussianBlur(sigma: s.blurRadius).cropped(to: canvasRect)
        case .preset:
            return Backgrounds.image(s.backgroundPreset)
        case .color:
            let c = s.backgroundColor
            return CIImage(color: CIColor(red: c.r, green: c.g, blue: c.b)).cropped(to: canvasRect)
        case .custom:
            return lock.withLock { _customBackground } ?? Backgrounds.image(.newsStudio)
        }
    }

    private func applyFilter(_ img: CIImage, _ s: EffectSettings, time: Double) -> CIImage {
        let i = s.filterIntensity
        let face = faces.faces.first?.rect
        let faceCenter = CIVector(x: face?.midX ?? canvasSize.width / 2, y: face?.midY ?? canvasSize.height / 2)
        let faceW = face?.width ?? 300
        let canvasCenter = CIVector(x: canvasSize.width / 2, y: canvasSize.height / 2)
        // Blend a full-strength effect with the original by the intensity slider.
        func mix(_ name: String) -> CIImage {
            img.applyingFilter(name).applyingFilter("CIMix", parameters: [
                kCIInputBackgroundImageKey: img, kCIInputAmountKey: 0.25 + i * 0.75])
        }

        let out: CIImage
        switch s.filter {
        case .none: return img
        case .mono: out = mix("CIPhotoEffectMono")
        case .noir: out = mix("CIPhotoEffectNoir")
        case .sepia: out = img.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: i])
        case .comic: out = mix("CIComicEffect")
        case .thermal: out = mix("CIThermal")
        case .xray: out = mix("CIXRay")
        case .invert: out = mix("CIColorInvert")
        case .pixelate:
            out = img.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: 6 + i * 40, kCIInputCenterKey: canvasCenter])
        case .posterize:
            out = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.8])
                .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 2 + (1 - i) * 8])
        case .crystallize:
            out = img.clampedToExtent().applyingFilter("CICrystallize", parameters: [
                kCIInputRadiusKey: 6 + i * 40, kCIInputCenterKey: canvasCenter])
        case .kaleidoscope:
            out = img.applyingFilter("CIKaleidoscope", parameters: [
                "inputCount": 6, kCIInputCenterKey: canvasCenter, kCIInputAngleKey: time * 0.4 * i])
        case .bloom:
            out = img.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 14, kCIInputIntensityKey: i * 1.6])
        case .vhs: out = vhs(img, intensity: i)
        case .edges:
            out = img.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3 + i * 12])
                .applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: time])
        case .twirl:
            out = img.clampedToExtent().applyingFilter("CITwirlDistortion", parameters: [
                kCIInputCenterKey: faceCenter, kCIInputRadiusKey: faceW * 1.6, kCIInputAngleKey: i * .pi * 3])
        case .bulge:
            out = img.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: faceCenter, kCIInputRadiusKey: faceW * 1.1, kCIInputScaleKey: 0.2 + i * 0.7])
        case .pinch:
            out = img.clampedToExtent().applyingFilter("CIPinchDistortion", parameters: [
                kCIInputCenterKey: faceCenter, kCIInputRadiusKey: faceW * 1.3, kCIInputScaleKey: 0.2 + i * 1.3])
        }
        return out.cropped(to: canvasRect)
    }

    private func vhs(_ img: CIImage, intensity i: Double) -> CIImage {
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let shift = 3 + i * 10
        let red = img.applyingFilter("CIColorMatrix", parameters: ["inputGVector": zero, "inputBVector": zero])
            .transformed(by: CGAffineTransform(translationX: shift, y: 0))
        let cyan = img.applyingFilter("CIColorMatrix", parameters: ["inputRVector": zero])
            .transformed(by: CGAffineTransform(translationX: -shift / 2, y: 0))
        var out = red.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: cyan])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
            .cropped(to: canvasRect)
        if let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0.18 + i * 0.25),
            "inputColor1": CIColor.clear, "inputWidth": 2.0, "inputSharpness": 1.0])?.outputImage {
            out = stripes.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: canvasRect).composited(over: out)
        }
        if let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let one = CIVector(x: 1, y: 0, z: 0, w: 0)
            let grain = noise.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": one, "inputGVector": one, "inputBVector": one, "inputAVector": zero,
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0.04 + i * 0.08)])
                .transformed(by: CGAffineTransform(translationX: .random(in: 0...500), y: .random(in: 0...500)))
                .cropped(to: canvasRect)
            out = grain.composited(over: out)
        }
        return out
    }

    private func stickers(_ sticker: Sticker, over img: CIImage) -> CIImage {
        var out = img
        let sprite = EmojiCache.shared.image(sticker.emoji)
        for f in faces.faces {
            let r = f.rect
            let anchor: CGPoint, width: CGFloat
            switch sticker.placement {
            case .eyes: anchor = CGPoint(x: r.midX, y: r.minY + r.height * 0.6); width = r.width * 1.15
            case .hat: anchor = CGPoint(x: r.midX, y: r.maxY + r.width * 0.28); width = r.width * 1.05
            case .nose: anchor = CGPoint(x: r.midX, y: r.minY + r.height * 0.38); width = r.width * 0.32
            case .face: anchor = CGPoint(x: r.midX, y: r.midY + r.height * 0.05); width = r.width * 1.6
            }
            // Rotate the anchor around the face center so stickers follow head tilt.
            let c = CGPoint(x: r.midX, y: r.midY)
            let dx = anchor.x - c.x, dy = anchor.y - c.y
            let p = CGPoint(x: c.x + dx * cos(f.roll) - dy * sin(f.roll), y: c.y + dx * sin(f.roll) + dy * cos(f.roll))
            out = sprite.placed(center: p, width: width, rotation: f.roll).composited(over: out)
        }
        return out
    }

    private func snapshot(_ img: CIImage) -> CIImage? {
        ciContext.createCGImage(img, from: canvasRect).map { CIImage(cgImage: $0) }
    }

    private func render(_ img: CIImage) -> CVPixelBuffer? {
        if pool == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(canvasSize.width),
                kCVPixelBufferHeightKey: Int(canvasSize.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey: true,
            ]
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let pb else { return nil }
        // Tag the surface as sRGB so Core Animation shows it with the right colors.
        if let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, CGColorSpace.sRGB)
        }
        ciContext.render(img, to: pb, bounds: canvasRect, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return pb
    }

    private func countFrame(_ now: Double, latency: Double) {
        frameCount += 1
        latencySum += latency
        if now - fpsWindowStart >= 1 {
            onStats?(Int(Double(frameCount) / (now - fpsWindowStart) + 0.5), Int(latencySum / Double(frameCount) * 1000))
            frameCount = 0
            latencySum = 0
            fpsWindowStart = now
        }
    }
}

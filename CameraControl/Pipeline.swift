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
    let screen = ScreenSource()
    /// Called about once a second with the output frame rate and the average
    /// camera-to-finished-frame latency in milliseconds.
    var onStats: ((_ fps: Int, _ latencyMs: Int) -> Void)?

    private let lock = NSLock()
    private var _settings = EffectSettings.load()
    private var _customBackground: CIImage?

    private let segmenter = Segmenter()
    private let faces = FaceTracker()
    private let overlays = OverlayRenderer()
    private let looks = Looks()
    private let scenes = AnimatedScenes()
    private let history = FrameHistory()
    private var pool: CVPixelBufferPool?
    private var lastFrameTime: Double?
    /// Smoothed point the zoom is centered on (auto-framing).
    private var frameCenter: CGPoint?
    /// 0 = showing video, 1 = showing the card; animated by the transition style.
    private var cardProgress = 0.0
    private var cardKind = CardKind.off
    private var countdownStart = 0.0
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

    private var _snapshotURL: URL?

    var settings: EffectSettings { lock.withLock { _settings } }

    /// Saves the next finished frame as a PNG at `url`.
    func snapshot(to url: URL) { lock.withLock { _snapshotURL = url } }

    func update(_ s: EffectSettings) { lock.withLock { _settings = s } }

    func setCustomBackground(_ cg: CGImage?) {
        let img = cg.map { CIImage(cgImage: $0).aspectFill(canvasRect) }
        lock.withLock { _customBackground = img }
    }

    func process(_ input: CVPixelBuffer, captured: CMTime) -> CVPixelBuffer? {
        let s = settings
        let now = CACurrentMediaTime()
        let dt = min(now - (lastFrameTime ?? now), 0.1)
        lastFrameTime = now
        defer {
            previous = s
            countFrame(now, latency: (CMClockGetTime(CMClockGetHostTimeClock()) - captured).seconds)
        }

        // 1. Camera: fill the canvas, mirror, color adjust, then zoom / auto-frame. Mirroring
        // flips only the camera image, so the output (and OBS/Zoom) is mirrored while text
        // and graphics drawn later stay readable.
        var full = CIImage(cvPixelBuffer: input).aspectFill(canvasRect)
        if s.mirror {
            full = full.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -canvasSize.width, y: 0))
        }
        if s.brightness != 0 || s.contrast != 1 || s.saturation != 1 {
            full = full.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: s.brightness, kCIInputContrastKey: s.contrast, kCIInputSaturationKey: s.saturation])
        }
        let needFaces = s.sticker != .none || s.filter.isDistortion || s.laserEyes || s.witness != .off || s.autoFrame
        // Auto-framing needs faces from the whole frame before deciding where to zoom.
        if s.autoFrame { faces.update(with: full) }
        let frame = framing(s, face: s.autoFrame ? faces.raw.first : nil)
        let cam = frame.isIdentity ? full : full.transformed(by: frame).cropped(to: canvasRect)
        if s.autoFrame {
            faces.apply(frame)
        } else if needFaces {
            faces.update(with: cam)
        } else {
            faces.clear()
        }

        // 2. You vs. background: replacement scenes and person effects.
        var base = cam
        let fx = s.personEffect
        if s.backgroundMode != .none || fx != .none, let mask = segmenter.mask(for: cam) {
            var soft = mask.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: canvasRect)
            var person = cam.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: soft])
            var backdrop = s.backgroundMode == .none ? cam : background(for: s, camera: cam, time: now)
            if fx == .colorPop { backdrop = backdrop.applyingFilter("CIPhotoEffectNoir") }
            if fx == .clones || fx == .ghostTrail {
                history.push(person, context: ciContext)
                backdrop = (fx == .clones ? history.clones() : history.trail()).composited(over: backdrop)
            } else {
                history.clear()
            }
            if s.backgroundMode == .screen && s.presenterSmall {
                // Presenter mode: you shrink into the bottom-right corner over the screen.
                let k: CGFloat = 0.42
                let corner = CGAffineTransform(scaleX: k, y: k)
                    .concatenating(CGAffineTransform(translationX: canvasSize.width * (1 - k) - 24, y: 24))
                person = person.transformed(by: corner)
                soft = soft.transformed(by: corner)
                faces.apply(s.autoFrame ? frame.concatenating(corner) : corner)
            }
            base = person.composited(over: backdrop)
            if fx == .neonOutline { base = neonOutline(mask: soft, time: now).composited(over: base) }
            base = base.cropped(to: canvasRect)
        } else {
            history.clear()
        }

        // 3. Look filter, then face effects on top.
        base = applyFilter(base, s, time: now)
        if s.witness != .off { base = witnessProtection(base, faces: faces.faces, mode: s.witness) }
        if s.sticker != .none { base = stickers(s.sticker, over: base) }
        if s.laserEyes { base = laserEyes(base, faces: faces.faces, time: now) }

        // 4. Freeze, and cards (camera off / be right back / starting soon) with transitions.
        let cardTurnedOn = s.showsCard && !previous.showsCard
        if (s.freeze && !previous.freeze) || cardTurnedOn {
            held = snapshot(base)
            heldBackdrop = held.flatMap {
                snapshot($0.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: canvasRect)
                    .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.0]))
            }
        }
        if s.freeze, let held { base = held }
        if s.startingSoon && !previous.startingSoon { countdownStart = now }
        if s.showsCard { cardKind = s.startingSoon ? .startingSoon : s.blank ? .beRightBack : .off }
        let step = dt / 0.8
        cardProgress = s.showsCard ? min(1, cardProgress + step) : max(0, cardProgress - step)
        if cardProgress > 0 {
            base = transition(s.offStyle, progress: cardProgress, video: base, card: card(cardKind, s, time: now),
                              time: now, looks: looks)
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
        let final = out.cropped(to: canvasRect).composited(over: CIImage.black.cropped(to: canvasRect))

        if let url = lock.withLock({ defer { _snapshotURL = nil }; return _snapshotURL }) {
            try? ciContext.writePNGRepresentation(of: final, to: url, format: .RGBA8,
                                                  colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        return render(final)
    }

    // MARK: - Pieces

    private enum CardKind { case off, beRightBack, startingSoon }

    private func card(_ kind: CardKind, _ s: EffectSettings, time: Double) -> CIImage {
        switch kind {
        case .off:
            return overlays.offCard()
        case .beRightBack:
            return overlays.holdCard(title: s.blankTitle, subtitle: s.blankSubtitle)
                .composited(over: heldBackdrop ?? overlays.holdBackdrop())
        case .startingSoon:
            let left = max(0, Double(s.countdownMinutes * 60) - (time - countdownStart))
            let clock = left > 0 ? String(format: "%d:%02d", Int(left) / 60, Int(left) % 60) : "Now!"
            return overlays.startingSoon(title: s.startingSoonTitle, clock: clock, subtitle: s.startingSoonSubtitle)
                .composited(over: startingSoonBackdrop(time: time))
        }
    }

    /// Zoom transform; with auto-framing it glides to keep your face in frame.
    private func framing(_ s: EffectSettings, face: TrackedFace?) -> CGAffineTransform {
        let W = canvasSize.width, H = canvasSize.height
        let z = s.autoFrame ? max(s.zoom, 1.6) : s.zoom
        var target = CGPoint(x: W / 2, y: H / 2)
        if s.autoFrame, let f = face {
            // Aim a little below the face so it sits in the upper part of the frame.
            target = CGPoint(x: f.rect.midX, y: f.rect.midY - f.rect.height * 0.2)
        }
        let c = frameCenter.map { CGPoint(x: $0.x + (target.x - $0.x) * 0.08, y: $0.y + (target.y - $0.y) * 0.08) } ?? target
        frameCenter = c
        guard z > 1.001 else { return .identity }
        let tx = min(0, max(W - W * z, W / 2 - c.x * z))
        let ty = min(0, max(H - H * z, H / 2 - c.y * z))
        return CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: tx, ty: ty)
    }

    private func background(for s: EffectSettings, camera: CIImage, time: Double) -> CIImage {
        switch s.backgroundMode {
        case .none, .blur:
            return camera.clampedToExtent().applyingGaussianBlur(sigma: s.blurRadius).cropped(to: canvasRect)
        case .preset:
            return s.backgroundPreset.isAnimated ? scenes.image(s.backgroundPreset, time: time) : Backgrounds.image(s.backgroundPreset)
        case .screen:
            if let screen = screen.image { return screen.aspectFill(canvasRect) }
            return overlays.message(screen.failed
                ? "Allow Screen Recording for Camera Control in System Settings → Privacy & Security"
                : "Starting screen capture…")
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
        case .oldFilm: return looks.oldFilm(img, intensity: i, time: time)
        case .glitch: return looks.glitch(img, intensity: i, time: time)
        case .ascii: return looks.ascii(img, intensity: i)
        case .halftone: return looks.halftone(img, intensity: i)
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

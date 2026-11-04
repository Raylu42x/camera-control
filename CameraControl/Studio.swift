import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App-wide state: settings the UI edits, the camera, and the processing pipeline.
@MainActor
final class Studio: ObservableObject {
    @Published var settings: EffectSettings {
        didSet {
            guard settings != oldValue else { return }
            pipeline.update(settings)
            settings.save()
            if settings.backgroundMode != oldValue.backgroundMode { updateScreenCapture() }
        }
    }
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedDeviceID = UserDefaults.standard.string(forKey: "cameraID") ?? "" {
        didSet {
            UserDefaults.standard.set(selectedDeviceID, forKey: "cameraID")
            camera.select(deviceID: selectedDeviceID)
        }
    }
    @Published var cameraDenied = false
    @Published var fps = 0
    @Published var latencyMs = 0
    @Published var customBackgroundName: String?

    let camera = CameraManager()
    let pipeline = Pipeline()
    let frames = FrameStore()
    private var thumbnailCache: [BackgroundPreset: NSImage] = [:]

    init() {
        settings = pipeline.settings
        let pipeline = pipeline, frames = frames
        camera.onFrame = { pb, captured in
            if let out = pipeline.process(pb, captured: captured) { frames.publish(out) }
        }
        pipeline.onStats = { [weak self] fps, latency in
            DispatchQueue.main.async {
                self?.fps = fps
                self?.latencyMs = latency
            }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDevices() }
            }
        }
    }

    func start() async {
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if !granted { granted = await AVCaptureDevice.requestAccess(for: .video) }
        cameraDenied = !granted
        guard granted else { return }
        refreshDevices()
        if !devices.contains(where: { $0.uniqueID == selectedDeviceID }), let first = devices.first {
            selectedDeviceID = first.uniqueID
        } else {
            camera.select(deviceID: selectedDeviceID)
        }
        updateScreenCapture()
        runLaunchSnapshotIfRequested()
    }

    func refreshDevices() {
        devices = CameraManager.availableDevices()
    }

    /// Screen capture runs only while presenter mode is the background.
    private func updateScreenCapture() {
        if settings.backgroundMode == .screen { pipeline.screen.start() } else { pipeline.screen.stop() }
    }

    /// Saves the current output to ~/Pictures/Camera Control and reveals it in Finder.
    func takeSnapshot() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Camera Control", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dir.appendingPathComponent("Snapshot \(f.string(from: Date())).png")
        pipeline.snapshot(to: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Test hook: `--args -snapshotPath <file> [-snapshotDelay <s>] [-turnOn cameraOff|blank|startingSoon]
    /// [-turnOnLead <s>]` launches, optionally switches a card on `turnOnLead` seconds before the
    /// snapshot (default 1.5, i.e. after the transition), saves one frame, and quits.
    private func runLaunchSnapshotIfRequested() {
        let args = UserDefaults.standard
        guard let path = args.string(forKey: "snapshotPath") else { return }
        let delay = args.double(forKey: "snapshotDelay") > 0 ? args.double(forKey: "snapshotDelay") : 5
        let lead = args.double(forKey: "turnOnLead") > 0 ? args.double(forKey: "turnOnLead") : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay - lead) { [self] in
            switch args.string(forKey: "turnOn") {
            case "cameraOff": settings.cameraOff = true
            case "blank": settings.blank = true
            case "startingSoon": settings.startingSoon = true
            default: break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            pipeline.snapshot(to: URL(fileURLWithPath: path))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
    }

    /// One-click weather report: map scene, weather tag, news graphics on.
    func weatherMode() {
        settings.backgroundMode = .preset
        settings.backgroundPreset = .weather
        settings.newsTag = "WEATHER"
        settings.newsTitle = "Your local forecast"
        settings.newsEnabled = true
    }

    func react(_ reaction: Reaction) {
        pipeline.particles.burst(reaction)
    }

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Pick a picture to put behind you"
        guard panel.runModal() == .OK, let url = panel.url,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        pipeline.setCustomBackground(cg)
        customBackgroundName = url.lastPathComponent
        settings.backgroundMode = .custom
    }

    func thumbnail(_ preset: BackgroundPreset) -> NSImage {
        if let img = thumbnailCache[preset] { return img }
        // A private AnimatedScenes so this doesn't share drawing state with the camera queue.
        let full = preset.isAnimated ? AnimatedScenes().image(preset, time: 3) : Backgrounds.image(preset)
        let small = full.transformed(by: CGAffineTransform(scaleX: 0.2, y: 0.2))
        let cg = pipeline.ciContext.createCGImage(small, from: small.extent)!
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnailCache[preset] = img
        return img
    }

    var backgroundColor: Binding<Color> {
        Binding {
            let c = self.settings.backgroundColor
            return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
        } set: { color in
            guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
            self.settings.backgroundColor = RGB(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent)
        }
    }
}

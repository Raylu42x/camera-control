import AVFoundation
import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

/// App-wide state: settings the UI edits, the camera, and the processing pipeline.
@MainActor
final class Studio: ObservableObject {
    /// What the controls edit and the main window previews. With "Preview before applying"
    /// on, changes reach the output (OBS/Zoom) only when you click Apply.
    @Published var settings: EffectSettings {
        didSet {
            guard settings != oldValue else { return }
            previewPipeline.update(settings)
            if previewFirst {
                for key in EffectSettings.liveControls { applied[keyPath: key] = settings[keyPath: key] }
            } else {
                applied = settings
            }
            updatePreviewing()
        }
    }
    /// What the output window shows right now.
    @Published private(set) var applied: EffectSettings {
        didSet {
            guard applied != oldValue else { return }
            pipeline.update(applied)
            applied.save()
        }
    }
    @Published var previewFirst = UserDefaults.standard.object(forKey: "previewBeforeApply") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(previewFirst, forKey: "previewBeforeApply")
            if !previewFirst { apply() }
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
    /// Renders the output; its frames go to the Output window.
    let pipeline: Pipeline
    /// Renders unapplied changes for the main window's preview.
    let previewPipeline: Pipeline
    let frames = FrameStore()
    let previewFrames = FrameStore()
    private let preview = OSAllocatedUnfairLock(initialState: PreviewState())
    private var draftBackground: CGImage?
    private var appliedBackground: CGImage?
    private var thumbnailCache: [BackgroundPreset: NSImage] = [:]

    private struct PreviewState {
        var active = false
        var busy = false
    }

    /// True when the preview shows changes the output doesn't have yet.
    var hasPendingChanges: Bool { settings != applied || draftBackground !== appliedBackground }

    init() {
        let screen = ScreenSource()
        let pipeline = Pipeline(screen: screen), previewPipeline = Pipeline(screen: screen)
        self.pipeline = pipeline
        self.previewPipeline = previewPipeline
        settings = pipeline.settings
        applied = pipeline.settings
        let frames = frames, previewFrames = previewFrames, preview = preview
        let previewQueue = DispatchQueue(label: "preview.frames", qos: .userInitiated)
        camera.onFrame = { pb, captured in
            guard let out = pipeline.process(pb, captured: captured) else { return }
            frames.publish(out)
            // The draft renders on its own queue and skips frames when it falls behind,
            // so previewing never slows down the output.
            let start = preview.withLock { s -> Bool? in
                guard s.active else { return nil }
                guard !s.busy else { return false }
                s.busy = true
                return true
            }
            switch start {
            case nil:
                previewFrames.publish(out)
            case true?:
                previewQueue.async {
                    if let draft = previewPipeline.process(pb, captured: captured) { previewFrames.publish(draft) }
                    preview.withLock { $0.busy = false }
                }
            case false?:
                break
            }
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

    /// Sends the previewed changes to the output.
    func apply() {
        if draftBackground !== appliedBackground {
            appliedBackground = draftBackground
            pipeline.setCustomBackground(appliedBackground)
        }
        applied = settings
        updatePreviewing()
    }

    /// Throws away the previewed changes.
    func revert() {
        if draftBackground !== appliedBackground {
            draftBackground = appliedBackground
            previewPipeline.setCustomBackground(draftBackground)
        }
        settings = applied
        updatePreviewing()
    }

    private func updatePreviewing() {
        let active = hasPendingChanges
        preview.withLock { $0.active = active }
        updateScreenCapture()
    }

    /// Screen capture runs only while presenter mode is the background (previewed or live).
    private func updateScreenCapture() {
        if settings.backgroundMode == .screen || applied.backgroundMode == .screen {
            pipeline.screen.start()
        } else {
            pipeline.screen.stop()
        }
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
    /// [-turnOnLead <s>] [-draft <json>] [-previewSnapshotPath <file>]` launches, optionally previews
    /// the settings in `draft` without applying them, optionally switches a card on `turnOnLead`
    /// seconds before the snapshot (default 1.5, i.e. after the transition), saves one output frame
    /// (and one preview frame), and quits.
    private func runLaunchSnapshotIfRequested() {
        let args = UserDefaults.standard
        guard let path = args.string(forKey: "snapshotPath") else { return }
        // Read raw: the defaults argument domain would parse "{...}" as a property list.
        let argv = ProcessInfo.processInfo.arguments
        if let i = argv.firstIndex(of: "-draft"), i + 1 < argv.count {
            settings = settings.merging(json: argv[i + 1])
        }
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
            if let previewPath = args.string(forKey: "previewSnapshotPath") {
                previewPipeline.snapshot(to: URL(fileURLWithPath: previewPath))
            }
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
        previewPipeline.particles.burst(reaction)
    }

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Pick a picture to put behind you"
        guard panel.runModal() == .OK, let url = panel.url,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        draftBackground = cg
        previewPipeline.setCustomBackground(cg)
        customBackgroundName = url.lastPathComponent
        settings.backgroundMode = .custom
        if previewFirst { updatePreviewing() } else { apply() }
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

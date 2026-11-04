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
    }

    func refreshDevices() {
        devices = CameraManager.availableDevices()
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
        let small = Backgrounds.image(preset).transformed(by: CGAffineTransform(scaleX: 0.2, y: 0.2))
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

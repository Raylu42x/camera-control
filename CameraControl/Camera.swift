import AVFoundation
import AppKit

/// Owns the physical camera and hands each frame to `onFrame` on a background queue.
final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    /// Frame plus its capture time on the host clock (for latency measurement).
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "camera.frames", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var input: AVCaptureDeviceInput?

    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified
        ).devices.filter { !$0.localizedName.contains("Camera Control") }
    }

    override init() {
        super.init()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
    }

    func select(deviceID: String) {
        sessionQueue.async { [self] in
            guard let device = AVCaptureDevice(uniqueID: deviceID) ?? Self.availableDevices().first else { return }
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            input = nil
            if let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) {
                session.addInput(newInput)
                input = newInput
            }
            // 720p keeps effects fast; big 4K webcams would just get scaled down anyway.
            session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = sampleBuffer.imageBuffer else { return }
        var captured = sampleBuffer.presentationTimeStamp
        if let clock = session.synchronizationClock {
            captured = CMSyncConvertTime(captured, from: clock, to: CMClockGetHostTimeClock())
        }
        onFrame?(pb, captured)
    }
}

/// Fans finished frames out to every on-screen video view.
final class FrameStore {
    private let lock = NSLock()
    private let views = NSHashTable<VideoNSView>.weakObjects()

    func add(_ view: VideoNSView) { lock.withLock { views.add(view) } }

    func publish(_ pb: CVPixelBuffer) {
        let targets = lock.withLock { views.allObjects }
        for view in targets { view.show(pb) }
    }
}

/// Shows frames by handing their IOSurface straight to the layer. Only the newest frame is
/// ever pending, so the picture can't fall behind the camera (a sample-buffer queue can).
final class VideoNSView: NSView {
    private let lock = NSLock()
    private var pending: CVPixelBuffer?
    /// Held so the pool doesn't recycle the surface while it's on screen.
    private var current: CVPixelBuffer?
    private let videoLayer = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.contentsGravity = .resizeAspect
        videoLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        videoLayer.frame = bounds
    }

    func show(_ pb: CVPixelBuffer) {
        let needsSchedule = lock.withLock {
            defer { pending = pb }
            return pending == nil
        }
        guard needsSchedule else { return }
        DispatchQueue.main.async { [weak self] in self?.presentPending() }
    }

    private func presentPending() {
        let pb = lock.withLock {
            defer { pending = nil }
            return pending
        }
        guard let pb, let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
        videoLayer.contents = surface
        current = pb
    }
}

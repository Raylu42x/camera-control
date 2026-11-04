import CoreImage
import ScreenCaptureKit

/// Captures the main display (minus this app's own windows) for presenter mode.
/// The first start triggers macOS's Screen Recording permission prompt.
final class ScreenSource: NSObject, SCStreamOutput {
    private let queue = DispatchQueue(label: "screen.frames")
    private let lock = NSLock()
    private var stream: SCStream?
    private var latest: CVPixelBuffer?
    private var starting = false
    private(set) var failed = false

    var image: CIImage? { lock.withLock { latest }.map { CIImage(cvPixelBuffer: $0) } }

    func start() {
        guard stream == nil, !starting else { return }
        starting = true
        failed = false
        Task {
            defer { starting = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { return }
                let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 1920
                config.height = Int(1920 * CGFloat(display.height) / CGFloat(display.width))
                config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.queueDepth = 4
                let s = SCStream(filter: filter, configuration: config, delegate: nil)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await s.startCapture()
                stream = s
            } catch {
                failed = true
            }
        }
    }

    func stop() {
        stream?.stopCapture()
        stream = nil
        lock.withLock { latest = nil }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Idle frames (screen unchanged) carry no image; keep showing the last one.
        guard type == .screen, let pb = sampleBuffer.imageBuffer else { return }
        lock.withLock { latest = pb }
    }
}

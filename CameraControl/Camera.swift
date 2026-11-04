import AVFoundation
import AppKit

/// Owns the physical camera and hands each frame to `onFrame` on a background queue.
final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onFrame: ((CVPixelBuffer) -> Void)?

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
        onFrame?(pb)
    }
}

/// Fans finished frames out to every on-screen video view.
final class FrameStore {
    private let lock = NSLock()
    private let layers = NSHashTable<AVSampleBufferDisplayLayer>.weakObjects()

    func add(_ layer: AVSampleBufferDisplayLayer) { lock.withLock { layers.add(layer) } }

    func publish(_ pb: CVPixelBuffer) {
        guard let sb = makeSampleBuffer(pb) else { return }
        let targets = lock.withLock { layers.allObjects }
        for layer in targets {
            let renderer = layer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(sb)
        }
    }

    private func makeSampleBuffer(_ pb: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sb)
        guard let sb else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }
}

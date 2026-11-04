import AVFoundation
import SwiftUI

@main
struct CameraControlApp: App {
    @StateObject private var studio = Studio()

    var body: some Scene {
        WindowGroup("Camera Control", id: "main") {
            ContentView()
                .environmentObject(studio)
                .frame(minWidth: 1040, minHeight: 660)
        }
        .defaultSize(width: 1240, height: 760)

        // Clean, chrome-free copy of the output for screen sharing or OBS window capture.
        Window("Camera Control Output", id: "output") {
            VideoView(frames: studio.frames)
                .background(.black)
                .background(CleanOutputWindow())
                .ignoresSafeArea()
                .frame(minWidth: 480, minHeight: 270)
        }
        .defaultSize(width: 1280, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}

/// Shows the pipeline's output frames. Any number of these can be on screen at once.
struct VideoView: NSViewRepresentable {
    let frames: FrameStore

    func makeNSView(context: Context) -> VideoNSView {
        let view = VideoNSView()
        frames.add(view.displayLayer)
        return view
    }

    func updateNSView(_ nsView: VideoNSView, context: Context) {}
}

final class VideoNSView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    init() {
        super.init(frame: .zero)
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { displayLayer }

    override var mouseDownCanMoveWindow: Bool { true }
}

/// Strips the traffic-light buttons so a window capture (OBS, screen share) shows only video,
/// keeps the window 16:9, and lets you drag it anywhere. Close it with ⌘W.
private struct CleanOutputWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = true
            }
            window.isMovableByWindowBackground = true
            window.contentAspectRatio = canvasSize
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

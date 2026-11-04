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
}

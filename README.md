# Camera Control

A macOS app that takes your webcam, adds effects, and lets you stop the video on demand.

## Features

- **Turn the video off and on in style:** Camera Off (⌘K), Be Right Back (⌘B) and a Starting Soon countdown card, each with an animated transition: Old TV, Glitch, Pixels, Iris, Spin or Fade. Freeze (⌘F) holds the current frame.
- **Backgrounds:** blur, static scenes (News Studio, Night City, Sunset, Space, Beach, Synthwave, Green Screen), animated scenes (Weather Map, Snowfall, Code Rain, Sky, Aquarium), a solid color, your own image, or **presenter mode** (your screen behind you, with you in the corner). Uses Vision person segmentation.
- **You vs. background:** Color Pop (you in color, the room in black and white), Neon Outline, Clones (delayed copies either side), Ghost Trail.
- **Face tricks:** laser eyes, witness protection (pixelated face or eye bar), auto-framing that follows your face.
- **News mode (⌘L):** animated lower third (tag, name, title), scrolling ticker, and a LIVE bug with channel name and clock.
- **Filters:** Mono, Noir, Sepia, Comic, Thermal, X-Ray, Invert, Pixelate, Pop Art, Crystal, Kaleido, Dreamy, VHS, Neon Edges, Old Film, Glitch, ASCII, Halftone, plus face-centered Twirl, Big Head and Pinch.
- **Weather report mode:** one button in the News tab turns on the Weather Map scene and a WEATHER lower third.
- **Face stickers:** sunglasses, hats, clown nose and full-face masks that follow your face.
- **Reactions (⌘1–⌘7):** confetti, hearts, laughs, fire, thumbs up, claps and balloons.
- **Caption (⌘T)**, mirror, zoom, brightness, contrast and saturation.
- **Snapshot (⇧⌘S):** saves the current output to Pictures › Camera Control.
- **Output window:** a clean, chrome-free copy of the video for screen sharing or OBS window capture.

Settings are saved between launches; settings added in newer versions merge with what's saved. Freeze and the cards always start off.

**Mirroring:** Mirror flips the camera image in the output itself (what OBS and Zoom receive). Text and graphics are drawn afterwards, so they stay readable. Turn Zoom's "Mirror my video" off, or it flips the picture back in your self-view.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project CameraControl.xcodeproj -scheme CameraControl -derivedDataPath build build
open "build/Build/Products/Debug/Camera Control.app"
```

## Layout

| File | What it does |
| --- | --- |
| `Camera.swift` | AVCaptureSession capture and `FrameStore`, which fans frames out to the video views |
| `Pipeline.swift` | Per-frame compositing: camera → zoom/auto-frame → background + person effects → filter → face effects → freeze → card transitions → overlays → particles |
| `Tracking.swift` | Vision person segmentation and face landmarks (box, roll, pupils) |
| `Looks.swift` | Old film, glitch, ASCII (built from stock Core Image filters, so no Metal toolchain is needed) and halftone |
| `PersonEffects.swift` | Clones/ghost frame history, neon outline, witness protection, laser eyes |
| `AnimatedScenes.swift` | Per-frame layers for the moving scenes |
| `Transitions.swift` | Camera-off / card transitions and the Starting Soon backdrop |
| `ScreenSource.swift` | ScreenCaptureKit capture for presenter mode |
| `Overlays.swift` | News package, caption and hold-card graphics (cached per text) |
| `Backgrounds.swift` | Procedurally drawn scenes |
| `Particles.swift` | Emoji reactions |
| `Studio.swift` | App state shared by the UI and the pipeline |
| `ContentView.swift` | SwiftUI controls |

Output is a fixed 1280×720 canvas, so overlays look the same no matter which camera is used.

The preview badge shows the frame rate and the latency from camera capture to finished frame (about 50 ms on a MacBook Air). Video views draw each frame's IOSurface directly and keep only the newest pending frame, so they can't fall behind. An `AVSampleBufferDisplayLayer` queue could.

## Decision: preview app first, virtual camera later

To let Zoom, FaceTime or Meet pick "Camera Control" as a camera, you need a CoreMediaIO **Camera Extension**, which is a system extension. Apple only grants the system-extension entitlement to paid Apple Developer Program teams. This Mac's signing team is a free Personal Team (`435J4NHWXP`), so the extension can't be signed or installed. (The older DAL-plugin route no longer loads on current macOS.)

So v0.1 ships the full effects pipeline as a standalone app with an **Output window**. Until there's a virtual camera, you can:

- share the Output window in a meeting, or
- add the Output window to OBS as a *Window Capture* source and use **Start Virtual Camera**.

### Using it in Zoom through OBS

1. In Camera Control, click **Output Window** (top right of the toolbar). Leave the window open; it can sit behind other windows, but don't minimize it. Drag anywhere on it to move it, and close it with ⌘W.
2. In OBS, under **Sources**, click **+** → **macOS Screen Capture**. Set *Method* to **Window Capture** and pick **Camera Control Output**. If macOS asks, allow OBS to record the screen. Don't use the older, deprecated "Window Capture" source: it polls through an old API, keeps `tccd` busy, and added about a second of lag in testing. The Screen Capture source finds windows by ID, so **after relaunching Camera Control**, open the source's Properties and pick the window again.
3. Right-click the source → **Transform → Fit to Screen**. For a sharp image, set **Settings → Video** base and output resolution to 1280×720.
4. Click **Start Virtual Camera**.
5. In Zoom, go to **Settings → Video → Camera** and choose **OBS Virtual Camera**.

### Adding the virtual camera (needs a paid developer account)

The pipeline already produces finished `CVPixelBuffer`s (`Pipeline.process`), so here's the plan:

1. Add a Camera Extension target (CMIOExtension provider, device, source stream and **sink** stream). Give the app and the extension a shared app group and the `com.apple.developer.system-extension.install` entitlement.
2. Have the app activate it with `OSSystemExtensionRequest` (it must run from /Applications).
3. In `FrameStore.publish`, also enqueue each sample buffer into the extension's sink stream through the CoreMediaIO C API (`CMIOStreamCopyBufferQueue`). The extension forwards sink frames to its source stream, which is what Zoom sees.

`CameraManager.availableDevices()` already filters out any device named "Camera Control", so the app won't capture its own output.

## Testing

Launch arguments let you check rendering without clicking through the UI. The app saves one output frame and quits:

```sh
open -n "Camera Control.app" --args -snapshotPath /tmp/frame.png -snapshotDelay 6 -turnOn cameraOff -turnOnLead 0.45
```

`-turnOn` (`cameraOff`, `blank` or `startingSoon`) switches a card on `-turnOnLead` seconds before the snapshot, so a short lead catches a transition mid-animation.

## Known gaps

- Presenter mode is untested: it needs Screen Recording permission for Camera Control, which macOS prompts for the first time it's used.

- Sticker tilt direction (`FaceTracker.rollSign`) hasn't been checked with a tilted head. Flip the sign if stickers rotate the wrong way.

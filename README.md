# Camera Control

A macOS app that takes your webcam, adds effects, and lets you stop the video on demand.

## Features

- **Stop the video:** Freeze (⌘F) holds the current frame. Be Right Back (⌘B) swaps your video for a card over a blurred snapshot.
- **Backgrounds:** blur, seven built-in scenes (News Studio, Night City, Sunset, Space, Beach, Synthwave, Green Screen), a solid color, or your own image. Uses Vision person segmentation.
- **News mode (⌘L):** animated lower third (tag, name, title), scrolling ticker, and a LIVE bug with channel name and clock.
- **Filters:** Mono, Noir, Sepia, Comic, Thermal, X-Ray, Invert, Pixelate, Pop Art, Crystal, Kaleido, Dreamy, VHS, Neon Edges, plus face-centered Twirl, Big Head and Pinch.
- **Face stickers:** sunglasses, hats, clown nose and full-face masks that follow your face.
- **Reactions (⌘1–⌘7):** confetti, hearts, laughs, fire, thumbs up, claps and balloons.
- **Caption (⌘T)**, mirror, zoom, brightness, contrast and saturation.
- **Output window:** a clean, chrome-free copy of the video for screen sharing or OBS window capture.

Settings are saved between launches. Freeze and Be Right Back always start off.

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
| `Pipeline.swift` | Per-frame compositing: camera → background → filter → stickers → freeze/hold → overlays → particles |
| `Tracking.swift` | Vision person segmentation and face tracking |
| `Overlays.swift` | News package, caption and hold-card graphics (cached per text) |
| `Backgrounds.swift` | Procedurally drawn scenes |
| `Particles.swift` | Emoji reactions |
| `Studio.swift` | App state shared by the UI and the pipeline |
| `ContentView.swift` | SwiftUI controls |

Output is a fixed 1280×720 canvas, so overlays look the same no matter which camera is used.

## Decision: preview app first, virtual camera later

To let Zoom, FaceTime or Meet pick "Camera Control" as a camera, you need a CoreMediaIO **Camera Extension**, which is a system extension. Apple only grants the system-extension entitlement to paid Apple Developer Program teams. This Mac's signing team is a free Personal Team (`435J4NHWXP`), so the extension can't be signed or installed. (The older DAL-plugin route no longer loads on current macOS.)

So v0.1 ships the full effects pipeline as a standalone app with an **Output window**. Until there's a virtual camera, you can:

- share the Output window in a meeting, or
- add the Output window to OBS as a *Window Capture* source and use **Start Virtual Camera**.

### Adding the virtual camera (needs a paid developer account)

The pipeline already produces finished `CVPixelBuffer`s (`Pipeline.process`), so here's the plan:

1. Add a Camera Extension target (CMIOExtension provider, device, source stream and **sink** stream). Give the app and the extension a shared app group and the `com.apple.developer.system-extension.install` entitlement.
2. Have the app activate it with `OSSystemExtensionRequest` (it must run from /Applications).
3. In `FrameStore.publish`, also enqueue each sample buffer into the extension's sink stream through the CoreMediaIO C API (`CMIOStreamCopyBufferQueue`). The extension forwards sink frames to its source stream, which is what Zoom sees.

`CameraManager.availableDevices()` already filters out any device named "Camera Control", so the app won't capture its own output.

## Known gaps

- Sticker tilt direction (`FaceTracker.rollSign`) hasn't been checked with a tilted head. Flip the sign if stickers rotate the wrong way.

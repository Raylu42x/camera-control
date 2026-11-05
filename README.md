# Camera Control

A macOS app that takes your webcam, adds live effects, and lets you switch your video off and on in style. Use it in Zoom, Meet, Teams or FaceTime through OBS's virtual camera.

<img src="CameraControl/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Camera Control icon">

## Features

- **Preview before you apply:** effects you pick show up in the main window first (with a yellow PREVIEW border) while your output keeps the old look. Click **Apply** (⌘↩) to send them to Zoom, or **Revert** to drop them. The big buttons (Freeze, Camera Off, Be Right Back, News Mode, Caption) still act at once. Turn off "Preview before applying" to make every change live immediately.
- **Turn the video off and on in style:** Camera Off (⌘K), Be Right Back (⌘B) and a Starting Soon countdown card, each with an animated transition: Old TV, Glitch, Pixels, Iris, Spin or Fade. Freeze (⌘F) holds the current frame.
- **Backgrounds:** blur, static scenes (News Studio, Night City, Sunset, Space, Beach, Synthwave, Green Screen), animated scenes (Weather Map, Snowfall, Code Rain, Sky, Aquarium), a solid color, your own image, or **presenter mode** (your screen behind you, with you in the corner). Uses on-device Vision person segmentation.
- **You vs. background:** Color Pop (you in color, the room in black and white), Neon Outline, Clones, Ghost Trail.
- **Face tricks:** laser eyes, witness protection (pixelated face or eye bar), auto-framing that follows your face, and stickers (sunglasses, hats, clown nose, masks).
- **News mode (⌘L):** animated lower third, scrolling ticker, and a LIVE bug with your channel name and clock. One click sets up a weather report.
- **Filters:** Mono, Noir, Sepia, Comic, Thermal, X-Ray, Invert, Pixelate, Pop Art, Crystal, Kaleido, Dreamy, VHS, Neon Edges, Old Film, Glitch, ASCII, Halftone, Twirl, Big Head, Pinch.
- **Reactions (⌘1–⌘7):** confetti, hearts, laughs, fire, thumbs up, claps and balloons.
- **Caption (⌘T)**, mirror, zoom, brightness, contrast, saturation, and **Snapshot (⇧⌘S)**, which saves a PNG to Pictures › Camera Control.

Everything runs on your Mac. Nothing is uploaded.

## Install

1. Download `Camera-Control.zip` from the [latest release](../../releases/latest) and unzip it.
2. Drag **Camera Control** into **Applications**.
3. The app isn't notarized by Apple, so the first time, **right-click it → Open → Open**. You can also run `xattr -dr com.apple.quarantine "/Applications/Camera Control.app"`.
4. Allow camera access when asked.

Requires macOS 15 or later. Apple silicon recommended.

## Use it in Zoom (or any video app) through OBS

Camera Control shows its finished video in a clean **Output window**. [OBS](https://obsproject.com) turns that window into a camera other apps can pick:

1. In Camera Control, click **Output Window** in the toolbar. Leave it open; it can sit behind other windows, but don't minimize it.
2. In OBS, set **Settings → Video** base and output resolution to **1280×720**.
3. Under **Sources**, click **+** → **macOS Screen Capture**. Set *Method* to **Window Capture**, pick **Camera Control Output**, and allow Screen Recording if macOS asks. Avoid the older "Window Capture" source: it's much slower and adds lag.
4. Right-click the source → **Transform → Fit to Screen**.
5. Click **Start Virtual Camera**. The first time, allow the OBS camera extension in **System Settings → General → Login Items & Extensions → Camera Extensions**.
6. In Zoom, choose **OBS Virtual Camera** under **Settings → Video → Camera**.

Tips:
- **Mirroring:** Camera Control's Mirror flips your camera image in the output, and text and graphics stay readable. Turn Zoom's "Mirror my video" **off**, or it flips the picture back.
- **After restarting Camera Control**, OBS shows black because the window is new. Open the source's **Properties** and pick **Camera Control Output** again.
- Quit OBS from its menu (**OBS → Quit OBS**) so it saves its scene properly.

## Build from source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project CameraControl.xcodeproj -scheme CameraControl -configuration Release -derivedDataPath build build
open "build/Build/Products/Release/Camera Control.app"
```

Builds are ad-hoc signed by default, so no developer account is needed. With ad-hoc signing, macOS asks for camera access again after every rebuild. To sign with your own certificate, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and set your team.

`scripts/make-icon.swift` regenerates the app icon.

### Code layout

| File | What it does |
| --- | --- |
| `Camera.swift` | AVCaptureSession capture; `FrameStore` and `VideoNSView` show frames with no display queue |
| `Pipeline.swift` | Per-frame compositing: camera → zoom/auto-frame → background + person effects → filter → face effects → freeze → card transitions → overlays → particles |
| `Tracking.swift` | Vision person segmentation and face landmarks (box, roll, pupils) |
| `Looks.swift` | Old film, glitch, ASCII (built from stock Core Image filters, so no Metal toolchain is needed) and halftone |
| `PersonEffects.swift` | Clones/ghost frame history, neon outline, witness protection, laser eyes |
| `AnimatedScenes.swift` | Per-frame layers for the moving scenes |
| `Transitions.swift` | Camera-off / card transitions and the Starting Soon backdrop |
| `ScreenSource.swift` | ScreenCaptureKit capture for presenter mode |
| `Overlays.swift` | News package, captions and cards (cached per text) |
| `Backgrounds.swift` | Procedurally drawn scenes |
| `Particles.swift` | Emoji reactions |
| `Studio.swift` | App state shared by the UI and the pipelines: draft settings (preview) vs. applied settings (output) |
| `ContentView.swift` | SwiftUI controls |

Output is a fixed 1280×720 canvas. While there are unapplied changes, a second `Pipeline` renders them for the preview on its own queue and skips frames if it falls behind, so previewing never slows the output. The preview badge shows the frame rate and the camera-to-output latency (about 50 ms on an M-series MacBook Air).

### Render testing

Launch arguments let you check rendering without the UI. The app saves one output frame and quits:

```sh
open -n "Camera Control.app" --args -snapshotPath /tmp/frame.png -snapshotDelay 6 -turnOn cameraOff -turnOnLead 0.45
```

`-turnOn` (`cameraOff`, `blank` or `startingSoon`) switches a card on `-turnOnLead` seconds before the snapshot, so a short lead catches a transition mid-animation.

To check the preview, pass settings to preview without applying them, plus a second path for the preview frame:

```sh
open -n "Camera Control.app" --args -snapshotPath /tmp/output.png -previewSnapshotPath /tmp/preview.png -draft '{"filter":"comic","sticker":"sunglasses"}'
```

## Why OBS instead of a built-in virtual camera?

For Zoom to list "Camera Control" directly, the app needs a CoreMediaIO **Camera Extension**, which is a system extension. Apple only grants that entitlement to paid Apple Developer Program accounts, and the older DAL plugins no longer load on current macOS. Routing through OBS's virtual camera works with any account.

If you have a paid account, the plan is:

1. Add a Camera Extension target (provider, device, source stream and **sink** stream), with a shared app group and the `com.apple.developer.system-extension.install` entitlement.
2. Activate it from the app with `OSSystemExtensionRequest` (the app must run from /Applications).
3. In `FrameStore.publish`, also enqueue each frame into the extension's sink stream (`CMIOStreamCopyBufferQueue`). The extension forwards sink frames to its source stream, which is what Zoom sees.

`CameraManager.availableDevices()` already skips any device named "Camera Control", so the app won't capture its own output.

## Known gaps

- Presenter mode hasn't been tested yet. It needs Screen Recording permission, which macOS asks for on first use.
- Sticker tilt direction (`FaceTracker.rollSign`) hasn't been checked with a tilted head. Flip the sign if stickers rotate the wrong way.

## License

[MIT](LICENSE)

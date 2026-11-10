# FrameLinePro

**Your vision. Beautifully framed.**

A creative camera for iPhone: natural photography, expressive video, and a rangefinder way of seeing. FrameLinePro brings live looks, manual controls, exposure aids and two-format recording into one considered interface.

[Download the Xcode project](https://github.com/edwinmuronzi/FrameLine-Pro/archive/refs/heads/main.zip) · [Marketing images](Marketing/AppStore) · [Releases](https://github.com/edwinmuronzi/FrameLine-Pro/releases) · [Report an issue](https://github.com/edwinmuronzi/FrameLine-Pro/issues)

<p align="center">
  <img src="Marketing/AppStore/01-your-pocket-camera-studio.png" width="31%" alt="FrameLinePro rangefinder camera interface over a cinematic coastal scene">
  <img src="Marketing/AppStore/04-dual-shot.png" width="31%" alt="Dual Shot landscape and vertical video previews">
  <img src="Marketing/AppStore/07-manual-control.png" width="31%" alt="Manual exposure, ISO, shutter, white balance and focus controls">
</p>

## Download and install on iPhone

**Current availability: source installation with a Mac and Xcode.** There is no public App Store or TestFlight installation link yet. The project currently uses a free Apple Personal Team. A source ZIP is not an iPhone installer, and an unsigned IPA cannot be installed just by opening it in Safari.

### Install with your free Apple Account

1. Use a Mac capable of running **Xcode 27.2 or newer**. Install Xcode from Apple and open it once to finish installing its components.
2. [Download this project](https://github.com/edwinmuronzi/FrameLine-Pro/archive/refs/heads/main.zip) and unzip it, or clone it:
   ```sh
   git clone https://github.com/edwinmuronzi/FrameLine-Pro.git
   ```
3. Open **FrameLinePro.xcodeproj** in Xcode. Select the **MyApp** scheme.
4. In **Xcode → Settings → Accounts**, add your own Apple Account. Keep your credentials private.
5. Select the **FrameLinePro** target, open **Signing & Capabilities**, enable automatic signing, and select **your Personal Team**. Change the bundle identifier to a unique value you control, for example `com.yourname.FrameLinePro`.
6. Connect your iPhone, unlock it, and trust the Mac if asked. The phone must run **iOS 26 or newer**.
7. Select the phone as the run destination and press **Run (⌘R)**. If iOS asks, enable **Developer Mode** under Settings → Privacy & Security, restart, and confirm. Follow any developer-trust prompt shown by iOS.
8. Open FrameLinePro, explore or skip the feature tour, then allow camera access. Microphone access is needed for sound in videos; Photos access is needed to save into your library.

Personal Team signing expires periodically. If the development app stops opening, connect the phone and run it from Xcode again. This method needs a Mac; there is currently no supported phone-only public install.

### Public beta and App Store release

Public distribution is the next publishing step, **not currently enabled**. The owner needs Apple Developer Program membership, App Store Connect access, distribution signing, a processed uploaded build and the applicable Apple review. External TestFlight testing also needs a tester group and a public invitation link.

When available, this section will contain the real TestFlight/App Store link. See [Apple’s distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/) and [external TestFlight instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

## Three ways to make an image

### Photo — natural detail, personal color

- HEIF and JPEG capture, with **HEIF Max** and **RAW** where the selected camera supports them.
- Repeated shutter presses use independent capture requests. Grading and thumbnail creation happen away from the interface, with bounded processing to protect memory.
- Automatic exposure when you want simplicity; manual controls when you need precision.
- Live camera styles, custom look recipes, and optional LUT baking.
- Full-frame, framed crop, or both; full-resolution files remain available from the session gallery.
- Countdown, exposure bracketing, still timelapse, grid, level and focus magnifier.

HEIF Max, RAW, flash, low-light processing and bracketing take longer than ordinary stills. Responsive/zero-shutter-lag capture is enabled only where supported; timing remains dependent on the camera, format and light. There is no claim of unlimited full-resolution burst capture.

### Video — motion with intention

- Resolution, frame rate, bitrate and codec choices discovered from the active camera.
- **Apple Log, Apple Log 2 and ProRes** on compatible devices, lenses and formats. Unsupported combinations are not universal features.
- Exposure, white balance, shutter angle and supported focus control.
- Live styles and enabled LUT baking while recording on the live grading path.
- RGB histogram/waveform and exposure/focus aids available while recording.
- Microphone selection, audio level/clipping indication and headphone monitoring.
- Torch control on supported cameras, including during recording.
- Clean recording controls, clip counters and running timecode.

### Rangefinder — see beyond the crop

Choose frame lines using the focal-length ruler while keeping the wider scene visible. Anticipate the next subject entering the composition, then save the full image, the framed crop, or both. These are digital framing/crop controls, not a promise of a different physical lens or optical focal length.

## Dual Shot: one take, two finished videos

Record **landscape 16:9 and vertical 9:16 simultaneously from one camera source**. A movable, resizable live landscape window sits inside the main reel viewfinder so you can judge both compositions.

- Two finished files: **1920×1080 landscape** and **1080×1920 vertical**.
- A camera style is baked into the pair. A selected LUT is baked only when its bake control is enabled.
- No style and no baked LUT means a plain pair.
- Optional subject tracking moves the reel crop independently; the landscape framing stays centered.
- Optional reel safe-zone guides help leave room for captions. Guides and tracking boxes do not appear in saved videos.
- Both outputs are committed together to Photos after successful finalization. Incomplete pairs are not deliberately published.

Dual Shot is two crops of one source, not two independently pointed cameras. It does not create four copies, and it does not deliver two 4K files. Available framing is limited by what the camera can see.

## Looks, LUTs and shooting presets

**Looks** are the camera’s visual recipes: color, tone, grain, softness, glow, vignette and other supported adjustments. Use **Fn → Looks / Look Studio** to explore built-in styles, make your own, and adjust the Quality and Tone dials.

**LUTs** are imported `.cube` color transforms. Use the **LUT** pill to select a transform and adjust its mix. Preview and baking are independent: seeing a LUT in the viewfinder does not, by itself, mean it will be written into a file. The LUT pill is yellow when baking is active and white otherwise. Hold/tap A/B to compare against the original preview.

**Shooting presets** remember a setup, including format, exposure, white balance, focus, lens/zoom, style/LUT, Dual Shot, framing and audio choices. Use **LUT → Save Preset** or **Fn → Shooting tools → Shooting presets**. The selected preset is yellow. Changing its setup clears the selection; automatic exposure/focus readings do not. Apply presets between recordings. A referenced custom look or LUT must still be available.

### What saves

- Stills without a look/baked LUT save the plain output(s) you selected.
- With a look or baked LUT, the graded selected output(s) save to Photos; originals remain available in the app’s session gallery.
- Identical full-frame/crop outputs are not intentionally duplicated.
- RAW capture also preserves a separate DNG where supported.
- Dual Shot saves the final two-video pair described above.
- The session gallery keeps small previews in memory and opens larger previews from files when needed. Share uses full-resolution files. Save important work to Photos or export it; the session gallery is not a cloud backup.

## Tools that stay out of the way

| Tool | Where / purpose |
| --- | --- |
| **M** | ISO, shutter, EV, white balance and supported focus; use auto where preferred |
| **HIST** | RGB exposure histogram, including during recording |
| **Eye** | Compact waveform, zebra, peaking and false-color switches; clean feed |
| **MAG** | Focus magnifier |
| **Fn → Shooting tools** | Presets, tracking, focus pulls, safe zones, anamorphic and audio |
| **Subject tracking** | Tap a subject in Dual Shot’s reel; autofocus can follow while AF is enabled |
| **Focus pulls** | Set two marks and a duration. Fixed-lens mode uses supported rear 1×/2× framing; turn it off to return to all-lens zoom |
| **Anamorphic desqueeze** | Preview correction, or explicitly saved correction for compatible video paths; requires the matching physical attachment for an anamorphic image |
| **Audio** | Select available microphone inputs; monitor through headphones/compatible output routes and watch clipping |
| **Preserve settings** | Restore the previous shooting setup and controls across launches |
| **Feature tour** | First-launch introduction; replay it from Settings |

Lens stops, stabilization, torch, RAW, Log, ProRes, manual focus and audio routes depend on the actual hardware. A focus pull cannot be promised on every virtual camera or lens. Anamorphic preview correction alone does not alter a saved file; raw Log paths without grading may remain preview-only.

## First launch and everyday use

The ten-page introduction showcases photography, video, Dual Shot, live looks, rangefinder composition, manual controls, exposure aids and shooting tools. It is skippable and replayable, uses frosted native glass, respects reduced-motion preferences for its transitions, and keeps the live camera off until you enter the camera.

- Tap the bare viewfinder to focus; hold to lock exposure/focus.
- Drag vertically to adjust exposure.
- Use the ruler and lens selector to reframe; supported unified rear cameras provide continuous zoom transitions.
- Use the eye panel or double-tap the viewfinder for a cleaner composition.
- Open the gallery thumbnail to compare available originals/crops/graded versions and share.

## Compatibility, performance and privacy

- **Deployment target: iOS 26.0+.** This release keeps one modern interface rather than a separate reduced iOS 16/iPhone X app.
- A phone that cannot run iOS 26 cannot install this build. Running iOS 26 also does not give older hardware newer sensors, lenses, RAW/Log/ProRes support or identical throughput.
- The current development toolchain is **Xcode 27.2**. The minimum OS is a build target, not a claim that every supported iPhone has been physically tested.
- Capture, Core Image grading and subject tracking run on the device. This build has no account system, subscription flow, analytics SDK or photo-upload service.
- Camera, microphone and Photos permissions are used for their corresponding capture/save functions. If you share through another app or use iCloud Photos, that service’s behavior is separate.
- Rendering resources are reused, photo processing is bounded, and motion/storage polling pauses in the background. The zoom ruler does not run a constant display-rate redraw while idle.
- Camera hardware, screen brightness, high resolution, tracking and grading still consume power and can warm the phone. There is no zero-heat, zero-drain or zero-lag guarantee.

The marketing scenes are **AI-generated illustrative photography**, not evidence that FrameLinePro captured those images. The interfaces shown are rendered from the app’s own views. Images in the Halide reference material are not redistributed as FrameLinePro assets.

## Marketing kit

Ten coordinated **1320×2868, opaque PNG** images are in [Marketing/AppStore](Marketing/AppStore), covering the main camera, photo, video, Dual Shot, looks/LUTs, rangefinder, manual controls, scopes, shooting tools and the overall experience.

The set is designed for the iPhone App Store screenshot slot; confirm [Apple’s current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) and your actual supported devices before submission. It is a prepared marketing set, not an App Store approval or a published listing. See [the marketing notes](Marketing/README.md) for source, copy and regeneration details.

## Build and development

Open `FrameLinePro.xcodeproj`, use scheme **MyApp**, and build the **FrameLinePro** target. Swift source is in `FrameLinePro/`. Photos and saves must be checked on real devices; simulator previews do not validate camera speed, lens transitions or thermal behavior.

```sh
xcodebuild -project FrameLinePro.xcodeproj \
  -scheme MyApp -configuration Debug \
  -destination 'generic/platform=iOS' build
```

Choose your signing team before using the device build command. See [DEVELOPMENT.md](DEVELOPMENT.md) for regression checks and the build/install/push workflow.

Found an issue? Include the iPhone model, iOS version, mode, format/frame rate, look/LUT state and exact steps in [an issue](https://github.com/edwinmuronzi/FrameLine-Pro/issues). Please do not attach private photos or credentials unless you intend to share them publicly.

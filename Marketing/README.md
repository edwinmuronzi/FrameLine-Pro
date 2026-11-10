# FrameLinePro marketing kit

Ten portrait marketing images for the iPhone App Store screenshot slot. Each file in `AppStore/` is an opaque RGB PNG at **1320 × 2868**. Typography, device framing, captions and feature copy are rendered in code; the app interfaces are captured from the actual running simulator views. The photographic scenes are original **AI-generated illustrations**, not claims of images captured with FrameLinePro.

## Set order

1. Your vision — the overall Photo / Video / Rangefinder experience.
2. Photography — HEIF, JPEG and supported RAW; natural detail and color.
3. Video — manual video and hardware-dependent Log / codec choices.
4. Dual Shot — landscape + vertical reel, two live views and two finished files.
5. Looks & LUTs — live camera styles, look recipes and imported `.cube` transforms.
6. Rangefinder — frame lines, wider context, full frame and crop.
7. Manual control — exposure, ISO, shutter, white balance and supported focus.
8. Exposure and focus aids — RGB histogram/waveform, zebras, peaking and false color.
9. Shooting tools — presets, subject tracking, focus pulls and audio tools.
10. The creative camera — closing brand / everyday-use frame.

## Source and editable copy

- `FrameLinePro/FeatureTour.swift`: shared feature text and the first-launch tour.
- `FrameLinePro/MarketingExport.swift`: Debug-only native screenshot compositor.
- `FrameLinePro/Assets.xcassets/Story*.imageset`: original illustrative photography used by the tour.
- `FrameLinePro/Assets.xcassets/Screen*.imageset`: compressed interface previews for efficient onboarding.
- `GenerationPrompts.json`: prompt set and generation method (built-in image_gen).
- `AppStore/`: finished marketing PNGs. `Overview.jpg`, if present, is a review contact sheet, not a listing screenshot.

The Halide references informed the brief’s broad presentation direction. Halide screenshots, logos, sales copy and claims are not redistributed in this kit.

## Regenerate

Use the Debug build on a simulator. `scripts/export-marketing.sh` builds the app, captures each `--capture-story N` interface through the native simulator window, and launches `--export-marketing` to render the decorated set. Native window capture matters: offscreen renderers cannot reproduce every UIKit-backed menu.

Review all ten images after changing UI, copy, assets or simulator versions. Keep feature claims consistent with the shipped build. The kit does not imply that Log, RAW, ProRes, every lens stop or manual focus exists on every iPhone.

The current app also targets iPad. This kit is the iPhone set; prepare appropriate iPad screenshots before a universal App Store submission. Follow [Apple’s current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## Publishing

A download of these PNGs is not an app installation. The current free Personal Team cannot publish the app through TestFlight or the App Store. The repository README explains the available Mac/Xcode source-install route and the remaining publishing steps.

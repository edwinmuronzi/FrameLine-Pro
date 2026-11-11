# FrameLinePro marketing kit

Ten portrait marketing images for the iPhone App Store screenshot slot. Each file in `AppStore/` is an opaque RGB PNG at **1320 × 2868**. Typography, device framing, captions and feature copy are rendered in code; the app interfaces are captured from the actual running simulator views. The photographic scenes are original **AI-generated illustrations**, not claims of images captured with FrameLinePro.

## Set order

1. Your vision — the overall Photo / Video / Rangefinder experience.
2. Photography — natural detail, supported RAW and depth, with HDR highlights.
3. Video — manual video and hardware-dependent Log / codec choices.
4. Dual Shot — landscape + vertical reel, two live views and two finished files.
5. Looks & LUTs — live camera styles, imported `.cube` transforms, photo grain and warm light halos.
6. Rangefinder — frame lines, wider context, full frame and crop.
7. Manual control — exposure, ISO, shutter, white balance and supported focus.
8. Exposure and focus aids — RGB histogram/waveform, zebras, peaking and false color.
9. Shooting tools — custom photo controls, portable presets and viewfinder focus pulls.
10. The creative camera — closing brand / everyday-use frame.

## Source and editable copy

- `FrameLinePro/FeatureTour.swift`: shared feature text and the fifteen-page first-launch tour. The marketing exporter uses the original nine shooting topics plus the final brand page.
- `FrameLinePro/MarketingExport.swift`: Debug-only native screenshot compositor.
- `FrameLinePro/Assets.xcassets/Story*.imageset`: original illustrative photography used by the tour.
- `FrameLinePro/Assets.xcassets/Screen*.imageset`: compressed interface previews for efficient onboarding.
- `GenerationPrompts.json`: prompt set and generation method (built-in image_gen).
- `AppStore/`: finished marketing PNGs. `Overview.jpg` is a review contact sheet, not a listing screenshot.

The Halide references informed the brief’s broad presentation direction. Halide screenshots, logos, sales copy and claims are not redistributed in this kit.

## Regenerate

Use the Debug build on a simulator. `scripts/export-marketing.sh` builds the app, captures each `--capture-story N` interface through the native simulator window, and launches `--export-marketing` to render the decorated set. Native window capture matters: offscreen renderers cannot reproduce every UIKit-backed menu.

Review all ten images after changing UI, copy, assets or simulator versions. Keep feature claims consistent with the shipped build. The kit does not imply that Log, RAW, ProRes, every lens stop or manual focus exists on every iPhone.

The kit includes three native 2064 × 2752 iPad captures in [AppStore-iPad](AppStore-iPad). [Onboarding.jpg](Onboarding.jpg) previews four pages from the tour. Follow [Apple’s current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## Publishing

A download of these PNGs is not an app installation. The current free Personal Team cannot publish the app through TestFlight or the App Store. The repository README explains the available Mac/Xcode source-install route and the remaining publishing steps.

## Listing copy

**Subtitle:** Film looks and manual camera

FrameLine Pro is a camera for stills, video and rangefinder framing. Choose a film look live, shape exposure and focus, and keep your favorite controls within reach.

- Keep natural texture with supported RAW capture, depth portraits and HDR highlights.
- Give photos midtone grain or warm light halos with 35mm Night.
- Turn moving water into a soft blur or stretch moving lights into trails.
- Compose with rangefinder frame lines, or record a landscape clip and a vertical reel in one take.
- Set two focus distances in the viewfinder, preview imported LUTs and save your shooting setup as a preset.

Format, lens and capture combinations vary by device. Listing setup also requires distribution signing, an App Store Connect app record, privacy and support URLs, and review.

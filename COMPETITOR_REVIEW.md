# Remaining camera-app priorities

Reviewed 10 November 2026 against the vendors’ own published descriptions. Feature availability depends on hardware and app version. This is a product-gap review, not an independent image-quality or speed benchmark.

| App | Significant capability beyond the current FrameLinePro workflow | Practical next step |
| --- | --- | --- |
| Halide | HDR-aware looks and Photo Lab controls for crop, leveling, output resolution, tone fusion, film components and RAW development. | Crop/straighten and export sizing are now implemented. Adaptive HDR JPEG export is now available for compatible HDR originals, alongside crop/straighten and export sizing. Next validate styled HDR across real scenes and expand RAW/HDR combinations. |
| No Fusion | Its proprietary ProRAW-based HEIF+ development, advanced HSL tools, and advertised combinations of high-resolution RAW, Live Photo, Portrait, HDR and re-editing. | Adjustable depth blur and selective hue, saturation and lightness controls are now implemented. Live Photo with depth and HDR, and a ProRAW DNG alongside an HDR still, are verified on the iPhone 16 Pro. Depth and ProRAW remain separate capture paths. FrameLine’s Natural RAW is a different pipeline; its depth portrait is a rendered image, not Apple’s editable Portrait asset. |
| Moment Pro Camera II | Dedicated slow-shutter motion blur/light trails, configurable Action Plates and widgets/shortcuts that open a particular mode or Profile. | Launch links for shooting presets are available. Frame-blended motion blur and light trails are available with 1–8 second capture windows. The Photo and Rangefinder bottom row and the viewfinder shortcuts can be rearranged. |
| mood.camera | Film-character calibration, highlight/gain-map-aware bloom and halation, dynamic-range shaping and film-grain modeling. | Validate a smaller set of looks across skin tones, mixed light, bright highlights and low light; improve highlight-aware film rendering. More preset names alone will not close this gap. |

FrameLine already combines video, simultaneous landscape/reel output, rangefinder framing, live styles/LUTs, manual controls and viewfinder A/B focus pulls. Those are useful differentiators, not evidence that it beats every specialist camera.

## Sources

- [Halide Mark III](https://www.lux.camera/halide-mark-iii/) describes its current Photo Lab, HDR looks and film controls.
- [No Fusion core features](https://www.nofusion.app/en/introduction.html) describes HEIF+, HSL and format combinations. Its [FAQ](https://www.nofusion.app/en/faq.html) also explains processing, preview and thermal tradeoffs.
- [Moment’s released updates](https://www.momentprocamera.com/whats-new) lists Slow Shutter, Action Plates and mode/Profile shortcuts. Its [manual](https://www.momentprocamera.com/manual) covers the corresponding workflows. Roadmap requests were not treated as released features.
- [mood.camera](https://www.mood.camera/) and its [v2 processing notes](https://www.mood.camera/v2) describe film rendering and dynamic range. It deliberately does not offer a live filter preview; FrameLine’s live preview is a different design choice.

## Order of work

1. Reliable startup, dependable capture/save and measured thermal performance across supported phones.
2. Broader real-scene HDR validation and more compatible capture combinations. Adaptive HDR JPEG editing of compatible originals, crop/straighten/output size and adjustable depth edits for new captures are now available.
3. More consistent natural/film processing, with real reference photographs and controlled side-by-side tests.
4. Frame-blended slow shutter, launch-to-preset links, batch sharing and portable preset files are implemented. Further editing features are outside the camera roadmap.

Avoid claiming zero heat, identical performance on every phone, or a proprietary competitor pipeline that FrameLine does not implement. Use VALIDATION.md for the measured scope of each release.

## Implementation status — 11 November 2026

The competitor-inspired work is not all finished. Shipped additions include viewfinder A/B focus pulls, Natural RAW, Live Photo/depth capture, retained originals and edit recipes, crop/straighten/output sizing, adjustable retained-depth blur/separation, compatible-source adaptive HDR export, style/preset management, anamorphic framing and Lock Screen capture.

Still open: broader device coverage and more real-scene film calibration. Photo grain now tapers at tonal extremes, and 35mm Night applies highlight-driven halation. Fuji Classic, Eterna, Cinegrain and Night 35 now use gentler highlight curves and less saturated highlight tint. Native editable Apple Portrait assets and a proprietary HEIF+ equivalent are not implemented. Sustained 30 fps and older-device/energy validation also remain open. Lossless working-buffer support improves the memory architecture while retaining the grade; it does not establish feature parity or unlimited thermal performance.

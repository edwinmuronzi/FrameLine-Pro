# Remaining camera-app priorities

Reviewed 10 November 2026 against the vendors’ own published descriptions. Feature availability depends on hardware and app version. This is a product-gap review, not an independent image-quality or speed benchmark.

| App | Significant capability beyond the current FrameLinePro workflow | Practical next step |
| --- | --- | --- |
| Halide | HDR-aware looks and Photo Lab controls for crop, leveling, output resolution, tone fusion, film components and RAW development. | Add crop/straighten and export resolution to Develop photo; then preserve HDR/gain-map information through editing and export. |
| No Fusion | Its proprietary ProRAW-based HEIF+ development, advanced HSL tools, and advertised combinations of high-resolution RAW, Live Photo, Portrait, HDR and re-editing. | Make depth editing adjustable after capture and expand compatible format combinations. FrameLine’s Natural RAW is a different pipeline; its depth portrait is a rendered image, not Apple’s editable Portrait asset. |
| Moment Pro Camera II | Dedicated slow-shutter motion blur/light trails, configurable Action Plates and widgets/shortcuts that open a particular mode or Profile. | Prioritize a straightforward motion-blur/light-trails mode and launch-to-preset controls. Three FrameLine shortcuts are useful but do not equal a fully configurable capture layout. |
| mood.camera | Film-character calibration, highlight/gain-map-aware bloom and halation, dynamic-range shaping and film-grain modeling. | Validate a smaller set of looks across skin tones, mixed light, bright highlights and low light; improve highlight-aware film rendering. More preset names alone will not close this gap. |

FrameLine already combines video, simultaneous landscape/reel output, rangefinder framing, live styles/LUTs, manual controls and viewfinder A/B focus pulls. Those are useful differentiators, not evidence that it beats every specialist camera.

## Sources

- [Halide Mark III](https://www.lux.camera/halide-mark-iii/) describes its current Photo Lab, HDR looks and film controls.
- [No Fusion core features](https://www.nofusion.app/en/introduction.html) describes HEIF+, HSL and format combinations. Its [FAQ](https://www.nofusion.app/en/faq.html) also explains processing, preview and thermal tradeoffs.
- [Moment’s released updates](https://www.momentprocamera.com/whats-new) lists Slow Shutter, Action Plates and mode/Profile shortcuts. Its [manual](https://www.momentprocamera.com/manual) covers the corresponding workflows. Roadmap requests were not treated as released features.
- [mood.camera](https://www.mood.camera/) and its [v2 processing notes](https://www.mood.camera/v2) describe film rendering and dynamic range. It deliberately does not offer a live filter preview; FrameLine’s live preview is a different design choice.

## Order of work

1. Reliable startup, responsive editing, dependable capture/save and measured sustained thermal performance across supported phones.
2. Adjustable depth edits, crop/straighten/output size and HDR-preserving photo export.
3. More consistent natural/film processing, with real reference photographs and controlled side-by-side tests.
4. Slow-shutter/light-trails capture, launch-to-preset controls, then batch editing/export and portable preset files.

Avoid claiming zero heat, identical performance on every phone, or a proprietary competitor pipeline that FrameLine does not implement. Use VALIDATION.md for the measured scope of each release.

# FrameLinePro development

Open `FrameLinePro.xcodeproj` and use scheme `MyApp`. The Swift source and assets are in `FrameLinePro/`.

After changes, build in Xcode, install on the connected iPhone, and leave the app open for device testing. Commit the complete source changes and push to https://github.com/edwinmuronzi/FrameLine-Pro after verification. Exclude build products, local Xcode state and credentials.

## Device regression checks

- Open LUT → Save Preset, save a named setup, change it, and restore it from the same panel. The selected preset is yellow; automatic exposure/focus readings preserve selection, while changing the setup clears it. Test rename/delete through Presets.
- Change mode, lens/zoom, look/LUT, manual controls and framing. Background/foreground repeatedly, then force-quit/relaunch. Verify the same setup is restored with Preserve Settings enabled.
- Record successive Dual Shot clips in Standard and with styles/LUTs, including grain/glow. Move the phone. Inspect both previews and the left edge of both saved files. Each recording must create exactly two playable files.
- Toggle waveform, zebra, peaking and false color from the eye panel, repeatedly and while recording. Each switch should react on its first tap.
- Switch 8× ↔ 0.5× while recording, then stop and record again. Both previews should remain live.
- Check microphone selection, headphones, audio/video sync and capture interruption recovery on real hardware.

DEBUG-only launch arguments `--verify-live-zoom`, `--verify-advanced-preview`, `--verify-focus-pull` and `--verify-styled-recording`, `--verify-efficiency` and `--verify-interruption` run bounded device checks. The styled-recording check uses temporary files and does not save to Photos. Use a normal launch afterwards.

`--verify-efficiency` records a private 60-second styled Dual Shot pair and logs thermal state, both preview counts, final frame counts and dimensions. `--verify-interruption` injects capture-session interruption notifications and checks finalization/resume. Diagnostic movie events are intercepted so they do not save to Photos. Keep the phone unlocked for sustained capture checks. Real call/lock interruption scenarios still need device testing.

Efficiency changes preserve recording resolution, frame rate, bitrate and grading. Motion/storage polling and capture metering stop in the background, unused audio monitoring is lazy, and preview/writer format descriptions are reused. Report thermal state and measured battery/power separately; thermal status alone does not measure energy consumption.

## Photo pipeline and onboarding

`--verify-photo-pipeline` exercises reordered callbacks, isolated grading contexts, both saved framings, thumbnail bounds and chronological ordering. `--verify-photo-burst` submits five HEIF shutter requests 140 ms apart, then repeats with a style; it checks completion and main-actor progress and cleans its local files without writing test images to Photos. Device verification passed all ten captures; completion including processing was 4.42 seconds plain and 2.75 seconds styled. This is a bounded regression check, not a guarantee of identical throughput on every device or format.

Test first-launch onboarding and Settings → feature tour, including interactive look comparisons, large text and Reduce Motion. Preview stores must never activate the camera or overwrite preserved shooting preferences. Use `--show-tour --tour-page N` for Debug visual checks (zero-based page).

Run `scripts/export-marketing.sh` to refresh ten native interface images and marketing compositions, then rebuild to include the compressed onboarding previews. Review the output before release. Minimum deployment is iOS 26; RAW, codecs and lens availability remain hardware-dependent. Simulator compilation does not replace testing on the oldest supported hardware.

## 1.2 feature validation

The app now embeds `LockCapture` (ExtensionKit secure capture) and `CameraControlWidget` (WidgetKit control), sharing the camera intent with the main app. All three targets must use the same signing team and matching bundle-ID prefixes. Locked capture has a separate photo-only camera and cannot browse the main gallery. Session content imports only after the main gallery index loads and is invalidated only after the index writes successfully. Test actual Lock Screen customization, authentication, extension termination during capture and import on hardware; compilation/signing alone does not prove those system flows.

New Debug diagnostics:

- `--verify-upgrade`: four batches of five independent shots, then available Native RAW/Live/depth modes, full-resolution RAW edit checks, non-destructive editing and a 250-record archive roundtrip. Does not write to Photos. Wait for `UPGRADE_VERIFY COMPLETE`.
- `--verify-library`: 250 records restored through a new archive instance, edit recipes retained, deletion persisted, 30 preview edits, bounded thumbnails and unchanged original bytes.
- `--verify-viewfinder`: A/B autofocus measurements, exposure preservation, forward/reverse pulls and repeated cancellation.
- `--verify-direct-grade`: compares the optimized working-resolution grading path against full-source rendering for three styled scenes, both output crops and the left edge. The retained writer resolves the grade once before cropping; the experiment that graded both full-source crops independently was not retained.
- `--verify-styled-recording --verify-throughput`: ten-second paired-file and preview check. `--verify-efficiency` extends it to 60 seconds and logs thermal state. Inspect actual frame counts and duration; valid files alone do not demonstrate a sustained requested frame rate.

Use an optimized **Release** build on the user's phone for final review. For optimized diagnostic builds only, use Release with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG`; install a clean Release without that override afterwards. Debug-build timing is not representative of shipped performance.

Thermal stress testing exposed reduced throughput on a phone already in the serious thermal state. Do not describe this as zero heat, zero dropped frames, or guaranteed 30 fps across hardware. Output dimensions, codec, bitrate and requested rate are preserved. Final UI checks: first-launch/replayed fifteen-page tour, Reduce Motion/large text, three custom shortcuts, focus-strip/LUT/A–B overlap, Photo/Rangefinder manual AUTO versus bracketing, persistent original/edited sharing, paired Live Photo playback in Photos, and depth edge quality.

## 1.2.1 implementation notes

`InteractivePhotoPreview` caches the source image and draws only when adjustments change; full-resolution encoding stays in the explicit save path. Keep editing off the camera session. `LookLibraryManagement` persists visibility/order/trash and bounded undo snapshots; archive deleted custom recipes so old edits remain reproducible.

Do not probe recording codecs from Photo/Rangefinder mode: changing the active video format can silently disable depth delivery. Configure depth-compatible formats before capture and preserve the restored camera configuration on foreground resume. Shared CameraCaptureIntent membership belongs to the app, WidgetKit control and secure capture extension; the extension must handle hardware capture events. Test actual Lock Screen routing on hardware, not solely build metadata.

Use native NV12 output for 8-bit styled recordings and preserve explicit transfer/matrix attachments. The color diagnostic compares mean linear RGB error, not an sRGB-encoded error statistic. Keep the longer efficiency test and inspect both frame counts and thermal state; successful file creation alone does not prove smooth sustained recording. See VALIDATION.md for measured results and COMPETITOR_REVIEW.md for remaining product priorities.

## 1.2.2 photo lab and capture buffers

PhotoEdit uses optional crop/straighten/export/depth fields so older recipes decode unchanged. PhotoGeometry shares crop transforms between the GPU preview and final export, trims rotation corners and snaps crop boundaries to integer pixels to avoid transparent JPEG fringes. Export resizing uses clamped Lanczos sampling and never upscales. Keep the preview above the scrollable controls.

New depth captures store an oriented, normalized float32 mask in depth-mask.json. The main library records its relative path; deleting a capture deletes the mask too. Save a private full source when a depth capture requested only a framed export. Existing images without a mask keep their prior editor behavior; never synthesize depth or advertise Apple editable Portrait assets.

Analysis output explicitly opts out of automatic/preview buffer dimensions before supplying exact dimensions, and requests native 8-bit 4:2:0 where supported. Use even-pixel multiples of the source’s reduced aspect ratio so stricter camera implementations accept the size request. For Dual Shot, size the short edge to at least 1920 pixels so the landscape crop keeps 1080p detail. Do not shrink to a 1920-pixel long edge; that would require upscaling the landscape output. Retain the existing scaling-crash fallback.

`--verify-editor-preview` includes PhotoLabVerification: crop/rotation/position cases, empty-corner detection, output sizes, no upscaling, legacy recipes and lossless depth-mask roundtrip. `--show-photo-editor --expand-editor` previews the real editor with isolated sample files. These routes are Debug-only.

## 1.2.3 gallery lifecycle and adaptive HDR

Keep CaptureButtonModifier structurally stable when review state changes. Its handler checks whether capture is allowed; conditionally replacing its wrapped view recreated the preview while the session was stopping. Gallery review uses the sheet's onDismiss to clear review state and flush stale display queues, rather than a nested navigation page's onDisappear. Native mirroring reads connection-port metadata, not the live session's input collection on the UI thread.

Do not stop/restart the capture session just for gallery presentation: stress testing exposed an intermittent stopped-camera/UI stall in that cycle. Keep the session warm, suppress custom preview/scopes while covered, and resume the same display layers on dismissal. Normal app-background stopping is retained. During recording, encoded outputs and tracking continue while hidden preview/scopes are suppressed.

GalleryThumbnails bounds photo/video decoding to two background jobs and caches up to 24 MiB of decoded thumbnails. Photo thumbnails use ImageIO URL sources; video generator work is cancellable. Detail viewing requests HDR decoding separately, and duplicate full/frame URLs are decoded once. Bulk deletion updates the collection/index once and removes files off the main thread only after the index saves and previously enqueued Photos imports finish. Failed index saves restore the items and leave files intact.

HDRPhoto expands compatible HDR originals, applies the same recipe/crop/resize to SDR and HDR images, and writes a new adaptive JPEG gain map. Never copy an old gain map onto a newly edited image. Preserve HDR highlights is optional; the live editor preview remains SDR. RAW and already-flattened SDR sources are not promoted to HDR. The viewer requests HDR decoding and high dynamic range on supported displays.

Debug checks: --verify-gallery exercises quick/long dismissals in Photo and Dual Shot, preview mount count, fresh-frame recovery, main-actor heartbeat, selected/all deletion and failed-index rollback using isolated files. --verify-editor-preview also checks actual HDR pixel values, crop size, the SDR opt-out and HDR-aware viewer decoding. --show-gallery --select-gallery previews selection controls without user media.

## 1.2.4 recording pipeline

MovieRenderResources owns one lazily created Metal queue/Core Image context for the camera session. Preview and recordings reuse compiled GPU programs instead of creating a cold context at every Record. LiveMovieWriter keeps at most two GPU frames in flight; it retains each camera sample, resolved pixel buffer and output samples until dependent work completes. A completion barrier returns to the serial writer queue before appending both outputs. Stop waits for admitted GPU frames before finishing either file. The non-Metal/synchronous fallback remains.

The capture-to-writer bridge uses a two-sample bounded FIFO and user-initiated queues to absorb short scheduling spikes, clearing stale samples across stream boundaries. Scopes and loupe rendering have bounded utility work off the camera delivery queue. RGB scope buffers are pooled, and scope readbacks use a separate low-priority context. Scope callbacks hop to MainActor once.

Date stamps cache the formatter and a bounded set of rendered sizes instead of rebuilding the label when preview and recording sizes alternate. Storage polling only publishes changed values. Finishing a writer returns preview rendering to the live camera immediately rather than waiting for file finalization.

The grading functions, spatial effects, output dimensions, codecs and bitrate remain unchanged. Direct per-crop grading and cached color-cube approximations were tested and rejected for performance or fidelity reasons. RenderOrderVerification compares the retained grade/crop path across three looks, LUT/intensity blends, date stamps and both crop edges at the existing 8-bit resolve precision. Flatten alpha before difference-blend comparisons: Porter-Duff compositing otherwise reports a false error on identical partially transparent edges.

Use --verify-render-order for image comparisons; --verify-efficiency --long-soak records three minutes and reports sorted-PTS cadence and five-second frame counts as well as thermal state. Diagnostic arguments and timing arrays are Debug-only. Ship a normal Release build after testing.

Dual Shot orientation invariant: analysis frames are portrait (connection angle 90); never apply deviceAngle/lastAngle a second time to idle dual crops or the analysis-backed live writer. Front analysis is mirrored once. The fallback writer connection is also portrait and uses exact native-aspect even dimensions. Device-angle rotation is retained for single-output captures. `--verify-styled-recording --rotate-dual` exercises four starts and finalization cycles without saving to Photos. Keep the two-frame GPU limit and cacheIntermediates=false; caching/deeper-queue trials did not establish a sustained-rate benefit.

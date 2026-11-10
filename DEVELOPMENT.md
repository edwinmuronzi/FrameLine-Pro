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

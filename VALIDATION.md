# FrameLinePro 1.2 validation

The signed Release archive, the Debug simulator build and both embedded camera extensions build successfully with the installed Xcode toolchain. The final phone installation uses Release optimization without the Debug diagnostic flag. Minimum deployment remains iOS 26.

## Passed checks

- Connected iPhone: four batches of five HEIF requests, alternating standard/styled processing. All twenty requests completed. Submission was 100 ms apart; total completion includes background rendering and storage, not just shutter timing.
- Connected iPhone: native Bayer RAW capture and development, a draft RAW preview, full-resolution RAW editing, Live Photo movie delivery and depth-map portrait rendering. Test media was not sent to Photos.
- Original bytes unchanged after development; thirty repeated preview edits; a new archive instance restored 250 records and edit recipes, with deletion reflected after saving.
- Viewfinder A/B autofocus measurement, exposure-bias preservation, forward/reverse pulls and twelve cancel/restart cycles. Separate 0.2 → 0.8 hardware focus-position check passed.
- Paired styled video files decoded successfully with matching frame counts and expected 1920×1080 / 1080×1920 dimensions. Camera input/format/zoom remained preserved after finalization.
- Optimized grading compared against full-source reference rendering for three styles, both crops and their left edges. The working image retains enough pixels for either finished output; single-output resolution is unchanged.
- Ten refreshed marketing PNGs verified as opaque RGB, 1320×2868. The fifteen-page tour and looping frosted summary were visually inspected in the simulator. The summary uses a native repeating transform, pauses off-page/background and respects Reduce Motion.

## Limits and remaining manual checks

Sustained styled Dual Shot is still thermally constrained. A short optimized check approached 29 recorded frames/s before the phone became heavily warmed; later serious-thermal-state tests fell well below the requested 30 fps despite producing valid files. The final retained path preserves output dimensions and grading, reduces redundant working pixels and submits both output renders before waiting. **This is not proof of zero heat, zero lag or sustained requested frame rate on every device.** Profiling on cooled devices and older supported hardware is the next performance priority.

Camera-mode tests above validated delivered resources, not every Photos-library presentation path. Confirm paired Live Photo playback and sound in Photos, depth edges around hair/glass, and full-resolution original/edited sharing manually.

Lock Screen control registration, authentication, actual locked capture and session transfer require hands-on device verification. Both extensions compile, sign and install, but that alone does not prove all system interactions. Also check termination during locked capture and gallery restoration after a real force-quit. No public TestFlight/App Store distribution is enabled by this project’s free Personal Team.

## 1.2.1 responsiveness and reliability checks

- Photo editor now retains a decoded preview and renders adjustments directly to a Metal drawable, removing per-slider debounce, file reads and JPEG roundtrips. On the connected phone, 120 changing slider requests produced 120 preview frames with 6.7 ms p95 render completion time. This measures the render path, not end-to-end touch latency. No camera or Photos writes are involved in this diagnostic.
- Depth capture passed three of three attempts with a camera stop/start between attempts. Photo mode no longer probes recording codecs (format changes can disable depth delivery); compatible depth formats and delivery are restored before capture. This verifies delivered portrait rendering on the connected rear camera, not every lens/device or editable Apple Portrait assets.
- Style/preset management passed hide/reorder/restore, custom-style and preset deletion, reset/undo and Codable persistence checks. Standard remains available; deleted custom recipes remain resolvable for existing photo edits.
- Paired video now renders directly to native 8-bit 4:2:0 encoder buffers, with explicit sRGB transfer and Rec.709 matrix/primaries. A reference-image conversion check measured 0.00402 mean linear RGB error. A ten-second phone check produced 305 frames over 10.07 seconds with both expected output sizes and approximately 301 preview frames per view.
- A later 60-second dual-style recording on an already warm phone produced 1663 frames per file over 60.07 seconds (about 27.7 fps), with 1659 preview frames per view and maximum preview gaps of 97/99 ms. Thermal state rose from fair to serious. Both files decoded, and input/format/zoom survived finalization. Sustained requested 30 fps and low temperature remain open performance targets.
- Camera work pauses behind the photo gallery, retained render caches support a smooth return, redundant starts are ignored, and internal last-session restoration no longer shows a loaded-preset toast. Resume input/format/zoom checks passed. Visual cold-start behavior across other supported phones remains a manual check.
- The camera intent is now included in all three targets, requests foreground routing when unlocked, and the secure extension handles hardware camera events as required by LockedCameraCapture. Both extension privacy manifests declare their own-defaults use. The user confirmed that the camera opens while locked after removing and re-adding the control. Locked capture transfer, interrupted capture and the full authentication matrix remain manual checks.

New Debug checks: `--verify-editor-preview`, `--verify-depth`, `--verify-manager`, and `--verify-nv12`. Diagnostic builds use Release optimization with DEBUG enabled; the installed final release must omit that diagnostic override.

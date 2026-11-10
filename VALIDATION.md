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

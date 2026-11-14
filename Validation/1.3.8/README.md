# Camera 1.3.8 (25)

## Native iPhone 17 Pro
- Seven idle lens selections, including 8× → 0.5×, passed. Selecting another physical lens exits dedicated Focus Lens mode.
- 8×, 0.5× and 1× remained selectable during virtual-camera Log capture. Encoded file cadence passed during the changes.
- 3840×2160 HEVC Apple Log at 30/60 fps and Apple Log 2 at 30/60 fps retained 10-bit depth and matching Log tags. The Log 2 30 fps test used the physical wide camera in Focus Lens mode.
- Sixty-second Log 2 with a LUT monitor and histogram: 1,806 monitor frames, longest steady monitor gap 59.70 ms; encoded 29.993 fps, longest encoded gap after one second 35 ms. Thermal state stayed nominal (0).
- Styled Dual Shot smoke: both previews delivered 63 frames, longest steady gap 37 ms; both 1080p crops were playable, no queued drops, and input/format/zoom were preserved on return. This is a two-second regression, not a new prolonged Dual Shot benchmark.
- Saved session, recording settings, look options and storage preferences were preserved (semantic JSON comparison).
- Plain and styled photo bursts: five captures each, 1.84/2.43 seconds including processing. Test images were removed without saving to Photos.

The raw recording queue bounds latency under overload; it cannot guarantee no dropped frames in every scene or thermal state. Resolution, requested bitrate and 10-bit depth are preserved. Removing encoder frame reordering changes temporal compression strategy; it is not a pixel-identical encode. Nominal iOS thermal state is not a skin-temperature or battery-energy measurement. Tests use this connected 17 Pro, not all older devices or all lighting/recording lengths. The LUT used is the built-in Soft Print test monitor, not every imported LUT.

## Implementation references
Apple’s TN2445 explains how unbounded retained capture buffers can starve the whole session, including preview: https://developer.apple.com/library/archive/technotes/tn2445/_index.html

The installed Xcode AVVideoSettings.h recommends disabling frame reordering for real-time sources and defines distinct Apple Log / Apple Log 2 writer colour properties on iOS 27. The writer uses matching source tags and a source format hint; it does not relabel arbitrary Standard media as Log.

# AirpodMouse — design

Date: 2026-10-29

## Goal

A macOS menu-bar app that turns head-tracking AirPods (tested target: AirPods Pro 3) into a mouse,
used both with hands on the keyboard and fully hands-free.

## Base

Fork of [tony1010-dev/PodMouse](https://github.com/tony1010-dev/PodMouse) @ `2688b79` (MIT), imported as the first commit
of a new local repo. Renamed to AirpodMouse (`com.seungmoyoun.airpodmouse`). Korean + English UI kept.

## Sensor facts that shape the design

- Data comes only from `CMHeadphoneMotionManager` (macOS 14+): attitude, rotation rate, gravity, user acceleration. No raw accelerometer.
- ~25 Hz, not configurable. Yaw has no absolute reference and drifts.
- Only while worn (with Automatic Ear Detection on) and connected to this Mac. Nothing from inside the charging case.

## Removed from PodMouse

Voice input (and mic/speech permissions), head-gesture detection (nod/tilt/shake), joystick and absolute cursor modes, self-test code.

## Cursor (relative mode only)

Per sensor sample: unwrap yaw → One Euro filter on yaw and pitch → speed of filtered deltas →
stillness gate (locks below threshold, unlocks above it, re-locks below half; absorbs drift) →
S-curve gain (`sensitivity × (1 + acceleration × smoothstep(speed))`) → pixel delta pushed into a spreader.

Per display frame (`CADisplayLink`): the spreader hands out the pending delta evenly over the measured sensor interval,
sub-pixel accumulation, clamp to screens, post move event.

Settings: sensitivity, acceleration, jitter filter (0–1 → One Euro min cutoff 4.0–0.4 Hz), stillness threshold, scroll speed, invert X/Y.

## Clicking

- Hotkeys (unchanged): ⌃⌥, left (hold = drag), ⌃⌥. right.
- Stem presses (kept): ×1 left, ×2 right, ×3 **toggle dwell** (was voice). Captured only while mouse mode is on.
- Dwell click (new): cursor stays within `radius` px for `duration` s → left click (drops drag lock if active).
  Ring overlay around the cursor shows progress after 15%. Disarmed after firing and after any other click until the cursor
  leaves the radius, so it never repeat-clicks in place. Off by default; ⌃⌥W, stem ×3, menu, or settings toggle it.

## Code layout

- `PointerMath.swift` — pure logic: `OneEuroFilter`, `PointerCurve`, `StillnessGate`, `MotionSpreader`, `DwellDetector`.
- `MotionEngine.swift` — sensor → pipeline → cursor, dwell callbacks.
- `DwellRing.swift` — click-through ring overlay.
- `AppController.swift`, `Settings.swift`, `SettingsView.swift`, `GuideView.swift`, `HUD.swift`, `StemButtons.swift`, `InputSynth.swift`, `HotKeys.swift` — trimmed from PodMouse.

## Testing

- `./test.sh` compiles `PointerMath.swift` with `Tests/main.swift` and checks filter jitter/lag, curve shape, gate hysteresis,
  spreader totals/evenness, dwell arming/firing/re-arming.
- Feel must be verified by wearing the AirPods; not automatable.

## Possible follow-up

Hand mode (hold an earbud like a pointer, Automatic Ear Detection off): unverified whether data flows; would need axis remapping
and rotation-rate-based movement. Check with the Live Sensors panel first.

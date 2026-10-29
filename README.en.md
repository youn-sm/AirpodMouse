# AirpodMouse

[한국어](README.md) | **English**

A macOS menu-bar app that moves the cursor with the motion sensors in head-tracking AirPods (AirPods Pro, AirPods 3rd gen and later, AirPods Max)
and clicks with shortcuts, AirPods stem presses, or by holding still (dwell click).

A fork of [PodMouse](https://github.com/tony1010-dev/PodMouse) (MIT), trimmed to mouse features with reworked cursor movement and clicking.

## What's different from PodMouse

- **Mouse only**: voice input, head gestures, and joystick/absolute movement modes are removed.
- **Smoother cursor**: a One Euro filter removes jitter, an S-curve speed acceleration, a stillness threshold that locks the cursor when your head stops (absorbs drift),
  and the 25 Hz sensor data is spread evenly across display refreshes.
- **Dwell click**: hold the cursor still and a ring fills, then it clicks. Great for fully hands-free use. Toggle with ⌃⌥W or stem ×3.

## Requirements

- macOS 14 (Sonoma) or later, Apple silicon recommended
- AirPods with head tracking, worn and connected to this Mac
- Xcode or Command Line Tools (`swiftc`)

## Install / build

```bash
./install.sh            # build → install to /Applications/AirpodMouse.app → launch
./build.sh              # just build build/AirpodMouse.app
./test.sh               # test the cursor math
./install.sh uninstall  # remove
```

If you have a developer certificate it's used for signing automatically. Otherwise the app is ad-hoc signed, and you may need to re-enable Accessibility after each rebuild.

Permissions on first launch: **Accessibility** (move and click), **Motion & Fitness** (asked when you put your AirPods in).

## Controls

| Input | Action |
|---|---|
| Turn / raise / lower your head | Move the cursor (slow = precise, fast = far) |
| ⌃⌥ , | Left click · twice = double-click · hold and move your head = drag |
| ⌃⌥ . | Right click |
| AirPods stem ×1 / ×2 / ×3 | Left click / right click / toggle dwell click |
| Hold the cursor still | Dwell click (when on) |

| Shortcut | Function |
|---|---|
| ⌃⌥M | Toggle mouse mode |
| ⌃⌥W | Toggle dwell click |
| ⌃⌥R | Reset + center cursor |
| ⌃⌥D | Start/end drag lock |
| ⌃⌥S | Scroll mode |
| ⌃⌥= / ⌃⌥- | Increase/decrease sensitivity |

- Stem presses only become clicks **while mouse mode is on**; otherwise they're play/pause again.
- AirPods wait to see whether a second press is coming, so a single press clicks about 0.3–0.5 s late.

## Calibration tips

- First check that values move in Settings → **Live Sensors**.
- If the cursor creeps, raise the **stillness threshold** (above the 'Filtered speed' you see while still).
- If it shakes when you stop to click, raise the **jitter filter**.

## Limits

- Head-tracking data comes from Apple's `CMHeadphoneMotionManager` at about 25 Hz, and yaw has no absolute reference so it drifts slowly.
- AirPods must be in your ears and connected to this Mac. They send nothing from inside the charging case.

## License

[MIT](LICENSE) — original PodMouse © 2026 tony1010-dev

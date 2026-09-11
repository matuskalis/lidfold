# LidFold

Menu bar app that folds a frozen capture of the built-in display in 1:1 sync with the physical
lid angle, in the style of the iPhone Duo fold animation.

## Lid angle sensor (MacBookPro18,1, macOS 26.5.2)

IOHIDDevice, Apple internal sensor hub over SPU transport:

| property | value |
|---|---|
| VendorID | `0x05AC` (1452) |
| ProductID | `0x8104` (33028) |
| PrimaryUsagePage | `0x20` |
| PrimaryUsage | `0x8A` |

Angle is a **feature report, report ID 1**, 3 bytes: `[reportID, lo, hi]`. Value is 9 bits
(`element usage 0x47F, reportSize 9, logicalMin 0, logicalMax 360`), so mask with `0x1FF`.
`IOHIDDeviceOpen` succeeds with `kIOHIDOptionsTypeNone` and needs no TCC permission; Input
Monitoring was never requested.

Other feature reports on the same device: id 2 = 1 byte enum, id 3 = 32-bit counter, id 4 = 1 byte
(state). Not used.

With the lid shut the sensor reports exactly `0.0` and keeps answering at 60 Hz. A log of all
zeroes means the lid never moved, not a broken decode — check `ioreg -r -k AppleClamshellState`
before debugging the read path.

## Traps

- **Always launch through `./run.sh`, never `open -a` or Finder.** There is no code signing
  identity on this machine (`security find-identity -v -p codesigning` prints
  `0 valid identities found`), so every build is ad-hoc signed with a fresh cdhash and TCC keys the
  Screen Recording grant to that hash. Launched by launchd the app is a new app to TCC every
  build: capture fails with `SCStreamErrorDomain Code=-3801 "The user declined TCCs"` while the
  Settings toggle still shows LidFold enabled, and the retry loop spams permission prompts.
  Launched from a terminal that already holds Screen Recording, TCC attributes the capture to the
  terminal and it just works. A stable self-signed identity would fix it properly but needs a
  trusted cert in the keychain.
- The Metal toolchain is not installed (`xcrun metal` fails with "missing Metal Toolchain"), so
  the blur is the private `CAFilter` `variableBlur` on the content layer.
- `variableBlur` reads its mask's **alpha**, not luminance. A grayscale ramp with no alpha channel
  blurs uniformly at full radius. `CAFilter` input keys are discoverable: `filter.inputKeys`.
- `lanczosResize` ties output coverage to `inputScale` — at 0.5 it draws at native size but covers
  only a quarter of the layer, so it cannot magnify a backdrop below 2x without leaving holes.
  Not usable for the fold.
- A `CABackdropLayer` samples everything behind it **including its own window's layers**, so an
  opaque background on the host view turns the backdrop black. It also samples in screen space:
  a transform on the backdrop moves where the effect lands but never warps the sampled pixels,
  which is why the standing-content geometry needs a real capture.
- The `IOHIDManager` must be retained for as long as the device is used. Holding only the
  `IOHIDDevice` returned from a function whose manager was a local closes the device, and every
  `IOHIDDeviceGetReport` then fails silently — the menu shows "Lid angle sensor not found" while a
  standalone spike with a process-lifetime manager works fine.
- Arm threshold must stay below a normal working angle. Measured resting angle on this machine is
  97-103°; arming at 112° hit during ordinary use. The effect must never run above 90°: arm below
  88°, disarm above 90°.
- Do not set `layer.isGeometryFlipped` on the overlay's root layer: it flips every sublayer
  gradient and inverts the effect. With it off, `startPoint = (0.5, 0)` / `endPoint = (0.5, 1)`
  puts gradient location 0 at the **top** of the screen, which is `fromHinge = 1` (a MacBook's
  hinge is the bottom edge of the display). Both inversions cost a rebuild each to spot, so check
  a screenshot rather than reasoning about the axis.
- The overlay must never arm while the built-in panel is asleep or the lid is shut. `FoldController.tick` checks
  `CGDisplayIsActive` / `CGDisplayIsAsleep` plus a 3° floor.

## The Duo effect

Formulas taken from the two public recreations, adapted to a bottom hinge. `fromHinge` is 0 at the
bottom of the display and 1 at the top; `motion = smoothstep(0, 1, progress)`.

| element | formula |
|---|---|
| blur radius | `72 * motion * pow(fromHinge, 1.35)`, applied as 6 stacked bands |
| darkening | `effect = motion * pow(clamp((fromHinge - 0.2) / 0.8), 1.35)`, `color *= 1 - min(1, effect * 2)` |
| glass tint | `rgb(0.82, 0.85, 0.86)` at `0.20 * motion`, soft light |
| reflection | narrow band at `fromHinge ≈ 0.65`, `0.06 * motion` |

Apple keeps the content in a fixed front-view projection — the device half rotates, the picture
does not tip in 3D. An earlier version used `rotation3DEffect` and read as a tilting screenshot;
that is macTilt's reading, not Apple's.

Real variable-radius blur over the live desktop comes from the private `CABackdropLayer` plus
`CAFilter` `gaussianBlur` with `inputRadius` set per band through
`setValue(_:forKeyPath: "filters.gaussianBlur.inputRadius")`. Both classes resolve on macOS 26.5.
`NSVisualEffectView` only offers fixed material radii, which cannot follow the curve.

Dev overrides, read at launch (`LIDFOLD_ARM=130 LIDFOLD_PROGRESS=0.75 /Applications/LidFold.app/Contents/MacOS/LidFold`):
`LIDFOLD_ARM`, `LIDFOLD_DISARM`, `LIDFOLD_PROGRESS` pin the thresholds and the fold amount so the
look can be screenshotted without touching the lid.

## Build

```
./build.sh            # build/LidFold.app
./build.sh install    # kill, install to /Applications, keep signature identity
./build.sh spike      # build/spike, prints the raw angle at 60 Hz for 30 s
```

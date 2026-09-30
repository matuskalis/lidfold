# LidFold

Menu bar app that folds a frozen capture of the built-in display in 1:1 sync with the physical
lid angle, in the style of the iPhone Duo fold animation.

## Layout

- `Sources/LidFoldCore/`: pure logic, no AppKit. `FoldModel` (angle to fold, all the curves, the silhouette
  geometry), `LidSensor` (report decode, `AngleFilter` smoothing and poll throttle), `AngleSimulation`
  (scripted lid). Unit tested.
- `Sources/*.swift`: the app shell (IOKit read, ScreenCaptureKit freeze, overlay window and view, menu bar).
- `Tools/`: `spike.swift` (sensor probe), `render.swift` (offscreen renderer), `standin/` (generated stand-in
  desktop), `hero.sh` (regenerates `docs/` media).
- `Package.swift` exists only so `swift test` can build the core. `build.sh` compiles the same core files into
  the app with `swiftc`. Core types stay `internal`; the tests use `@testable import`.

## Lid angle sensor (MacBookPro18,1, macOS 26.5.2, read path rechecked on 27.0)

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

Probed earlier: id 2 = 1 byte enum, id 3 = 32-bit counter, id 4 = 1 byte (state). Not used. The descriptor
in `ioreg -r -c AppleSPUHIDDevice -l` declares ids 1 to 8 (id 6 as an output, id 7 as a 50-bit field with
range 0 to 36000); their meaning is unverified.

With the lid shut the sensor reports exactly `0.0` and keeps answering at 60 Hz. A log of all
zeroes means the lid never moved, not a broken decode: check `ioreg -r -k AppleClamshellState`
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
- `lanczosResize` ties output coverage to `inputScale`: at 0.5 it draws at native size but covers
  only a quarter of the layer, so it cannot magnify a backdrop below 2x without leaving holes.
  Not usable for the fold.
- A `CABackdropLayer` samples everything behind it **including its own window's layers**, so an
  opaque background on the host view turns the backdrop black. It also samples in screen space:
  a transform on the backdrop moves where the effect lands but never warps the sampled pixels,
  which is why the standing-content geometry needs a real capture.
- The `IOHIDManager` must be retained for as long as the device is used. Holding only the
  `IOHIDDevice` returned from a function whose manager was a local closes the device, and every
  `IOHIDDeviceGetReport` then fails silently: the menu shows "Lid angle sensor not found" while a
  standalone spike with a process-lifetime manager works fine.
- Arm threshold must stay below a normal working angle. Measured resting angle on this machine is
  97-103°; arming at 112° hit during ordinary use. The effect must never run above 90°: the fold starts
  below 88° and the overlay is removed above 90°.
- Do not set `layer.isGeometryFlipped` on the overlay's root layer: it flips every sublayer
  gradient and inverts the effect. With it off, `startPoint = (0.5, 0)` / `endPoint = (0.5, 1)`
  puts gradient location 0 at the **top** of the screen, which is `fromHinge = 1` (a MacBook's
  hinge is the bottom edge of the display). Both inversions cost a rebuild each to spot, so check
  a screenshot rather than reasoning about the axis.
- The overlay must never arm while the built-in panel is asleep or the lid is shut. `FoldController.tick` checks
  `CGDisplayIsActive` / `CGDisplayIsAsleep` plus a 3° floor.
- `CARenderer` (used by `Tools/render.swift`) draws nothing until `CATransaction.flush()` has run, and its
  texture is stored bottom row first, so flip it. It does apply the private `variableBlur`. When timing it,
  change the state every frame: Core Animation skips unchanged frames and reports 0.2 ms.
- A lossy animated WebP with long runs of delta frames smears artifacts into the still parts of the picture.
  `Tools/hero.sh` forces a key frame every 4 frames.

## The Duo effect

Formulas taken from the two public recreations, adapted to a bottom hinge and since tuned. `fromHinge` is 0 at
the bottom of the display and 1 at the top; `motion = smoothstep(0, 1, progress)`; `progress` is
`(88 - angle) / (88 - 5)` clamped to 0...1. The constants live in `FoldModel`.

| element | formula |
|---|---|
| blur radius | one `variableBlur`, `96 * pow(progress, 0.7)`, mask alpha `pow(fromHinge, 1.35)` per row |
| darkening | six black stops, alpha `min(1, 1.5 * motion * pow(clamp((fromHinge - 0.2) / 0.8), 1.35))` |
| glass tint | `rgb(0.82, 0.85, 0.86)` at `0.20 * motion`, soft light |
| reflection | narrow band at `fromHinge ≈ 0.65`, `0.06 * motion` |

Frost (the blur) leads the geometry on purpose: the fold looks empty if the picture is still crisp once the
panel has visibly moved. The content swings away about the hinge by `0.55 * (88 - angle)` degrees under a fixed
camera (`m34 = -1/3000`), foreshortening into a trapezoid while black void opens behind it. Two earlier
readings were wrong: a pure blur sweep with no geometry, and a "standing content" homography that magnified
the desktop to keep it fixed in space. The giveaway is the void: Apple's transition opens black space as the
half recedes, so the content must get smaller, not larger.

`build/render --verify` checks the silhouette geometry against what Core Animation draws: worst error
0.6 px on a 3456x2234 frame, and it fails above 3 px.

An earlier version blurred the live desktop with the private `CABackdropLayer` plus `CAFilter` `gaussianBlur`
with `inputRadius` set per band through `setValue(_:forKeyPath: "filters.gaussianBlur.inputRadius")`. Both
classes resolved on macOS 26.5. `NSVisualEffectView` only offers fixed material radii, which cannot follow the
curve.

## Running without the lid

All read at launch:

| variable | effect |
|---|---|
| `LIDFOLD_SIMULATE=open:closed:seconds[:hold]` | scripted lid in whole degrees, for example `100:5:3:0.5`, repeating |
| `LIDFOLD_ARM`, `LIDFOLD_DISARM` | fold start angle (88) and the angle above which the overlay is removed (90) |
| `LIDFOLD_PROGRESS`, `LIDFOLD_TILT` | pin the fold amount and the tilt in degrees |
| `LIDFOLD_EYE_Z`, `LIDFOLD_SWING` | viewing distance in points (3000) and swing per degree of lid travel (0.55) |

Pinning a fold at the resting angle needs `LIDFOLD_DISARM` raised too, otherwise the overlay is removed
above 90°: `LIDFOLD_ARM=130 LIDFOLD_DISARM=130 LIDFOLD_PROGRESS=0.75`. `LIDFOLD_SIMULATE` is simpler. The
overlay still needs Screen Recording, so use `Tools/render.swift` when you only need pictures.

## Build

```
./build.sh            # build/LidFold.app
./build.sh install    # kill, install to /Applications, keep signature identity
./build.sh spike      # build/spike [seconds]: raw angle on change, then rate and read latency
./build.sh render     # build/render: offscreen frames, --verify, --bench, --table
swift test            # the core's unit tests
Tools/hero.sh         # regenerate docs/lidfold.webp and the stills (needs img2webp)
```

`run.sh` runs `build/LidFold.app` when it exists, otherwise the installed copy.

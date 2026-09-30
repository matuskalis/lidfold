# Measurements

Raw output of the commands the README quotes. All from one machine on 30 Sep 2026: MacBookPro18,1
(16-inch, M1 Pro), macOS 27.0 (build 26A428), Apple Swift 6.4, lid open at 103 degrees and not touched.
The laptop was shared with other heavy work (load average 85 to 140 during the runs), so treat the tails
(p95, max) as pessimistic.

## Sensor: `build/spike 30`

```
devices matched: 1
first report: 01 67 00
  0.000 s   103.0
1875 reads in 30.0 s, 0 failed, 1 distinct angles
timer interval ms: mean 16.01 (62.5 Hz)  p50 16.20  p95 19.07  p99 20.78  max 35.06
read latency us: p50 664  p95 1378  p99 3860  max 9557
```

- The spike uses the same matching dictionary, report and timer (16 ms, 2 ms leeway) as `LidAngleReader`.
- `01 67 00` is report ID 1 followed by the little-endian 9-bit angle: `0x067` is 103.
- One distinct angle because the lid did not move, so the step size is **not verified by motion**. The
  report descriptor declares the field as 9 bits with logical and physical range 0 to 360, which reads as
  one count per degree. The descriptor's unit item comes after this field, so the descriptor alone does not
  label it degrees; 103 with a resting lid and 0 with a shut one is what makes that reading safe. Move the
  lid while `build/spike` runs and it prints every change.

`ioreg -r -c AppleSPUHIDDevice -l` lists the device as product `las`, transport `SPU`, `Built-In = Yes`,
vendor 1452 (0x05AC), product 33028 (0x8104), usage page 32 (0x20), usage 138 (0x8A). The descriptor starts
`05 20 09 8a a1 01 85 01 0a 7f 04 46 68 01 34 26 68 01 14 75 09 95 01 81 02`, which reads as: usage page
Sensor, usage 0x8A, report ID 1, usage 0x47F, physical and logical maximum 360, minimum 0, report size 9.
Reports 2 to 8 are declared too and are not used.

## Overlay: `build/render --source Tools/standin/desktop.jpg --bench 300`

```
render 3456x2234, 300 frames that all differ: p50 4.03 ms  p95 8.28 ms  max 12.49 ms
view.update on the main thread, 3000 calls: p50 15 us  p95 26 us  max 724 us
```

- This is the real `FoldOverlayView` (transform, private `variableBlur`, darkening, glass) drawn through
  `CARenderer` into a retina-size Metal texture, waiting for the GPU each frame. It is not the window server's
  compositor, so it says what a frame costs, not what the screen shows.
- Every frame differs from the last. Core Animation skips unchanged frames, and an earlier run that did not
  vary the state reported 0.2 ms, which was meaningless.
- `view.update` is what the app does on the main thread every 1/60 s: one `CATransaction`, a transform, a
  blur radius, six gradient colours, two opacities.

## Idle cost: the app with a simulated open lid

```
LIDFOLD_SIMULATE=120:100:5 build/LidFold.app/Contents/MacOS/LidFold
top -l 4 -s 2 -pid <pid> -stats pid,command,cpu,idlew,power
   %CPU 0.2, 0.4, 0.6 over three 2 s samples; idle wakeups reported as 0
```

The simulated lid stays between 120 and 100 degrees, so the overlay never arms, nothing is captured, and there
are no IOKit reads. What remains is the sensor timer (polled every sixth tick, since the lid is open) and the
main-thread timer, which fires 60 times a second whatever the angle. `top` reported zero idle wakeups, which
does not fit a 60 Hz timer, so read that column as unreliable and the CPU figure as the usable one.

## Fold model against the renderer: `build/render --verify`

```
tilt   far edge row, model / drawn   half width 60 px below it, model / drawn
  10       86.9 /     87.0              1670.1 /   1670.0
  30      296.8 /    297.0              1567.8 /   1568.0
  50      543.1 /    543.0              1483.5 /   1484.0
  70      814.6 /    815.0              1416.4 /   1417.0
  85     1029.9 /   1030.0              1377.5 /   1378.0
worst error 0.6 px on a 3456x2234 frame
```

A flat light picture is swung with no blur or darkening and its edges are found by threshold. The "model"
column is `FoldModel.silhouette`, plain trigonometry on the constants in `FoldConfiguration`.

## Refactor equivalence

`Tools/check-refactor.sh` builds the overlay view as it was before the maths moved into `LidFoldCore` (commit
78f7bae, read from git history) and as it is now, draws eight lid angles (87, 75, 60, 45, 30, 15, 5 and 4
degrees) over `Tools/standin/desktop.jpg` with each, and compares the PNG files byte for byte. On the test machine
all eight were identical. An earlier run of the same comparison over a synthetic test pattern was identical at
the same angles too. The script needs the full git history. It does fail when it should: with the darkness gain
changed from 1.5 to 2.0 all eight frames differed.

## Tests and build

```
swift test          Executed 47 tests, with 0 failures (0 unexpected) in 0.014 seconds
./build.sh          10.3 s wall, build/LidFold.app, executable 217,632 bytes
```

Mutation check, run once by hand: ten one-line mutations of the core (smoothing 0.4 to 0.5, mask
0x1FF to 0xFF, poll divisor 6 to 5, stale comparison, darkness gain, disarm comparison, frost exponent,
silhouette cosine, a tilt clamp, the simulation hold boundary). Nine were caught. The survivor changes
`opening < 0` to `opening <= 0` in `AngleSimulation`, which returns the same value on both sides of the
boundary, so it is not observable.

## From the app's own log

`~/Library/Logs/lidfold.log` on the author's machine (37 lines, 11 to 17 Sep 2026) is where the app writes its
`lidLog` messages. It holds 34 lines of the form `overlay shown at angle <filtered angle> progress <progress>`.
24 of them follow the fold mapping exactly. The other ten were written by dev runs with `LIDFOLD_PROGRESS` pinned
(progress 0.28 to 0.75 at angles 95 and 96, above the disarm angle), so they do not. Three of the 24:

```
2026-09-12T09:28:04Z overlay shown at angle 84.19932936192 progress 0.04579121250698803
2026-09-12T11:08:28Z overlay shown at angle 23.166336525959167 progress 0.7811284755908534
2026-09-13T19:34:25Z overlay shown at angle 84.28952754293913 progress 0.04470448743446836
```

`FoldPresentationTests.testReproducesTheProgressTheAppLoggedOnTheAuthorsMachine` carries all 24 lines verbatim and
matches each progress value to the last digit through `FoldModel.presentation`. The log lives in `~/Library/Logs`,
not in the repository, so the test holds the lines itself, and every one of them can be found in the log with
`grep -F`. What the log does not say is how the lid was moved. The fractional angles are the exponential average
at work, not raw readings.

## CI

The workflow in `.github/workflows/ci.yml` passed on the pull request on both runners, running `swift test`,
`./build.sh`, the spike and render builds and `build/render --verify`:

```
macos-15  Apple Swift 6.1.2   Executed 47 tests, with 0 failures   worst error 0.6 px on a 3456x2234 frame
macos-26  Apple Swift 6.3.3   Executed 47 tests, with 0 failures   worst error 0.6 px on a 3456x2234 frame
```

The runners are virtual machines, so this shows that Metal and `CARenderer` are available there and that the
private blur filter resolves. It says nothing about the sensor, which only exists on the real machine.

# LidFold

The iPhone Duo fold animation, driven by the MacBook's real lid angle sensor.

Close the lid and the built-in display freezes, swings away about the hinge into a foreshortened
trapezoid, and frosts with a progressive blur as black void opens behind it. The hinge is the
scrubber: there is no timeline, reverse the lid mid-way and the fold reverses with it.

- Built-in display only. Nothing renders on external monitors.
- The effect never runs above 90°: it engages below 88° and releases above 90°. Full fold at 5°.
- Launch with `./run.sh` from a terminal that already has Screen Recording. No prompts.

```
./build.sh install && ./run.sh
```

## Debug

`~/Library/Logs/lidfold.log` records when the overlay arms and any capture failure.

Dev overrides, read at launch:

```
LIDFOLD_ARM=130 LIDFOLD_PROGRESS=0.6 LIDFOLD_TILT=60 /Applications/LidFold.app/Contents/MacOS/LidFold
```

`LIDFOLD_ARM`, `LIDFOLD_DISARM`, `LIDFOLD_TILT`, `LIDFOLD_PROGRESS` pin the thresholds and the
fold amount so the look can be screenshotted without touching the lid. `LIDFOLD_EYE_Z` (default
1500) sets the viewing distance in points — shorter means harder perspective and more void —
and `LIDFOLD_SWING` (default 1.0) scales how far the content swings per degree of lid travel.

## Credit

Sensor reverse engineering: [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor),
[pybooklid](https://github.com/tcsenpai/pybooklid). Fold maths read from
[macTilt](https://github.com/lqSky7/iphone-duo-macos-animation) and
[iphone-duo](https://github.com/chuspeeism/iphone-duo).

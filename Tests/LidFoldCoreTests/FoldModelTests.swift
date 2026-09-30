import XCTest
@testable import LidFoldCore

final class FoldPresentationTests: XCTestCase {
    private let defaults = FoldConfiguration()

    private func fold(_ angle: Double, _ configuration: FoldConfiguration? = nil) -> (progress: Double, tilt: Double)? {
        guard case let .fold(progress, tilt) = FoldModel.presentation(angle: angle, configuration: configuration ?? defaults) else {
            return nil
        }
        return (progress, tilt)
    }

    func testDefaultsKeepTheEffectBelowANormalWorkingAngle() {
        XCTAssertLessThanOrEqual(defaults.disarmAbove, 90)
        XCTAssertLessThan(defaults.armBelow, defaults.disarmAbove)
        XCTAssertLessThan(defaults.closedAngle, defaults.armBelow)
        XCTAssertLessThan(defaults.minVisibleAngle, defaults.closedAngle)
    }

    func testHiddenWhenTheLidIsOpenPastTheDisarmAngle() {
        XCTAssertNil(fold(103))
        XCTAssertNil(fold(97))
        XCTAssertNil(fold(90.0001))
    }

    func testHiddenWhenTheLidIsEffectivelyShut() {
        XCTAssertNil(fold(2.99))
        XCTAssertNil(fold(0))
    }

    func testTheTwoDegreeBandBelowNinetyShowsTheFrozenPictureUnfolded() {
        for angle in [90.0, 89.0, 88.0] {
            let state = fold(angle)
            XCTAssertEqual(state?.progress, 0, "angle \(angle)")
            XCTAssertEqual(state?.tilt, 0, "angle \(angle)")
        }
    }

    func testProgressRunsLinearlyFromArmAngleToClosedAngle() {
        XCTAssertEqual(fold(87)!.progress, 1.0 / 83.0, accuracy: 1e-12)
        XCTAssertEqual(fold(46.5)!.progress, 0.5, accuracy: 1e-12)
        XCTAssertEqual(fold(5)!.progress, 1, accuracy: 1e-12)
    }

    func testTiltKeepsGrowingPastTheClosedAngleWhileProgressStopsAtOne() {
        XCTAssertEqual(fold(5)!.tilt, 83)
        XCTAssertEqual(fold(4)!.progress, 1)
        XCTAssertEqual(fold(4)!.tilt, 84)
        XCTAssertEqual(fold(3)!.tilt, 85)
    }

    func testProgressNeverDecreasesAsTheLidCloses() {
        var last = -1.0
        for tenths in stride(from: 900, through: 30, by: -1) {
            guard let state = fold(Double(tenths) / 10) else { continue }
            XCTAssertGreaterThanOrEqual(state.progress, last)
            last = state.progress
        }
        XCTAssertEqual(last, 1)
    }

    /// Lines the app wrote to ~/Library/Logs/lidfold.log on the author's machine, copied unchanged. That log
    /// has 34 "overlay shown" lines from 11 to 13 Sep 2026. These are the 24 that follow the fold mapping; the
    /// other ten come from dev runs with LIDFOLD_PROGRESS pinned (angles 95 and 96, above the disarm angle).
    private let appLogLines = """
        2026-09-11T17:43:05Z overlay shown at angle 17.0 progress 0.8554216867469879
        2026-09-12T09:27:41Z overlay shown at angle 33.99597471443399 progress 0.6506509070550122
        2026-09-12T09:28:04Z overlay shown at angle 84.19932936192 progress 0.04579121250698803
        2026-09-12T09:28:08Z overlay shown at angle 83.46997861260692 progress 0.05457857093244672
        2026-09-12T09:28:10Z overlay shown at angle 80.39738427448233 progress 0.09159777982551405
        2026-09-12T09:28:17Z overlay shown at angle 87.0896956896839 progress 0.010967521811037434
        2026-09-12T09:39:04Z overlay shown at angle 82.76769786965932 progress 0.06303978470289981
        2026-09-12T09:39:19Z overlay shown at angle 86.24940431353748 progress 0.02109151429472913
        2026-09-12T11:08:28Z overlay shown at angle 23.166336525959167 progress 0.7811284755908534
        2026-09-12T17:13:17Z overlay shown at angle 82.30633862233655 progress 0.06859832985136682
        2026-09-12T20:45:14Z overlay shown at angle 85.877262336 progress 0.025575152578313238
        2026-09-12T20:45:21Z overlay shown at angle 78.16379579796079 progress 0.11850848436191823
        2026-09-12T20:45:24Z overlay shown at angle 80.54553216220347 progress 0.08981286551562083
        2026-09-12T20:45:31Z overlay shown at angle 67.78757951488 progress 0.24352313837493983
        2026-09-12T21:15:49Z overlay shown at angle 65.01294833760207 progress 0.27695242966744493
        2026-09-12T21:21:22Z overlay shown at angle 82.513091584 progress 0.06610733031325308
        2026-09-12T21:21:25Z overlay shown at angle 79.60821195980506 progress 0.10110588000234866
        2026-09-12T21:21:27Z overlay shown at angle 81.37292847124068 progress 0.07984423528625682
        2026-09-12T21:21:31Z overlay shown at angle 84.79046333751768 progress 0.03866911641544966
        2026-09-12T21:21:43Z overlay shown at angle 75.22497896448017 progress 0.15391591609060035
        2026-09-13T17:45:45Z overlay shown at angle 83.16947549376353 progress 0.058199090436584
        2026-09-13T17:45:50Z overlay shown at angle 82.55221800015774 progress 0.06563592770894293
        2026-09-13T17:45:53Z overlay shown at angle 75.90671009516228 progress 0.145702288010093
        2026-09-13T19:34:25Z overlay shown at angle 84.28952754293913 progress 0.04470448743446836
        """

    func testReproducesTheProgressTheAppLoggedOnTheAuthorsMachine() throws {
        let lines = appLogLines.split(separator: "\n")
        XCTAssertEqual(lines.count, 24)
        for line in lines {
            // <timestamp> overlay shown at angle <filtered angle> progress <progress>
            let words = line.split(separator: " ")
            let angle = try XCTUnwrap(Double(words[5]), String(line))
            let logged = try XCTUnwrap(Double(words[7]), String(line))
            XCTAssertEqual(fold(angle)?.progress ?? -1, logged, accuracy: 1e-15, String(line))
        }
    }

    func testOverridesReplaceTheTrackedValues() {
        var pinned = defaults
        pinned.progressOverride = 0.6
        pinned.tiltOverride = 60
        let state = fold(40, pinned)
        XCTAssertEqual(state?.progress, 0.6)
        XCTAssertEqual(state?.tilt, 60)
    }

    func testRaisingTheArmAngleAloneDoesNotShowTheOverlayAtARestingAngle() {
        // The documented way to preview the fold without touching the lid used to omit LIDFOLD_DISARM.
        let armOnly = FoldConfiguration(environment: ["LIDFOLD_ARM": "130", "LIDFOLD_PROGRESS": "0.6"])
        XCTAssertNil(fold(103, armOnly))

        let both = FoldConfiguration(environment: ["LIDFOLD_ARM": "130", "LIDFOLD_DISARM": "130"])
        let state = fold(103, both)
        XCTAssertEqual(state?.progress ?? -1, 27.0 / 125.0, accuracy: 1e-12)
        XCTAssertEqual(state?.tilt, 27)
    }
}

final class FoldConfigurationTests: XCTestCase {
    func testEmptyEnvironmentGivesTheShippedDefaults() {
        let configuration = FoldConfiguration(environment: [:])
        XCTAssertEqual(configuration, FoldConfiguration())
        XCTAssertEqual(configuration.armBelow, 88)
        XCTAssertEqual(configuration.disarmAbove, 90)
        XCTAssertEqual(configuration.eyeDistance, 3000)
        XCTAssertEqual(configuration.swing, 0.55)
        XCTAssertNil(configuration.progressOverride)
        XCTAssertNil(configuration.simulation)
    }

    func testReadsEveryDocumentedVariable() {
        let configuration = FoldConfiguration(environment: [
            "LIDFOLD_ARM": "120", "LIDFOLD_DISARM": "125", "LIDFOLD_PROGRESS": "0.25", "LIDFOLD_TILT": "30",
            "LIDFOLD_EYE_Z": "1500", "LIDFOLD_SWING": "0.8", "LIDFOLD_SIMULATE": "100:5:3",
        ])
        XCTAssertEqual(configuration.armBelow, 120)
        XCTAssertEqual(configuration.disarmAbove, 125)
        XCTAssertEqual(configuration.progressOverride, 0.25)
        XCTAssertEqual(configuration.tiltOverride, 30)
        XCTAssertEqual(configuration.eyeDistance, 1500)
        XCTAssertEqual(configuration.swing, 0.8)
        XCTAssertEqual(configuration.simulation?.sweepSeconds, 3)
    }

    func testUnparseableValuesFallBackToDefaults() {
        let configuration = FoldConfiguration(environment: [
            "LIDFOLD_ARM": "steep", "LIDFOLD_PROGRESS": "", "LIDFOLD_SIMULATE": "fast",
        ])
        XCTAssertEqual(configuration, FoldConfiguration())
    }
}

final class FoldFrameTests: XCTestCase {
    private let defaults = FoldConfiguration()

    func testSmoothstepIsPinnedAtTheEndsAndSymmetric() {
        XCTAssertEqual(FoldModel.smoothstep(0), 0)
        XCTAssertEqual(FoldModel.smoothstep(0.5), 0.5)
        XCTAssertEqual(FoldModel.smoothstep(1), 1)
        for x in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(FoldModel.smoothstep(x) + FoldModel.smoothstep(1 - x), 1, accuracy: 1e-12)
        }
    }

    func testNothingIsDrawnAtProgressZero() {
        let frame = FoldModel.frame(progress: 0, tiltDegrees: 0, configuration: defaults)
        XCTAssertEqual(frame.blurRadius, 0)
        XCTAssertEqual(frame.darkness, Array(repeating: 0, count: 6))
        XCTAssertEqual(frame.glassOpacity, 0)
        XCTAssertEqual(frame.reflectionOpacity, 0)
        XCTAssertEqual(frame.rotationRadians, 0)
    }

    func testFullFoldNumbers() {
        let frame = FoldModel.frame(progress: 1, tiltDegrees: 83, configuration: defaults)
        XCTAssertEqual(frame.blurRadius, 96, accuracy: 1e-12)
        XCTAssertEqual(frame.glassOpacity, 0.20, accuracy: 1e-12)
        XCTAssertEqual(frame.reflectionOpacity, 0.06, accuracy: 1e-12)
        XCTAssertEqual(frame.rotationRadians, -0.7967428035354115, accuracy: 1e-12)
        XCTAssertEqual(frame.perspective, -1.0 / 3000.0, accuracy: 1e-15)
        let expected = [1, 1, 0.5884380734225629, 0.2308395775021716, 0, 0]
        for (actual, wanted) in zip(frame.darkness, expected) {
            XCTAssertEqual(actual, wanted, accuracy: 1e-12)
        }
    }

    func testHalfFoldNumbers() {
        let frame = FoldModel.frame(progress: 0.5, tiltDegrees: 41.5, configuration: defaults)
        XCTAssertEqual(frame.motion, 0.5, accuracy: 1e-12)
        XCTAssertEqual(frame.frost, 0.6155722066724582, accuracy: 1e-12)
        XCTAssertEqual(frame.blurRadius, 59.09493184055599, accuracy: 1e-9)
        let expected = [0.75, 0.5086206270637853, 0.29421903671128147, 0.1154197887510858, 0, 0]
        for (actual, wanted) in zip(frame.darkness, expected) {
            XCTAssertEqual(actual, wanted, accuracy: 1e-12)
        }
    }

    func testTheHingeEndOfTheGradientIsNeverDarkened() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            let darkness = FoldModel.frame(progress: progress, tiltDegrees: 0, configuration: defaults).darkness
            XCTAssertEqual(darkness.last, 0)
            XCTAssertEqual(darkness[4], 0)
            XCTAssertEqual(darkness, darkness.sorted(by: >), "darkness grows away from the hinge")
        }
    }

    func testFrostLeadsTheEasedMotionThroughTheFirstTwoThirdsOfTheFold() {
        for progress in stride(from: 0.05, through: 0.65, by: 0.05) {
            let frame = FoldModel.frame(progress: progress, tiltDegrees: 0, configuration: defaults)
            XCTAssertGreaterThan(frame.frost, frame.motion, "progress \(progress)")
        }
    }

    func testSwingScalesTheRotationOnly() {
        var stiff = defaults
        stiff.swing = 0.275
        let base = FoldModel.frame(progress: 0.4, tiltDegrees: 50, configuration: defaults)
        let half = FoldModel.frame(progress: 0.4, tiltDegrees: 50, configuration: stiff)
        XCTAssertEqual(half.rotationRadians, base.rotationRadians / 2, accuracy: 1e-12)
        XCTAssertEqual(half.blurRadius, base.blurRadius)
        XCTAssertEqual(half.darkness, base.darkness)
    }
}

final class BlurMaskTests: XCTestCase {
    func testRampRunsFromOpaqueAtTheFarEdgeToClearAtTheHinge() {
        XCTAssertEqual(FoldModel.blurMaskByte(row: 0, rows: 512), 255)
        XCTAssertEqual(FoldModel.blurMaskByte(row: 511, rows: 512), 0)
    }

    func testRampFollowsThePowerCurve() {
        let expected = [1: 254, 128: 172, 255: 100, 256: 99, 300: 77, 510: 0]
        for (row, byte) in expected {
            XCTAssertEqual(Int(FoldModel.blurMaskByte(row: row, rows: 512)), byte, "row \(row)")
        }
    }

    func testRampNeverIncreasesTowardTheHinge() {
        let bytes = (0..<512).map { FoldModel.blurMaskByte(row: $0, rows: 512) }
        XCTAssertEqual(bytes, bytes.sorted(by: >))
    }
}

final class SilhouetteTests: XCTestCase {
    private let defaults = FoldConfiguration()
    private let panelHeight = 1117.0

    func testUntiltedPictureFillsThePanel() {
        let shape = FoldModel.silhouette(tiltDegrees: 0, panelHeight: panelHeight, configuration: defaults)
        XCTAssertEqual(shape.farEdgeWidth, 1)
        XCTAssertEqual(shape.farEdgeHeight, 1)
    }

    func testFullFoldOnASixteenInchPanel() {
        let shape = FoldModel.silhouette(tiltDegrees: 83, panelHeight: panelHeight, configuration: defaults)
        XCTAssertEqual(shape.farEdgeWidth, 0.789733945710675, accuracy: 1e-12)
        XCTAssertEqual(shape.farEdgeHeight, 0.5520552850474609, accuracy: 1e-12)
    }

    func testThePictureOnlyGetsSmallerAsTheLidCloses() {
        var width = 1.0
        var height = 1.0
        for tilt in stride(from: 0.0, through: 85.0, by: 1.0) {
            let shape = FoldModel.silhouette(tiltDegrees: tilt, panelHeight: panelHeight, configuration: defaults)
            XCTAssertLessThanOrEqual(shape.farEdgeWidth, width)
            XCTAssertLessThanOrEqual(shape.farEdgeHeight, height)
            width = shape.farEdgeWidth
            height = shape.farEdgeHeight
        }
    }

    func testAShorterViewingDistanceOpensMoreVoid() {
        var close = defaults
        close.eyeDistance = 1500
        let normal = FoldModel.silhouette(tiltDegrees: 60, panelHeight: panelHeight, configuration: defaults)
        let harder = FoldModel.silhouette(tiltDegrees: 60, panelHeight: panelHeight, configuration: close)
        XCTAssertLessThan(harder.farEdgeHeight, normal.farEdgeHeight)
        XCTAssertLessThan(harder.farEdgeWidth, normal.farEdgeWidth)
    }
}

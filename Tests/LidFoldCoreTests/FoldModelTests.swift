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

    func testReproducesTheProgressLoggedDuringRealCloses() {
        // "overlay shown at angle <filtered angle> progress <progress>" lines from ~/Library/Logs/lidfold.log,
        // written by the app on 11 Sep 2026 while a lid was being closed by hand.
        let logged: [(angle: Double, progress: Double)] = [
            (79.28377468577379, 0.1050147628220025),
            (82.36284323075168, 0.06791755143672676),
            (82.89203692304005, 0.061541723818794546),
            (78.86901891168226, 0.11001182034117758),
            (36.40022154148321, 0.6216840778134552),
            (12.5998135296, 0.9084359815710844),
            (71.669074219008, 0.1967581419396627),
        ]
        for entry in logged {
            XCTAssertEqual(fold(entry.angle)?.progress ?? -1, entry.progress, accuracy: 1e-15, "angle \(entry.angle)")
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

import XCTest
@testable import LidFoldCore

final class AngleSimulationTests: XCTestCase {
    func testParsesThreeAndFourFieldSpecifications() {
        let plain = AngleSimulation(specification: "100:5:3")
        XCTAssertEqual(plain, AngleSimulation(openAngle: 100, closedAngle: 5, sweepSeconds: 3, holdSeconds: 0))
        let held = AngleSimulation(specification: "100:5:3:0.5")
        XCTAssertEqual(held?.holdSeconds, 0.5)
    }

    func testRejectsMalformedSpecifications() {
        for bad in ["", "100", "100:5", "100:5:0", "100:5:-1", "a:b:c", "100:5:3:-1", "100:5:3:x", "1:2:3:4:5", "100::3"] {
            XCTAssertNil(AngleSimulation(specification: bad), bad)
        }
    }

    func testWalksDownHoldsAndWalksBack() throws {
        let lid = try XCTUnwrap(AngleSimulation(specification: "100:5:2:1"))
        let expected: [(Double, Double)] = [
            (0, 100), (0.99, 100), (1, 100),
            (2, 53), (3, 5),
            (3.5, 5), (4, 5),
            (5, 53), (6, 100), (7, 100), (8, 53),
        ]
        for (time, angle) in expected {
            XCTAssertEqual(lid.angle(at: time), angle, "t = \(time)")
        }
    }

    func testOnlyEverReportsWholeDegreesInsideTheSweep() throws {
        let lid = try XCTUnwrap(AngleSimulation(specification: "100:5:2.5:0.3"))
        for step in 0..<1200 {
            let angle = lid.angle(at: Double(step) / 60)
            XCTAssertEqual(angle, angle.rounded())
            XCTAssertTrue((5...100).contains(angle), "t = \(Double(step) / 60)")
        }
    }

    func testSweepsUpwardsToo() throws {
        let lid = try XCTUnwrap(AngleSimulation(specification: "10:90:4"))
        XCTAssertEqual(lid.angle(at: 0), 10)
        XCTAssertEqual(lid.angle(at: 2), 50)
        XCTAssertEqual(lid.angle(at: 4), 90)
        XCTAssertEqual(lid.angle(at: 6), 50)
        XCTAssertEqual(lid.angle(at: 8), 10)
    }

    func testNegativeTimeIsTheStartOfTheScript() throws {
        let lid = try XCTUnwrap(AngleSimulation(specification: "100:5:3"))
        XCTAssertEqual(lid.angle(at: -5), 100)
    }
}

/// The hardware-free path end to end: scripted lid, through the smoothing the app runs, into the fold decision.
final class SimulatedCloseTests: XCTestCase {
    private let tick = 1.0 / 60.0

    func testALidClosedFromOpenFoldsSmoothlyAndNeverShowsAboveNinetyDegrees() throws {
        let lid = try XCTUnwrap(AngleSimulation(specification: "100:5:3:1"))
        var filter = AngleFilter()
        var lastProgress = -1.0
        var shown = 0
        var finalProgress = 0.0

        for step in 0..<(5 * 60) {
            guard filter.shouldPoll() else { continue }
            let time = Double(step) * tick
            let reading = filter.ingest(lid.angle(at: time), at: time)
            let angle = try XCTUnwrap(reading.angle)
            switch FoldModel.presentation(angle: angle, configuration: FoldConfiguration()) {
            case .hidden:
                XCTAssertTrue(angle > 90 || angle < 3, "hidden at \(angle)")
            case let .fold(progress, tilt):
                XCTAssertLessThanOrEqual(angle, 90)
                XCTAssertGreaterThanOrEqual(progress, lastProgress, "progress went backwards at \(angle)")
                XCTAssertEqual(tilt, max(0, 88 - angle), accuracy: 1e-9)
                lastProgress = progress
                shown += 1
                finalProgress = progress
            }
        }
        // The average approaches the closed angle from above and never quite lands on it.
        XCTAssertGreaterThan(finalProgress, 0.999)
        XCTAssertGreaterThan(shown, 100)
    }
}

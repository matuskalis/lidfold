import XCTest
@testable import LidFoldCore

final class LidSensorReportTests: XCTestCase {
    func testDecodesTheReportReadFromHardware() {
        // Raw feature report 1 captured from a MacBookPro18,1 with the lid open: 01 67 00.
        XCTAssertEqual(LidSensorReport.angle(from: [0x01, 0x67, 0x00]), 103)
    }

    func testDecodesTheWholeLogicalRange() {
        XCTAssertEqual(LidSensorReport.angle(from: [1, 0x00, 0x00]), 0)
        XCTAssertEqual(LidSensorReport.angle(from: [1, 0x00, 0x01]), 256)
        XCTAssertEqual(LidSensorReport.angle(from: [1, 0x68, 0x01]), 360)
    }

    func testMasksEverythingAboveTheNineBitField() {
        XCTAssertEqual(LidSensorReport.angle(from: [1, 0xFF, 0xFF]), 511)
        XCTAssertEqual(LidSensorReport.angle(from: [1, 0x67, 0xFE]), 103)
    }

    func testRejectsReportsTooShortToHoldTheField() {
        XCTAssertNil(LidSensorReport.angle(from: []))
        XCTAssertNil(LidSensorReport.angle(from: [1]))
        XCTAssertNil(LidSensorReport.angle(from: [1, 0x67]))
    }
}

final class AngleFilterTests: XCTestCase {
    private let tick = 1.0 / 60.0

    func testFirstSamplePassesThroughUnsmoothed() {
        var filter = AngleFilter()
        let reading = filter.ingest(103, at: 0)
        XCTAssertEqual(reading.angle, 103)
        XCTAssertFalse(reading.isStale)
    }

    func testStepResponseLeavesSixtyPercentOfTheErrorPerSample() {
        var filter = AngleFilter()
        _ = filter.ingest(100, at: 0)
        let expected = [80.0, 68.0, 60.8, 56.48, 53.888]
        for (index, value) in expected.enumerated() {
            let angle = filter.ingest(50, at: Double(index + 1) * tick).angle
            XCTAssertEqual(angle!, value, accuracy: 1e-9)
        }
    }

    func testNinetyPercentOfAStepLandsOnTheFifthSample() {
        var filter = AngleFilter()
        _ = filter.ingest(100, at: 0)
        var remaining = 0.0
        for index in 1...4 { remaining = filter.ingest(50, at: Double(index) * tick).angle! - 50 }
        XCTAssertGreaterThan(remaining, 5)
        remaining = filter.ingest(50, at: 5 * tick).angle! - 50
        XCTAssertLessThan(remaining, 5)
    }

    func testOutputStaysWithinTheRangeOfItsInputs() {
        var filter = AngleFilter()
        _ = filter.ingest(5, at: 0)
        for index in 1...200 {
            let angle = filter.ingest(Double(index % 90), at: Double(index) * tick).angle!
            XCTAssertGreaterThanOrEqual(angle, 0)
            XCTAssertLessThanOrEqual(angle, 89)
        }
    }

    func testAFailedReadKeepsTheLastValueAndAges() {
        var filter = AngleFilter()
        _ = filter.ingest(70, at: 0)
        let quiet = filter.ingest(nil, at: 0.4)
        XCTAssertEqual(quiet.angle, 70)
        XCTAssertFalse(quiet.isStale)
        let stale = filter.ingest(nil, at: 0.6)
        XCTAssertEqual(stale.angle, 70)
        XCTAssertTrue(stale.isStale)
    }

    func testStaleFlagBoundaryIsExclusive() {
        var filter = AngleFilter()
        _ = filter.ingest(70, at: 10)
        XCTAssertFalse(filter.ingest(nil, at: 10.5).isStale)
        XCTAssertTrue(filter.ingest(nil, at: 10.5001).isStale)
    }

    func testStartsStaleAndClearsOnTheFirstGoodRead() {
        var filter = AngleFilter()
        let silent = filter.ingest(nil, at: 0)
        XCTAssertNil(silent.angle)
        XCTAssertTrue(silent.isStale)
        XCTAssertFalse(filter.ingest(60, at: 0.1).isStale)
    }

    func testPollsEveryTickAtOrBelowNinetyDegrees() {
        var filter = AngleFilter()
        _ = filter.ingest(90, at: 0)
        var polls = 0
        for _ in 0..<60 where filter.shouldPoll() { polls += 1 }
        XCTAssertEqual(polls, 60)
    }

    func testPollsOnceInSixTicksWhileTheLidIsOpenPastNinety() {
        var filter = AngleFilter()
        XCTAssertTrue(filter.shouldPoll())
        _ = filter.ingest(103, at: 0)
        var polls = 0
        for _ in 0..<60 where filter.shouldPoll() { polls += 1 }
        XCTAssertEqual(polls, 10)
    }
}

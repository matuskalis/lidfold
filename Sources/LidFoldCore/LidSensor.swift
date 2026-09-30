import Foundation

/// The lid angle sensor's report, as returned by `IOHIDDeviceGetReport(feature, report ID 1)`.
enum LidSensorReport {
    static let length = 3
    /// The angle field is 9 bits wide (logical range 0 to 360), the rest of the second byte is padding.
    static let angleMask: UInt16 = 0x1FF

    /// `[reportID, low, high]` to degrees. Nil when the report is too short to hold the field.
    static func angle(from bytes: [UInt8]) -> Double? {
        guard bytes.count >= length else { return nil }
        return Double((UInt16(bytes[1]) | UInt16(bytes[2]) << 8) & angleMask)
    }
}

/// Smooths the sensor's whole-degree steps, decides when to poll and flags a sensor that went quiet.
struct AngleFilter {
    /// Weight of each new sample in the exponential moving average.
    static let smoothing = 0.4
    /// A sensor that has not answered for this long counts as stale, in seconds.
    static let staleAfter = 0.5
    /// Above this angle nothing is drawn, so the sensor is polled at a fraction of the tick rate.
    static let idleAbove = 90.0
    static let idlePollDivisor = 6

    private(set) var smoothed: Double?
    private var lastGoodRead = -Double.infinity
    private var tickCount = 0

    /// Call once per timer tick. False means skip the read for this tick.
    mutating func shouldPoll() -> Bool {
        tickCount += 1
        if let smoothed, smoothed > Self.idleAbove, tickCount % Self.idlePollDivisor != 0 { return false }
        return true
    }

    /// Feed the decoded angle, or nil when the read failed. `time` is monotonic seconds.
    mutating func ingest(_ raw: Double?, at time: Double) -> (angle: Double?, isStale: Bool) {
        if let raw {
            lastGoodRead = time
            smoothed = smoothed.map { $0 + Self.smoothing * (raw - $0) } ?? raw
        }
        return (smoothed, time - lastGoodRead > Self.staleAfter)
    }
}

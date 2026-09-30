import Foundation

/// A scripted lid for running without touching the hardware. It sweeps between two angles at constant speed,
/// pauses at each end and repeats. Values are whole degrees, like the sensor's own.
struct AngleSimulation: Equatable {
    var openAngle: Double
    var closedAngle: Double
    var sweepSeconds: Double
    var holdSeconds: Double

    func angle(at seconds: Double) -> Double {
        let cycle = 2 * (sweepSeconds + holdSeconds)
        let phase = max(0, seconds).truncatingRemainder(dividingBy: cycle)
        let closing = phase - holdSeconds
        let opening = phase - (2 * holdSeconds + sweepSeconds)
        let towardClosed: Double
        if phase < holdSeconds {
            towardClosed = 0
        } else if closing < sweepSeconds {
            towardClosed = closing / sweepSeconds
        } else if opening < 0 {
            towardClosed = 1
        } else {
            towardClosed = 1 - opening / sweepSeconds
        }
        return (openAngle + (closedAngle - openAngle) * towardClosed).rounded()
    }
}

extension AngleSimulation {
    /// `open:closed:seconds` or `open:closed:seconds:hold`, for example `100:5:3` or `100:5:3:0.5`.
    /// `seconds` is one way, `hold` is the pause at each end.
    init?(specification: String) {
        let parts = specification.split(separator: ":").map { Double($0) }
        guard parts.count == 3 || parts.count == 4,
              let open = parts[0], let closed = parts[1], let sweep = parts[2], sweep > 0
        else { return nil }
        let hold = parts.count == 4 ? parts[3] : 0
        guard let hold, hold >= 0 else { return nil }
        self.init(openAngle: open, closedAngle: closed, sweepSeconds: sweep, holdSeconds: hold)
    }
}

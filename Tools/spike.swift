import Foundation
import IOKit.hid

// Reads the lid angle the way LidAngleReader does (same matching, same report, a 16 ms timer with 2 ms
// leeway) and prints it whenever it changes, so moving the lid shows the sensor's step size. After the run it
// prints the achieved rate, the timer interval and the read latency. `build/spike [seconds]`, default 30.

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let match: [String: Any] = [
    kIOHIDVendorIDKey: 0x05AC,
    kIOHIDProductIDKey: 0x8104,
    kIOHIDPrimaryUsagePageKey: 0x20,
    kIOHIDPrimaryUsageKey: 0x8A,
]
IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
    print("manager open failed")
    exit(1)
}
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
    print("no lid angle sensor found")
    exit(1)
}
let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print(String(format: "device open failed 0x%08X", openResult))
    exit(1)
}
print("devices matched: \(devices.count)")

func readReport() -> [UInt8]? {
    var report = [UInt8](repeating: 0, count: 3)
    var length = report.count
    let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
    guard result == kIOReturnSuccess, length >= 3 else { return nil }
    return report
}

func angle(_ report: [UInt8]) -> Double {
    Double((UInt16(report[1]) | UInt16(report[2]) << 8) & 0x1FF)
}

func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
}

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 30
let queue = DispatchQueue(label: "spike.sensor", qos: .userInteractive)
let timer = DispatchSource.makeTimerSource(queue: queue)
var stamps: [UInt64] = []
var latencies: [Double] = []
var failures = 0
var lastAngle: Double?
var distinct = Set<Double>()
let begin = DispatchTime.now().uptimeNanoseconds

timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
timer.setEventHandler {
    let before = DispatchTime.now().uptimeNanoseconds
    stamps.append(before)
    let report = readReport()
    latencies.append(Double(DispatchTime.now().uptimeNanoseconds - before) / 1000)
    if let report {
        let value = angle(report)
        distinct.insert(value)
        if value != lastAngle {
            if lastAngle == nil { print("first report: " + report.map { String(format: "%02x", $0) }.joined(separator: " ")) }
            print(String(format: "%7.3f s  %6.1f", Double(before - begin) / 1e9, value))
            fflush(stdout)
            lastAngle = value
        }
    } else {
        failures += 1
    }
    guard Double(before - begin) / 1e9 >= seconds else { return }

    let intervals = zip(stamps.dropFirst(), stamps).map { Double($0 - $1) / 1e6 }.sorted()
    latencies.sort()
    let mean = intervals.reduce(0, +) / Double(intervals.count)
    print(String(format: "%d reads in %.1f s, %d failed, %d distinct angles", stamps.count, seconds, failures, distinct.count))
    print(String(format: "timer interval ms: mean %.2f (%.1f Hz)  p50 %.2f  p95 %.2f  p99 %.2f  max %.2f",
                 mean, 1000 / mean, percentile(intervals, 0.5), percentile(intervals, 0.95), percentile(intervals, 0.99), intervals.last ?? 0))
    print(String(format: "read latency us: p50 %.0f  p95 %.0f  p99 %.0f  max %.0f",
                 percentile(latencies, 0.5), percentile(latencies, 0.95), percentile(latencies, 0.99), latencies.last ?? 0))
    exit(0)
}
timer.resume()
dispatchMain()

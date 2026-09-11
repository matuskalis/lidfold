import Foundation
import IOKit.hid

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

func readAngle() -> Double? {
    var report = [UInt8](repeating: 0, count: 3)
    var length = report.count
    let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
    guard result == kIOReturnSuccess, length >= 3 else { return nil }
    return Double((UInt16(report[1]) | UInt16(report[2]) << 8) & 0x1FF)
}

var frame = 0
let start = Date()
while Date().timeIntervalSince(start) < 30 {
    if let angle = readAngle() {
        print(String(format: "%5d  %6.1f", frame, angle))
    } else {
        print(String(format: "%5d  READ FAILED", frame))
    }
    frame += 1
    fflush(stdout)
    usleep(16_666)
}

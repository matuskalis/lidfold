import Foundation
import IOKit.hid
import Observation

@Observable
final class LidAngleReader {
    private(set) var angle: Double?
    private(set) var isStale = true

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.matuskalis.lidfold.sensor", qos: .userInteractive)
    private var filter = AngleFilter()

    func start() {
        queue.async { [weak self] in
            guard let self, self.device == nil else { return }
            let opened = Self.openSensor()
            self.manager = opened?.manager
            self.device = opened?.device
            NSLog("LidFold sensor open: %@", self.device != nil ? "ok" : "failed")
            guard self.device != nil else {
                DispatchQueue.main.async { self.isStale = true }
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    private func tick() {
        guard filter.shouldPoll() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let reading = filter.ingest(device.flatMap(Self.readAngle), at: now)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.angle = reading.angle
            self.isStale = reading.isStale
        }
    }

    private static func openSensor() -> (manager: IOHIDManager, device: IOHIDDevice)? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDPrimaryUsagePageKey: 0x20,
            kIOHIDPrimaryUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first,
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else { return nil }
        return (manager, device)
    }

    private static func readAngle(_ device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: LidSensorReport.length)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess else { return nil }
        return LidSensorReport.angle(from: Array(report.prefix(length)))
    }
}

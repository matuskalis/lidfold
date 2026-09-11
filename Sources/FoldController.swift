import AppKit

func lidLog(_ message: String) {
    let line = ISO8601DateFormatter().string(from: Date()) + " " + message + "\n"
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/lidfold.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

@MainActor
final class FoldController {
    static let armBelow = Double(ProcessInfo.processInfo.environment["LIDFOLD_ARM"] ?? "") ?? 88.0
    static let disarmAbove = Double(ProcessInfo.processInfo.environment["LIDFOLD_DISARM"] ?? "") ?? 90.0
    static let closedAngle = 5.0
    static let minVisibleAngle = 3.0
    static let progressOverride = ProcessInfo.processInfo.environment["LIDFOLD_PROGRESS"].flatMap(Double.init)
    static let tiltOverride = ProcessInfo.processInfo.environment["LIDFOLD_TILT"].flatMap(Double.init)

    let reader = LidAngleReader()
    private let freezer = ScreenFreezer()
    private var frozen: CGImage?
    private var capturing = false
    private var nextCaptureAttempt = Date.distantPast
    private var window: FoldOverlayWindow?
    private var ticker: Timer?

    var isEnabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enabled")
            if !isEnabled { disarm() }
        }
    }

    var angle: Double? { reader.angle }

    func start() {
        reader.start()
        let ticker = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func tick() {
        guard isEnabled, !reader.isStale, let angle = reader.angle else {
            disarm()
            return
        }
        if angle > Self.disarmAbove || angle < Self.minVisibleAngle {
            disarm()
            return
        }
        guard let screen = Self.builtInScreen(), Self.isAwake(screen) else {
            disarm()
            return
        }

        let tracked = min(max((Self.armBelow - angle) / (Self.armBelow - Self.closedAngle), 0), 1)
        let progress = Self.progressOverride ?? tracked
        let tilt = Self.tiltOverride ?? max(0, Self.armBelow - angle)
        guard let frozen else {
            arm()
            return
        }
        if let window {
            window.update(progress: progress, tiltDegrees: tilt)
        } else {
            let window = FoldOverlayWindow(screen: screen, frozen: frozen)
            window.show(progress: progress, tiltDegrees: tilt)
            self.window = window
            lidLog("overlay shown at angle \(angle) progress \(progress)")
        }
    }

    private func arm() {
        guard !capturing, Date() >= nextCaptureAttempt else { return }
        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            do {
                frozen = try await freezer.captureBuiltInDisplay(excludingWindowNumber: window?.windowNumber ?? -1)
            } catch {
                nextCaptureAttempt = Date().addingTimeInterval(5)
                lidLog("capture failed, launch through ./run.sh from a terminal: \(error)")
            }
        }
    }

    private func disarm() {
        window?.hide()
        window = nil
        frozen = nil
    }

    private static func isAwake(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return false }
        let id = CGDirectDisplayID(number.uint32Value)
        return CGDisplayIsActive(id) != 0 && CGDisplayIsAsleep(id) == 0
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
    }
}

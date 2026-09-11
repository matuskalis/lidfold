import AppKit

final class FoldOverlayWindow: NSWindow {
    private let foldView: FoldOverlayView

    init(screen: NSScreen, frozen: CGImage) {
        foldView = FoldOverlayView(frozen: frozen)
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = foldView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(progress: Double, tiltDegrees: Double) {
        foldView.update(progress: progress, tiltDegrees: tiltDegrees)
        orderFrontRegardless()
    }

    func update(progress: Double, tiltDegrees: Double) {
        foldView.update(progress: progress, tiltDegrees: tiltDegrees)
    }

    func hide() {
        orderOut(nil)
    }
}

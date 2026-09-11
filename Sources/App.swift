import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = FoldController()
    private var menuBar: MenuBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBar(controller: controller)
        controller.start()
    }
}

@main
enum LidFoldApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

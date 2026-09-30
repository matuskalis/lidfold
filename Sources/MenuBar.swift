import AppKit
import ServiceManagement

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: FoldController
    private let angleItem = NSMenuItem(title: "Lid angle: n/a", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")

    init(controller: FoldController) {
        self.controller = controller
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "LidFold")
        let menu = NSMenu()
        menu.delegate = self
        angleItem.isEnabled = false
        enabledItem.target = self
        loginItem.target = self
        menu.addItem(angleItem)
        menu.addItem(.separator())
        menu.addItem(enabledItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LidFold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let angle = controller.angle {
            angleItem.title = String(format: "Lid angle: %.1f°", angle) + (controller.isSimulated ? " (simulated)" : "")
        } else {
            angleItem.title = "Lid angle sensor not found"
        }
        enabledItem.state = controller.isEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
    }

    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }
}

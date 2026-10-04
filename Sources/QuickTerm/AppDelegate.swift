import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum HotZone {
        /// Total width of the trigger strip, centred on the top edge of each screen.
        static let width: CGFloat = 260
        static let edgeThickness: CGFloat = 2
        /// How far the pointer must back off the edge before it can trigger again.
        static let rearmDistance: CGFloat = 12
    }

    private var panel: DropPanelController!
    private var statusItem: NSStatusItem!
    private var monitors: [Any] = []
    private var edgeArmed = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = DropPanelController()
        installMainMenu()
        installStatusItem()
        installPointerMonitors()

        if CommandLine.arguments.contains("--show"), let screen = NSScreen.main {
            panel.show(on: screen)
        }
    }

    // MARK: - Pointer tracking

    private func installPointerMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Global: pointer over other apps. Local: pointer over our own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.pointerMoved()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) {
            monitors.append(local)
        }
    }

    private func pointerMoved() {
        // Ignore drags, so moving a window to the top edge doesn't toggle the terminal.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) })
        else { return }
        let frame = screen.frame
        let inZone = abs(location.x - frame.midX) <= HotZone.width / 2

        // Each push on the edge toggles once: open, then close on the next push.
        if inZone, location.y >= frame.maxY - HotZone.edgeThickness {
            guard edgeArmed else { return }
            edgeArmed = false
            panel.toggle(on: screen)
        } else if !inZone || location.y < frame.maxY - HotZone.rearmDistance {
            edgeArmed = true
        }
    }

    // MARK: - Menus

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "QuickTerm")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Show / Hide", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit QuickTerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// An accessory app shows no menu bar, but the key equivalents still route through it.
    private func installMainMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTitle: "Open at Login")?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggle() {
        panel.toggle(on: statusItem.button?.window?.screen)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change the login item"
            alert.runModal()
        }
    }
}

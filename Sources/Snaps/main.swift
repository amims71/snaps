import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var editors: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: "Snaps")

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Image…", action: #selector(openImage), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snaps", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // No menu bar is shown for a menu-bar app, but its key equivalents still work: this gives Cmd-W.
        let windowMenu = NSMenu()
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let mainMenu = NSMenu()
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu

        // `open Snaps.app --args /path/to/image.png` opens that image directly.
        for path in CommandLine.arguments.dropFirst() where FileManager.default.fileExists(atPath: path) {
            openEditor(for: URL(fileURLWithPath: path))
        }
    }

    @objc private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openEditor(for: url)
        }
    }

    private func openEditor(for url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        openEditor(source: source, imageURL: url)
    }

    private func openEditor(source: CGImageSource, imageURL: URL) {
        guard let controller = EditorWindowController(source: source, imageURL: imageURL) else { return }
        controller.onClose = { [weak self, weak controller] in
            self?.editors.removeAll { $0 === controller }
        }
        editors.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

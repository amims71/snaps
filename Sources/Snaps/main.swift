import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var clipboardWatcher: ClipboardWatcher?
    private var editors: [EditorWindowController] = []
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let saveFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: "Snaps")

        let menu = NSMenu()
        let hint = NSMenuItem(title: "Copy a screenshot (⌃⇧⌘4) to draw on it", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Image…", action: #selector(openImage), keyEquivalent: "o")
        menu.addItem(loginItem)
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

        // Launch at login by default; after the first run the menu toggle decides.
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
        }
        updateLoginItem()

        clipboardWatcher = ClipboardWatcher { [weak self] png in
            guard let self, let source = CGImageSourceCreateWithData(png as CFData, nil) else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "'Screenshot' yyyy-MM-dd 'at' HH.mm.ss'.png'"
            openEditor(source: source, imageURL: saveFolder.appendingPathComponent(formatter.string(from: Date())))
        }

        // `open Snaps.app --args /path/to/image.png` opens that image directly.
        for path in CommandLine.arguments.dropFirst() where FileManager.default.fileExists(atPath: path) {
            openEditor(for: URL(fileURLWithPath: path))
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
        updateLoginItem()
    }

    private func updateLoginItem() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
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

// Used by the uninstaller: remove the login item, then exit without starting the app.
if CommandLine.arguments.contains("--unregister") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

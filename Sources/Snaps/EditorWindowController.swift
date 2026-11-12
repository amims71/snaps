import AppKit
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white]
    private static let widths: [CGFloat] = [2, 4, 8]

    /// The image file, or for a clipboard screenshot a not-yet-existing file name; used for the title and Save.
    private let imageURL: URL
    private let canvas: CanvasView
    var onClose: (() -> Void)?

    init?(source: CGImageSource, imageURL: URL) {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.imageURL = imageURL
        // Keep the screenshot's DPI (144 on Retina) so the result pastes at the same size as the original.
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = props?[kCGImagePropertyDPIWidth] as? CGFloat ?? 72
        self.canvas = CanvasView(image: image, dpi: dpi)

        // Open at the screenshot's on-screen size, shrunk to fit the screen.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let backing = screen.backingScaleFactor
        let toolbarHeight: CGFloat = 52
        let visible = screen.visibleFrame
        var size = CGSize(width: CGFloat(image.width) / backing, height: CGFloat(image.height) / backing)
        let fit = min(1, visible.width * 0.9 / size.width, (visible.height * 0.9 - toolbarHeight) / size.height)
        size = CGSize(width: max(size.width * fit, 560), height: max(size.height * fit, 200) + toolbarHeight)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = imageURL.lastPathComponent
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 560, height: 260)
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeContent() -> NSView {
        let tools = NSSegmentedControl(
            images: Tool.allCases.map { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.name)! },
            trackingMode: .selectOne, target: self, action: #selector(toolChanged))
        Tool.allCases.forEach { tools.setToolTip($0.name, forSegment: $0.rawValue) }
        tools.selectedSegment = canvas.tool.rawValue

        let colors = NSSegmentedControl(
            images: Self.colors.map(Self.swatch), trackingMode: .selectOne,
            target: self, action: #selector(colorChanged))
        colors.selectedSegment = 0

        let widths = NSSegmentedControl(
            images: Self.widths.map(Self.widthIcon), trackingMode: .selectOne,
            target: self, action: #selector(widthChanged))
        widths.selectedSegment = Self.widths.firstIndex(of: canvas.lineWidth) ?? 1

        let undo = button("Undo", symbol: "arrow.uturn.backward", key: "z", action: #selector(undo))
        let copy = button("Copy", symbol: "doc.on.doc", key: "c", action: #selector(copyImage))
        let save = button("Save…", symbol: "square.and.arrow.down", key: "s", action: #selector(saveImage))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [tools, colors, widths, spacer, undo, copy, save])
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        let root = NSView()
        for view in [bar, canvas] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: bar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }

    private func button(_ title: String, symbol: String, key: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!,
                              target: self, action: action)
        button.imagePosition = .imageLeading
        button.keyEquivalent = key
        button.keyEquivalentModifierMask = .command
        return button
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            circle.fill()
            NSColor.gray.withAlphaComponent(0.6).setStroke()
            circle.stroke()
            return true
        }
    }

    private static func widthIcon(_ width: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: 18, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            CGRect(x: 1, y: (rect.height - width) / 2, width: rect.width - 2, height: width).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        canvas.tool = Tool(rawValue: sender.selectedSegment) ?? .pen
    }

    @objc private func colorChanged(_ sender: NSSegmentedControl) {
        canvas.color = Self.colors[sender.selectedSegment]
    }

    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        canvas.lineWidth = Self.widths[sender.selectedSegment]
    }

    @objc private func undo() {
        window?.undoManager?.undo()
    }

    @objc private func copyImage() {
        guard let png = canvas.renderPNG() else { return NSSound.beep() }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            board.setData(tiff, forType: .tiff)
        }
        window?.title = "Copied — " + imageURL.lastPathComponent
    }

    @objc private func saveImage() {
        guard let window, let png = canvas.renderPNG() else { return NSSound.beep() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = imageURL.deletingLastPathComponent()
        panel.nameFieldStringValue = imageURL.deletingPathExtension().lastPathComponent + " (edited).png"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
                window.title = "Saved — " + url.lastPathComponent
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

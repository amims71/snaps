import AppKit

/// Reports screenshots copied to the clipboard (Cmd-Ctrl-Shift-3/4, or "Save to: Clipboard").
/// macOS has no clipboard-change notification, so this polls `changeCount`, which is cheap.
/// A screenshot's PNG has EXIF UserComment "Screenshot"; images copied from other apps,
/// and Snaps' own Copy (no EXIF), don't.
final class ClipboardWatcher {
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    init(onScreenshot: @escaping (Data) -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let board = NSPasteboard.general
            guard board.changeCount != lastChange else { return }
            lastChange = board.changeCount
            // Only image copies are read; copied text etc. is never touched.
            guard board.availableType(from: [.png]) != nil,
                  let png = board.data(forType: .png),
                  let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
                  exif[kCGImagePropertyExifUserComment] as? String == "Screenshot"
            else { return }
            onScreenshot(png)
        }
    }
}

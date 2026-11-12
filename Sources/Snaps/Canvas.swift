import AppKit

enum Tool: Int, CaseIterable {
    case pen, line, arrow, rectangle, ellipse

    var symbol: String {
        switch self {
        case .pen: "scribble"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        }
    }

    var name: String {
        switch self {
        case .pen: "Free draw"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        }
    }
}

/// One drawn mark, stored in image pixel coordinates (origin bottom-left).
/// Pen marks keep every point; shapes keep [start, end].
struct Mark {
    var tool: Tool
    var color: NSColor
    var width: CGFloat
    var points: [CGPoint]

    func path() -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        guard let start = points.first, let end = points.last else { return path }
        switch tool {
        case .pen:
            path.move(to: start)
            if points.count == 1 { path.line(to: start) }
            points.dropFirst().forEach { path.line(to: $0) }
        case .line:
            path.move(to: start)
            path.line(to: end)
        case .arrow:
            path.move(to: start)
            path.line(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = max(width * 4, 12)
            for spread in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                path.move(to: end)
                path.line(to: CGPoint(x: end.x + head * cos(angle + spread), y: end.y + head * sin(angle + spread)))
            }
        case .rectangle:
            path.appendRect(Self.rect(start, end))
        case .ellipse:
            path.appendOval(in: Self.rect(start, end))
        }
        return path
    }

    func draw() {
        color.setStroke()
        path().stroke()
    }

    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Shows the screenshot scaled to fit and lets the user draw marks on it.
final class CanvasView: NSView {
    let image: CGImage
    let dpi: CGFloat
    var tool: Tool = .pen
    var color: NSColor = .systemRed
    /// Line width in on-screen points; converted to image pixels when a mark starts.
    var lineWidth: CGFloat = 4
    private(set) var marks: [Mark] = []
    private var current: Mark?

    init(image: CGImage, dpi: CGFloat) {
        self.image = image
        self.dpi = dpi
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    /// Where the image sits inside the view, aspect-fit and centered.
    private var imageRect: CGRect {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func toImage(_ viewPoint: CGPoint) -> CGPoint {
        let rect = imageRect
        let scale = imageSize.width / rect.width
        return CGPoint(x: (viewPoint.x - rect.minX) * scale, y: (viewPoint.y - rect.minY) * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / imageSize.width, y: rect.height / imageSize.height)
        marks.forEach { $0.draw() }
        current?.draw()
        ctx.restoreGState()
    }

    /// The editor pops up while another app is active; the first stroke should draw, not just focus the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        let width = lineWidth * imageSize.width / imageRect.width
        current = Mark(tool: tool, color: color, width: width, points: [p, p])
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard current != nil else { return }
        let p = toImage(convert(event.locationInWindow, from: nil))
        if current!.tool == .pen {
            current!.points.append(p)
        } else {
            current!.points[1] = p
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let mark = current else { return }
        current = nil
        marks.append(mark)
        undoManager?.registerUndo(withTarget: self) { $0.removeLastMark() }
        needsDisplay = true
    }

    private func removeLastMark() {
        guard let mark = marks.popLast() else { return }
        undoManager?.registerUndo(withTarget: self) { canvas in
            canvas.marks.append(mark)
            canvas.undoManager?.registerUndo(withTarget: canvas) { $0.removeLastMark() }
            canvas.needsDisplay = true
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: .crosshair)
    }

    /// The screenshot with all marks burned in, at full resolution, as PNG.
    func renderPNG() -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = CGSize(width: imageSize.width * 72 / dpi, height: imageSize.height * 72 / dpi)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.draw(image, in: CGRect(origin: .zero, size: imageSize))
        marks.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

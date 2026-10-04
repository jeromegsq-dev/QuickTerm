import AppKit

/// Invisible grip along an edge or corner of the card.
final class ResizeHandle: NSView {
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let bottom = Edges(rawValue: 1 << 2)
    }

    let edges: Edges
    var onBegin: (() -> Void)?
    /// Pointer translation since the drag began, in screen points.
    var onDrag: ((Edges, CGSize) -> Void)?
    var onEnd: (() -> Void)?

    private var dragOrigin = CGPoint.zero

    init(edges: Edges) {
        self.edges = edges
        super.init(frame: .zero)
        // Fully transparent pixels let clicks fall through to the windows below.
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.02).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var cursor: NSCursor {
        if edges == .bottom { return .resizeUpDown }
        if !edges.contains(.bottom) { return .resizeLeftRight }
        if #available(macOS 15.0, *) {
            return .frameResize(position: edges.contains(.left) ? .bottomLeft : .bottomRight, directions: .all)
        }
        return .crosshair
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: the panel is usable while another app is frontmost.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        cursor.set()
        onDrag?(edges, CGSize(width: location.x - dragOrigin.x, height: location.y - dragOrigin.y))
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }
}

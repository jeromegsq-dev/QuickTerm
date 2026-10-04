import AppKit

final class TabBarView: NSView {
    static let height: CGFloat = 36

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?

    private var items: [TabItemView] = []
    private let addButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        addButton.isBordered = false
        addButton.contentTintColor = .secondaryLabelColor
        addButton.target = self
        addButton.action = #selector(addClicked)
        addSubview(addButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reload(titles: [String], selected: Int) {
        if items.count != titles.count {
            items.forEach { $0.removeFromSuperview() }
            items = titles.indices.map { index in
                let item = TabItemView()
                item.onSelect = { [weak self] in self?.onSelect?(index) }
                item.onClose = { [weak self] in self?.onClose?(index) }
                addSubview(item)
                return item
            }
            needsLayout = true
        }
        for (index, item) in items.enumerated() {
            item.title = titles[index]
            item.isSelected = index == selected
        }
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8, spacing: CGFloat = 4, buttonSide: CGFloat = 24
        let itemHeight = bounds.height - 10
        let available = bounds.width - 2 * inset - buttonSide - spacing
        let width = min(200, (available - spacing * CGFloat(items.count)) / CGFloat(max(items.count, 1))).rounded(.down)
        var x = inset
        for item in items {
            item.frame = CGRect(x: x, y: 5, width: width, height: itemHeight)
            x += width + spacing
        }
        addButton.frame = CGRect(x: x, y: 5 + (itemHeight - buttonSide) / 2, width: buttonSide, height: buttonSide)
    }

    @objc private func addClicked() {
        onNew?()
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    var title: String {
        get { label.stringValue }
        set { if label.stringValue != newValue { label.stringValue = newValue } }
    }

    var isSelected = false {
        didSet {
            layer?.backgroundColor = NSColor(white: 1, alpha: isSelected ? 0.14 : 0).cgColor
            label.textColor = isSelected ? .labelColor : .secondaryLabelColor
            closeButton.isHidden = !isSelected
        }
    }

    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .secondaryLabelColor
        addSubview(label)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let side: CGFloat = 18
        closeButton.frame = CGRect(x: bounds.width - side - 5, y: (bounds.height - side) / 2, width: side, height: side)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = CGRect(x: 10, y: ((bounds.height - labelHeight) / 2).rounded(),
                             width: max(0, bounds.width - 10 - side - 8), height: labelHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    @objc private func closeClicked() {
        onClose?()
    }
}

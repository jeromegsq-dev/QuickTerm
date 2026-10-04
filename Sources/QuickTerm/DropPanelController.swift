import AppKit
import QuartzCore
import SwiftTerm

/// Borderless panel that takes keyboard focus without activating the app,
/// so the frontmost app stays frontmost while the terminal is down.
final class DropPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Returns true when the key press was consumed as a panel shortcut.
    var onKeyDown: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

final class DropPanelController: NSObject, LocalProcessTerminalViewDelegate {
    private enum Metrics {
        static let shadowMargin: CGFloat = 44
        static let cornerRadius: CGFloat = 16
        static let widthRatio: CGFloat = 0.62
        static let heightRatio: CGFloat = 0.48
        static let minSize = CGSize(width: 480, height: 240)
        static let defaultMaxWidth: CGFloat = 1280
        /// Grip width, half inside the card and half outside it.
        static let handleThickness: CGFloat = 20
        static let cornerHandleSide: CGFloat = 32
    }

    private enum DefaultsKey {
        static let width = "cardWidth"
        static let height = "cardHeight"
    }

    private static let slideKey = "slide"
    /// Key codes of the top-row digits 1…9, independent of the keyboard layout.
    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    private let panel: DropPanel
    private let slideView = NSView()
    private let shadowView = NSView()
    private let cardView = NSView()
    private let tabBar = TabBarView()
    private let terminalContainer = NSView()
    private let handles: [ResizeHandle] = [
        ResizeHandle(edges: .left), ResizeHandle(edges: .right), ResizeHandle(edges: .bottom),
        ResizeHandle(edges: [.left, .bottom]), ResizeHandle(edges: [.right, .bottom]),
    ]
    private var tabs: [TerminalTab] = []
    private var selectedIndex = 0
    private var titleTimer: Timer?
    private var cardSize = CGSize.zero
    private var sizeAtDragStart = CGSize.zero
    private var generation = 0
    /// One invisible, always-present window per screen. They join desktop
    /// Spaces only, so they tell those apart from a full-screen app's Space.
    private var spaceProbes: [NSWindow] = []

    private(set) var isShown = false

    override init() {
        panel = DropPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        configurePanel()
        configureViews()
        newTab()
        rebuildSpaceProbes()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildSpaceProbes),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(hideImmediately),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shadow is drawn by a layer so it follows the slide animation.
        panel.hasShadow = false
        panel.level = .statusBar
        // Tied to the Space it drops on, so it leaves with that Space on a swipe.
        // No .fullScreenAuxiliary: desktop Spaces only.
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
        panel.onKeyDown = { [weak self] in self?.handleKeyDown($0) ?? false }
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
    }

    private func configureViews() {
        // The root clips, so the card appears to slide out from under the menu bar.
        let root = NSView()
        root.wantsLayer = true
        root.layer?.masksToBounds = true
        panel.contentView = root

        slideView.wantsLayer = true
        root.addSubview(slideView)

        shadowView.wantsLayer = true
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = 0.45
        shadowView.layer?.shadowRadius = 22
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -10)
        slideView.addSubview(shadowView)

        cardView.wantsLayer = true
        if let layer = cardView.layer {
            layer.cornerRadius = Metrics.cornerRadius
            layer.cornerCurve = .continuous
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            layer.masksToBounds = true
            layer.borderWidth = 1
            layer.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        }
        slideView.addSubview(cardView)

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        cardView.addSubview(blur)

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.04, alpha: 0.55).cgColor
        tint.autoresizingMask = [.width, .height]
        cardView.addSubview(tint)

        tabBar.onSelect = { [weak self] in self?.selectTab($0) }
        tabBar.onClose = { [weak self] in self?.closeTab($0) }
        tabBar.onNew = { [weak self] in self?.newTab() }
        cardView.addSubview(tabBar)
        cardView.addSubview(terminalContainer)

        for handle in handles {
            handle.onBegin = { [weak self] in self?.sizeAtDragStart = self?.cardSize ?? .zero }
            handle.onDrag = { [weak self] in self?.resize(edges: $0, translation: $1) }
            handle.onEnd = { [weak self] in self?.saveSize() }
            slideView.addSubview(handle)
        }
    }

    @objc private func rebuildSpaceProbes() {
        spaceProbes.forEach { $0.close() }
        spaceProbes = NSScreen.screens.map { screen in
            let probe = NSWindow(
                contentRect: CGRect(x: screen.frame.midX, y: screen.frame.midY, width: 1, height: 1),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            probe.isReleasedWhenClosed = false
            probe.isOpaque = false
            probe.backgroundColor = .clear
            probe.hasShadow = false
            probe.ignoresMouseEvents = true
            probe.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            probe.orderFrontRegardless()
            return probe
        }
    }

    private func isDesktopSpace(on screen: NSScreen) -> Bool {
        spaceProbes.first { screen.frame.contains($0.frame.origin) }?.isOnActiveSpace ?? true
    }

    // MARK: - Tabs

    private var selectedTab: TerminalTab? {
        tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil
    }

    func newTab() {
        // A new tab starts where the current one is.
        let tab = TerminalTab(delegate: self, directory: selectedTab?.workingDirectory ?? NSHomeDirectory())
        tab.view.frame = terminalContainer.bounds
        terminalContainer.addSubview(tab.view)
        tabs.append(tab)
        selectTab(tabs.count - 1)
    }

    private func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
        // Hidden rather than removed: a Metal view doesn't survive leaving its window.
        for (i, tab) in tabs.enumerated() {
            tab.view.isHidden = i != index
        }
        panel.makeFirstResponder(tabs[index].view)
        reloadTabBar()
    }

    private func selectRelativeTab(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        selectTab((selectedIndex + offset + tabs.count) % tabs.count)
    }

    private func closeTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs.remove(at: index)
        tab.view.processDelegate = nil
        tab.view.terminate()
        tab.view.removeFromSuperview()

        if tabs.isEmpty {
            // Closing the last tab dismisses the panel; a fresh shell is ready for the next drop.
            hide()
            newTab()
        } else {
            selectTab(min(index > selectedIndex ? selectedIndex : max(selectedIndex - 1, 0), tabs.count - 1))
        }
    }

    private func reloadTabBar() {
        tabBar.reload(titles: tabs.map(\.title), selected: selectedIndex)
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isShown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if event.keyCode == 53, modifiers.isEmpty {
            // At the prompt Escape dismisses; otherwise it belongs to the running program.
            guard selectedTab?.shellIsForeground ?? true else { return false }
            hide()
            return true
        }
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "t":
                newTab()
                return true
            case "w":
                closeTab(selectedIndex)
                return true
            default:
                break
            }
            if let index = Self.digitKeyCodes.firstIndex(of: event.keyCode), index < tabs.count {
                selectTab(index)
                return true
            }
        }
        if event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift] {
            selectRelativeTab(modifiers.contains(.shift) ? -1 : 1)
            return true
        }
        return false
    }

    // MARK: - Layout

    private func layout(on screen: NSScreen) {
        let frame = screen.frame
        let topInset = Self.topInset(of: screen)
        let available = frame.height - topInset
        let margin = Metrics.shadowMargin
        let maxSize = CGSize(width: frame.width - 2 * margin, height: available - margin)

        let defaults = UserDefaults.standard
        var size = CGSize(width: defaults.double(forKey: DefaultsKey.width),
                          height: defaults.double(forKey: DefaultsKey.height))
        if cardSize != .zero { size = cardSize }
        if size.width <= 0 { size.width = min(frame.width * Metrics.widthRatio, Metrics.defaultMaxWidth) }
        if size.height <= 0 { size.height = available * Metrics.heightRatio }
        size.width = min(max(size.width, Metrics.minSize.width), maxSize.width).rounded()
        size.height = min(max(size.height, Metrics.minSize.height), maxSize.height).rounded()
        cardSize = size

        let card = CGRect(
            x: (frame.midX - size.width / 2).rounded(),
            y: (frame.maxY - topInset - size.height).rounded(),
            width: size.width,
            height: size.height
        )
        panel.setFrame(
            CGRect(x: card.minX - margin, y: card.minY - margin,
                   width: card.width + 2 * margin, height: card.height + margin),
            display: true
        )

        let local = CGRect(x: margin, y: margin, width: card.width, height: card.height)
        slideView.frame = CGRect(origin: .zero, size: panel.frame.size)
        // One point taller than the window, so the card's top border is clipped away.
        cardView.frame = CGRect(x: local.minX, y: local.minY, width: local.width, height: local.height + 1)
        shadowView.frame = local
        tabBar.frame = CGRect(x: 0, y: local.height - TabBarView.height, width: local.width, height: TabBarView.height)
        terminalContainer.frame = CGRect(x: 12, y: 10, width: local.width - 24,
                                         height: local.height - TabBarView.height - 10)
        tabs.forEach { $0.view.frame = terminalContainer.bounds }

        let thickness = Metrics.handleThickness, corner = Metrics.cornerHandleSide
        for handle in handles {
            switch handle.edges {
            case .left:
                handle.frame = CGRect(x: local.minX - thickness / 2, y: local.minY + corner,
                                      width: thickness, height: local.height - corner)
            case .right:
                handle.frame = CGRect(x: local.maxX - thickness / 2, y: local.minY + corner,
                                      width: thickness, height: local.height - corner)
            case .bottom:
                handle.frame = CGRect(x: local.minX + corner, y: local.minY - thickness / 2,
                                      width: local.width - 2 * corner, height: thickness)
            case [.left, .bottom]:
                handle.frame = CGRect(x: local.minX - thickness / 2, y: local.minY - thickness / 2,
                                      width: corner, height: corner)
            default:
                handle.frame = CGRect(x: local.maxX + thickness / 2 - corner, y: local.minY - thickness / 2,
                                      width: corner, height: corner)
            }
        }

        // Shadow only outside the card, so it doesn't darken the blur.
        let outline = Self.bottomRoundedPath(shadowView.bounds, radius: Metrics.cornerRadius)
        shadowView.layer?.shadowPath = outline
        let cutout = CGMutablePath()
        cutout.addRect(shadowView.bounds.insetBy(dx: -2 * margin, dy: -2 * margin))
        cutout.addPath(outline)
        let mask = CAShapeLayer()
        mask.path = cutout
        mask.fillRule = .evenOdd
        shadowView.layer?.mask = mask
    }

    /// Height of the strip the card hangs below: the menu bar, or the notch
    /// when the menu bar auto-hides.
    private static func topInset(of screen: NSScreen) -> CGFloat {
        let frame = screen.frame
        // `visibleFrame` rounds the menu bar up (40 pt for a 39 pt bar on notched
        // displays), which leaves a gap; the menu bar window has the real height.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let screenTop = primaryHeight - frame.maxY
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
        for window in windows where window[kCGWindowLayer] as? Int == Int(CGWindowLevelForKey(.mainMenuWindow)) {
            guard let dictionary = window[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary),
                  bounds.minX == frame.minX, bounds.minY == screenTop, bounds.width == frame.width
            else { continue }
            return bounds.height
        }
        return max(frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
    }

    private static func bottomRoundedPath(_ r: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX, y: r.maxY))
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                    tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY),
                    tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.closeSubpath()
        return path
    }

    // MARK: - Resize

    private func resize(edges: ResizeHandle.Edges, translation: CGSize) {
        guard let screen = panel.screen else { return }
        var size = sizeAtDragStart
        // The card stays centred and pinned to the top: side edges move in mirror.
        if edges.contains(.right) { size.width += 2 * translation.width }
        if edges.contains(.left) { size.width -= 2 * translation.width }
        if edges.contains(.bottom) { size.height -= translation.height }
        cardSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layout(on: screen)
        CATransaction.commit()
    }

    private func saveSize() {
        UserDefaults.standard.set(Double(cardSize.width), forKey: DefaultsKey.width)
        UserDefaults.standard.set(Double(cardSize.height), forKey: DefaultsKey.height)
    }

    // MARK: - Show / hide

    func toggle(on screen: NSScreen?) {
        if isShown {
            hide()
        } else if let screen = screen ?? NSScreen.main {
            show(on: screen)
        }
    }

    func show(on screen: NSScreen) {
        guard !isShown else { return }
        // Mid-hide the frame is still valid; moving it would break the interrupted slide.
        let interruptingHide = slideView.layer?.animation(forKey: Self.slideKey) != nil
        if !interruptingHide {
            // On a full-screen app's Space the panel isn't displayed: stay out of the way.
            guard isDesktopSpace(on: screen) else { return }
            layout(on: screen)
        }
        isShown = true
        slide(shown: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(selectedTab?.view)
        reloadTabBar()
        // Titles follow the shell's folder and running program; polled only while visible.
        titleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.reloadTabBar()
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        titleTimer?.invalidate()
        slide(shown: false)
    }

    /// Space switch: no animation, the panel must not follow or linger.
    @objc private func hideImmediately() {
        guard isShown || panel.isVisible else { return }
        isShown = false
        titleTimer?.invalidate()
        generation += 1
        slideView.layer?.removeAnimation(forKey: Self.slideKey)
        panel.orderOut(nil)
    }

    /// Slides the card by animating a layer transform only: the window never
    /// moves or resizes, so every frame is produced by the render server.
    private func slide(shown: Bool) {
        guard let layer = slideView.layer else { return }
        let hiddenOffset = panel.frame.height
        let keyPath = "transform.translation.y"

        let from: CGFloat
        if layer.animation(forKey: Self.slideKey) != nil,
           let current = layer.presentation()?.value(forKeyPath: keyPath) as? CGFloat {
            from = current
        } else {
            from = shown ? hiddenOffset : 0
        }

        let animation: CABasicAnimation
        if shown {
            let spring = CASpringAnimation(perceptualDuration: 0.22, bounce: 0)
            spring.duration = spring.settlingDuration
            animation = spring
        } else {
            // Short and bounded: the panel keeps keyboard focus until it is ordered out.
            animation = CABasicAnimation()
            animation.duration = 0.14
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.6)
        }
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = shown ? 0 : hiddenOffset
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        generation += 1
        let token = generation
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, token == self.generation else { return }
            if !shown { self.panel.orderOut(nil) }
            layer.removeAnimation(forKey: Self.slideKey)
        }
        layer.add(animation, forKey: Self.slideKey)
        CATransaction.commit()
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // `exit` closes its tab.
        if let index = tabs.firstIndex(where: { $0.view === source }) {
            closeTab(index)
        }
    }
}

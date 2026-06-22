import AppKit

// The translucent backdrop that lays its destination buttons out in a ring
// around the cursor. Handles Escape-to-dismiss.
final class RadialMenuView: NSView {
    var onDismiss: (() -> Void)?
    private let items: [Destination]
    private let origin: ArcOrigin

    // Roller state: when more destinations exist than fit on the arc, only a
    // window of them is shown and the user scrolls (rolls) through the rest.
    private var visibleStart = 0
    private var canScrollBack = false   // more items before the window
    private var canScrollFwd = false    // more items after the window
    // Set when a roll changes the window, so the next layout animates its tiles
    // in (and which way they slid, for a subtle directional cue).
    private var rollAnimation: CGFloat = 0   // 0 = none, -1 = back, +1 = forward

    // Edges fan a full 180° semicircle (±90°); corners a 90° quarter (±42°).
    private var spreadDegrees: CGFloat {
        origin.isCorner ? 42 : 90
    }

    init(frame frameRect: NSRect, items: [Destination], origin: ArcOrigin) {
        self.items = items
        self.origin = origin
        super.init(frame: frameRect)
        wantsLayer = true
        layoutItems()
        addCloseButton()
    }

    private func addCloseButton() {
        let size: CGFloat = 26
        let anchor = origin.anchor(in: bounds)
        let button = NSButton(frame: NSRect(x: anchor.x - size / 2,
                                            y: anchor.y - size / 2,
                                            width: size, height: size))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        button.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.7)
        button.imageScaling = .scaleProportionallyUpOrDown
        button.target = self
        button.action = #selector(closeTapped)
        addSubview(button)
    }

    @objc private func closeTapped() {
        onDismiss?()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// How many tiles fit along the arc before we need to roll. Uses tight
    /// spacing so a typical list fills the whole semicircle (like before) and
    /// rolling only kicks in on real overflow.
    private func capacity() -> Int {
        let radius = origin.radius(in: bounds)
        let totalSweep = 2 * spreadDegrees * .pi / 180
        let arcLength = radius * totalSweep
        let spacing: CGFloat = 58
        return max(3, Int(arcLength / spacing))
    }

    private func layoutItems() {
        let total = items.count
        let anchor = origin.anchor(in: bounds)
        let radius = origin.radius(in: bounds)

        let mid = origin.midAngleDegrees * .pi / 180
        let spread = spreadDegrees * .pi / 180
        let startAngle = mid - spread
        let endAngle = mid + spread

        let cap = capacity()
        let rolling = total > cap
        let visibleCount = rolling ? cap : max(total, 1)
        visibleStart = rolling ? min(max(0, visibleStart), total - cap) : 0
        canScrollBack = rolling && visibleStart > 0
        canScrollFwd = rolling && (visibleStart + visibleCount) < total

        let slice: [Destination] = rolling
            ? Array(items[visibleStart ..< visibleStart + visibleCount])
            : items
        let itemSize: CGFloat = rolling ? 76 : (total > 16 ? 60 : (total > 11 ? 70 : 84))

        let animate = rollAnimation != 0
        let slideDir = rollAnimation
        rollAnimation = 0

        for (index, dest) in slice.enumerated() {
            let t: CGFloat = visibleCount == 1 ? 0.5 : CGFloat(index) / CGFloat(visibleCount - 1)
            let angle = startAngle + t * (endAngle - startAngle)
            let cx = anchor.x + cos(angle) * radius
            let cy = anchor.y + sin(angle) * radius
            let finalFrame = NSRect(x: cx - itemSize / 2, y: cy - itemSize / 2, width: itemSize, height: itemSize)
            let itemView = ItemView(frame: finalFrame, destination: dest)
            itemView.onActed = { [weak self] in self?.onDismiss?() }
            addSubview(itemView)

            if animate {
                // Fade in, sliding a touch along the arc from the direction the
                // roll came from, so the scroll is clearly visible.
                let tangent = angle + .pi / 2
                let offset: CGFloat = 22 * slideDir
                itemView.alphaValue = 0
                itemView.frame = finalFrame.offsetBy(dx: cos(tangent) * offset, dy: sin(tangent) * offset)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.allowsImplicitAnimation = true
                    itemView.animator().alphaValue = 1
                    itemView.animator().frame = finalFrame
                }
            }
        }

        // Clickable roller arrows just past each end of the arc. They sit at the
        // exact end angles (not beyond them) so they stay on-screen — going past
        // the end of a 180° edge fan would push them off the anchor edge.
        if canScrollBack { addRollButton(angleDeg: origin.midAngleDegrees - spreadDegrees, tag: -1) }
        if canScrollFwd  { addRollButton(angleDeg: origin.midAngleDegrees + spreadDegrees, tag: 1) }
    }

    private func addRollButton(angleDeg: CGFloat, tag: Int) {
        let anchor = origin.anchor(in: bounds)
        // Sit just outboard of the end tiles (further along the radius), so the
        // chevron clears the last icon without leaving the window.
        let r = origin.radius(in: bounds) + 30
        let a = angleDeg * .pi / 180
        let p = NSPoint(x: anchor.x + cos(a) * r, y: anchor.y + sin(a) * r)
        let size: CGFloat = 34

        let horizontal = (origin == .top || origin == .bottom)
        let symbol: String
        if horizontal { symbol = tag < 0 ? "chevron.left.circle.fill" : "chevron.right.circle.fill" }
        else          { symbol = tag < 0 ? "chevron.up.circle.fill" : "chevron.down.circle.fill" }

        let button = NSButton(frame: NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Scroll more")
        button.contentTintColor = .controlAccentColor
        button.imageScaling = .scaleProportionallyUpOrDown
        button.tag = tag
        button.target = self
        button.action = #selector(rollButtonClicked(_:))
        addSubview(button)
    }

    @objc private func rollButtonClicked(_ sender: NSButton) {
        let cap = capacity()
        let step = max(1, cap / 2)
        let prev = visibleStart
        visibleStart = min(max(0, visibleStart + sender.tag * step), max(0, items.count - cap))
        if visibleStart != prev { rollAnimation = CGFloat(sender.tag); rebuild() }
    }

    // Roll through overflow with the scroll wheel / trackpad (slides along the
    // arc — up/down for side fans, left/right for top/bottom fans).
    override func scrollWheel(with event: NSEvent) {
        guard items.count > capacity() else { return }
        let dy = event.scrollingDeltaY, dx = event.scrollingDeltaX
        let delta = abs(dy) >= abs(dx) ? dy : dx
        guard abs(delta) > 0.5 else { return }

        let prev = visibleStart
        let dir: CGFloat = delta > 0 ? -1 : 1
        visibleStart += Int(dir)
        let cap = capacity()
        visibleStart = min(max(0, visibleStart), max(0, items.count - cap))
        if visibleStart != prev { rollAnimation = dir; rebuild() }
    }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        layoutItems()
        addCloseButton()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // A soft translucent half-disc fanning out from the anchor, behind the
        // tiles. The arc spans exactly the same sweep as the icons (180° for an
        // edge, ~84° for a corner), so the straight side is a clean diameter and
        // the shape reads as a proper semicircle — no overshoot bulge.
        let anchor = origin.anchor(in: bounds)
        let radius = origin.radius(in: bounds) + 54
        let startDeg = origin.midAngleDegrees - spreadDegrees
        let endDeg = origin.midAngleDegrees + spreadDegrees

        let wedge = NSBezierPath()
        wedge.move(to: anchor)
        wedge.appendArc(withCenter: anchor, radius: radius, startAngle: startDeg, endAngle: endDeg)
        wedge.close()
        NSColor(calibratedWhite: 0.10, alpha: 0.42).setFill()
        wedge.fill()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    // Clicking the empty backdrop (not an item) dismisses the palette.
    override func mouseUp(with event: NSEvent) {
        onDismiss?()
    }
}

// A single circular destination button. It is a file drag destination and also
// responds to a plain click.
final class ItemView: NSView {
    private let destination: Destination
    /// Resolved once at init. `Destination.icon` performs NSWorkspace icon
    /// lookups (and may read from disk), so it must not be recomputed on every
    /// redraw — draw() runs on each highlight/roll animation frame.
    private let cachedIcon: NSImage
    var onActed: (() -> Void)?

    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    init(frame frameRect: NSRect, destination: Destination) {
        self.destination = destination
        self.cachedIcon = destination.icon
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Rounded-square app-icon tile, matching Quick_Drop's look.
        let tileSize: CGFloat = 58
        let tileRect = NSRect(
            x: (bounds.width - tileSize) / 2,
            y: bounds.height - tileSize - 2,
            width: tileSize,
            height: tileSize
        )
        let tile = NSBezierPath(roundedRect: tileRect, xRadius: 14, yRadius: 14)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        if isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.95).setFill()
        } else {
            NSColor(calibratedWhite: 0.16, alpha: 0.78).setFill()
        }
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Subtle ring around the tile.
        NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
        tile.lineWidth = 1
        tile.stroke()

        // Icon centered inside the tile.
        let iconSize: CGFloat = 40
        let iconRect = NSRect(
            x: tileRect.midX - iconSize / 2,
            y: tileRect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        cachedIcon.draw(in: iconRect)

        // Label under the circle.
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let labelShadow = NSShadow()
        labelShadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        labelShadow.shadowBlurRadius = 3
        labelShadow.shadowOffset = NSSize(width: 0, height: -1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
            .shadow: labelShadow
        ]
        let labelRect = NSRect(x: 0, y: 0, width: bounds.width, height: 14)
        (destination.name as NSString).draw(in: labelRect, withAttributes: attrs)
    }

    // MARK: - Click

    override func mouseUp(with event: NSEvent) {
        destination.activate()
        onActed?()
    }

    // MARK: - Dragging destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHighlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isHighlighted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []

        destination.handleDrop(urls: urls)
        isHighlighted = false
        onActed?()
        return true
    }
}

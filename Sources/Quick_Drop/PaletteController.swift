import AppKit

// Borderless windows cannot become key by default, which means they can't
// receive the Escape keypress. This subclass opts in.
final class PaletteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PaletteController {
    private let store: Store
    private var window: PaletteWindow?

    private var autoCloseTimer: Timer?
    private var outsideMouseUpMonitor: Any?
    /// Auto-dismiss the palette if nothing is dropped within this many seconds.
    private let autoCloseSeconds: TimeInterval = 6

    init(store: Store) {
        self.store = store
    }

    var isVisible: Bool { window != nil }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    /// Summon the palette. When `activating` is false (e.g. triggered by a shake
    /// during an in-progress file drag) the window is ordered front WITHOUT
    /// activating the app, so the drag session is not cancelled.
    func show(activating: Bool = true) {
        if isVisible { return }

        // Reload so edits to the JSON take effect on the next summon.
        store.load()

        // Only enabled destinations, then narrowed to those that accept the type
        // of the file(s) currently being dragged (if any).
        let enabled = store.destinations.filter { $0.isEnabled }
        var items = enabled
        if let categories = draggedFileCategories(), !categories.isEmpty {
            let matching = enabled.filter { $0.acceptsAny(of: categories) }
            if !matching.isEmpty { items = matching }
        }

        // The palette is an arc/fan docked to a screen edge/corner (configurable),
        // on whichever screen the cursor is on, so a file can be dragged onto it.
        let origin = ArcOrigin.from(Preferences.shared.arcOrigin)
        let mouse = NSEvent.mouseLocation // bottom-left origin, global screen coords
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let frame = origin.windowFrame(in: vf)

        let win = PaletteWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .popUpMenu
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        win.isReleasedWhenClosed = false

        let view = RadialMenuView(
            frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height),
            items: items,
            origin: origin
        )
        view.onDismiss = { [weak self] in self?.hide() }
        win.contentView = view

        if activating {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Mid-drag: appear on top but leave the drag session (and Finder) alone.
            win.orderFrontRegardless()
        }
        self.window = win
        startAutoDismiss()
        // Dismissal is handled inside the view: Escape, clicking the backdrop,
        // clicking a destination, or completing a drop. We deliberately do NOT
        // dismiss on outside mouse-down, because that fires the moment you press
        // a file in Finder to begin dragging it onto the palette.
    }

    /// Arm the two auto-close paths: a timeout, and a release of the mouse
    /// outside the palette (a drop on the desktop / another app). A drop that
    /// lands on a tile is delivered to *our* window, so the global monitor —
    /// which only sees events destined for other apps — does not fire for it.
    private func startAutoDismiss() {
        let timer = Timer(timeInterval: autoCloseSeconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
        // .common so it still fires while the mouse is in a drag-tracking loop.
        RunLoop.main.add(timer, forMode: .common)
        autoCloseTimer = timer
        outsideMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            // Give a tile's drop handler a beat to run before we tear down.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.hide() }
        }
    }

    /// The file categories of whatever is currently being dragged (read from the
    /// system drag pasteboard), or nil if nothing file-like is on it.
    private func draggedFileCategories() -> Set<String>? {
        let pb = NSPasteboard(name: .drag)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else {
            return nil
        }
        return FileCategory.categories(for: urls)
    }

    func hide() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        if let monitor = outsideMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            outsideMouseUpMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

import AppKit
import ServiceManagement

// Borderless floating card that can become key (so switches/escape work) and is
// draggable by its background.
final class CardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// A clickable category row (rounded pill with title, count, chevron) like the
// "Folders & Locations / Applications & Scripts" rows in the Quick_Drop panel.
final class CategoryRowView: NSView {
    var onClick: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    /// Light vs dark card; flips the subtle fill from white-overlay to
    /// black-overlay so the row is visible on either background.
    var isLight = false { didSet { applyFill(hover: false) } }

    init(title: String, count: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        countLabel.stringValue = count
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        addSubview(countLabel)

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.identifier = NSUserInterfaceItemIdentifier("chev")
        addSubview(chevron)
        self.chevron = chevron
        applyFill(hover: false)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var chevron: NSImageView!

    private func applyFill(hover: Bool) {
        let alpha: CGFloat = hover ? 0.12 : 0.06
        let base: CGFloat = isLight ? 0 : 1
        layer?.backgroundColor = NSColor(calibratedWhite: base, alpha: alpha).cgColor
    }

    func update(count: String) { countLabel.stringValue = count }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 12, y: bounds.height - 20, width: bounds.width - 24, height: 16)
        countLabel.frame = NSRect(x: 12, y: 6, width: bounds.width - 40, height: 14)
        chevron.frame = NSRect(x: bounds.width - 22, y: bounds.midY - 7, width: 12, height: 14)
    }

    override func mouseDown(with event: NSEvent) {
        applyFill(hover: true)
    }
    override func mouseUp(with event: NSEvent) {
        applyFill(hover: false)
        onClick?()
    }
}

// The three logical groupings of destinations shown as category rows. Each maps
// to the kinds it contains and is used to filter the JSON shown in the drawer.
enum DestinationCategory: Hashable, CaseIterable {
    case folders, appsScripts, share

    var title: String {
        switch self {
        case .folders:     return "Folders & Locations"
        case .appsScripts: return "Applications & Scripts"
        case .share:       return "Send & Share"
        }
    }

    func matches(_ d: Destination) -> Bool {
        switch self {
        case .folders:     return d.kind == .folder
        case .appsScripts: return d.kind == .app || d.kind == .script
        case .share:       return d.kind == .share
        }
    }
}

final class PreferencesController: NSObject {
    private let store: Store
    private let prefs = Preferences.shared

    // Wired by AppDelegate so toggles take effect immediately.
    var onHideDockChanged: ((Bool) -> Void)?
    var onShakeChanged: ((Bool) -> Void)?
    var onAppearanceChanged: (() -> Void)?
    var onManageDestinations: (() -> Void)?
    /// Open the destinations manager focused on a given category.
    var onManageCategory: ((DestinationCategory) -> Void)?
    /// The activation hotkey was changed; re-register it.
    var onHotkeyChanged: ((Shortcut) -> Void)?

    private var window: CardWindow?
    private var effectView: NSVisualEffectView!
    private var statusLabel: NSTextField!
    private var arcButtons: [ArcOrigin: NSButton] = [:]
    private var categoryRows: [DestinationCategory: CategoryRowView] = [:]
    private var hotkeyButton: NSButton?
    private var recordMonitor: Any?
    private var recording = false

    init(store: Store) {
        self.store = store
        super.init()
    }

    func show() {
        if window == nil { buildWindow() }
        refreshStatus()
        for (category, row) in categoryRows {
            row.update(count: "\(count(of: category)) configured")
        }
        applyAppearance()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Build

    private func buildWindow() {
        let w: CGFloat = 320
        let pad: CGFloat = 18

        // Vertical layout, all offsets measured from the TOP of the card so the
        // whole thing stacks tightly with no dead space, then the window height
        // is derived from the content. (AppKit y is bottom-up, so each element's
        // frame y is `h - topOffset - height` via fy() below.)
        let iconH: CGFloat = 60
        let iconTop = pad
        let titleTop = iconTop + iconH + 6
        let subtitleTop = titleTop + 24
        let statusTop = subtitleTop + 18
        let rowsTop = statusTop + 18 + 18          // first settings row
        let rowStep: CGFloat = 34
        let arcLabelTop = rowsTop + rowStep * 5 + 8
        let gridTop = arcLabelTop + 16 + 10
        let gridCell: CGFloat = 26
        let gridVStep: CGFloat = 30
        let gridBottom = gridTop + gridCell + gridVStep * 2
        let catTop = gridBottom + 18
        let catH: CGFloat = 44
        let catStep: CGFloat = 52
        let doneTop = catTop + catStep * 2 + catH + 16
        let doneH: CGFloat = 38
        let h = doneTop + doneH + pad

        // Top-offset → AppKit (bottom-up) frame y.
        func fy(_ top: CGFloat, _ height: CGFloat) -> CGFloat { h - top - height }

        let win = CardWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                             styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        win.contentView = effect
        self.effectView = effect

        // Close button (top-right corner).
        let closeBtn = NSButton(frame: NSRect(x: w - 14 - 22, y: h - 14 - 22, width: 22, height: 22))
        closeBtn.isBordered = false
        closeBtn.imagePosition = .imageOnly
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeBtn.contentTintColor = .tertiaryLabelColor
        closeBtn.target = self
        closeBtn.action = #selector(dismiss)
        effect.addSubview(closeBtn)

        // Header.
        let icon = NSImageView(frame: NSRect(x: (w - iconH) / 2, y: fy(iconTop, iconH), width: iconH, height: iconH))
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            icon.image = img
        } else {
            icon.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "Quick_Drop")
            icon.contentTintColor = .white
        }
        effect.addSubview(icon)

        let title = NSTextField(labelWithString: "Quick_Drop")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .labelColor
        title.alignment = .center
        title.frame = NSRect(x: 0, y: fy(titleTop, 22), width: w, height: 22)
        effect.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Drag-and-drop launching")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 0, y: fy(subtitleTop, 16), width: w, height: 16)
        effect.addSubview(subtitle)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = NSColor.systemGreen
        status.alignment = .center
        status.frame = NSRect(x: 0, y: fy(statusTop, 16), width: w, height: 16)
        effect.addSubview(status)
        self.statusLabel = status

        // Settings rows (toggles + popup + hotkey pill).
        let r0 = fy(rowsTop, 18)
        addToggleRow(in: effect, y: r0, title: "Start at Login",
                     isOn: startAtLoginEnabled, action: #selector(toggleStartAtLogin(_:)))
        addToggleRow(in: effect, y: r0 - rowStep, title: "Hide Dock Icon",
                     isOn: prefs.hideDockIcon, action: #selector(toggleHideDock(_:)))
        addToggleRow(in: effect, y: r0 - rowStep * 2, title: "Activate w/ Mouse Shake",
                     isOn: prefs.shakeEnabled, action: #selector(toggleShake(_:)))

        // Appearance popup row.
        let apY = r0 - rowStep * 3
        addLabelRow(in: effect, y: apY, title: "Appearance")
        let popup = NSPopUpButton(frame: NSRect(x: w - 16 - 110, y: apY - 3, width: 110, height: 24))
        popup.addItems(withTitles: ["Clear", "Dark", "Light"])
        popup.selectItem(withTitle: prefs.appearance)
        popup.target = self
        popup.action = #selector(appearanceChanged(_:))
        effect.addSubview(popup)

        // Hotkey recorder row — click the pill, then press the new combination.
        let hkY = r0 - rowStep * 4
        addLabelRow(in: effect, y: hkY, title: "Activation Hotkey")
        let pill = NSButton(frame: NSRect(x: w - 16 - 120, y: hkY - 4, width: 120, height: 24))
        pill.isBordered = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
        pill.layer?.cornerRadius = 6
        pill.target = self
        pill.action = #selector(recordHotkey)
        effect.addSubview(pill)
        self.hotkeyButton = pill
        updateHotkeyDisplay()

        // Arc-origin compass grid.
        addArcOriginGrid(in: effect, width: w,
                         labelY: fy(arcLabelTop, 16),
                         gridTopY: fy(gridTop, gridCell),
                         cell: gridCell, vStep: gridVStep)

        // Category rows — clicking one opens the destinations manager for that group.
        categoryRows.removeAll()
        for (i, category) in DestinationCategory.allCases.enumerated() {
            let row = CategoryRowView(title: category.title, count: "\(count(of: category)) configured")
            row.frame = NSRect(x: 16, y: fy(catTop + CGFloat(i) * catStep, catH), width: w - 32, height: catH)
            row.onClick = { [weak self] in
                self?.dismiss()
                self?.onManageCategory?(category)
            }
            effect.addSubview(row)
            categoryRows[category] = row
        }

        // Bottom dismiss button.
        let done = NSButton(frame: NSRect(x: 16, y: fy(doneTop, doneH), width: w - 32, height: doneH))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\u{1b}"   // Escape actually dismisses now.
        done.wantsLayer = true
        done.layer?.cornerRadius = 9
        done.bezelColor = .controlAccentColor
        done.attributedTitle = NSAttributedString(string: "Press Escape to dismiss", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        done.target = self
        done.action = #selector(dismiss)
        effect.addSubview(done)

        self.window = win
    }

    /// 3×3 compass of arrow buttons letting the user choose which edge/corner the
    /// arc opens from. `labelY` / `gridTopY` are AppKit (bottom-up) frame y's.
    private func addArcOriginGrid(in parent: NSView, width w: CGFloat,
                                  labelY: CGFloat, gridTopY: CGFloat,
                                  cell: CGFloat, vStep: CGFloat) {
        let label = NSTextField(labelWithString: "Arc Opens From")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.frame = NSRect(x: 0, y: labelY, width: w, height: 16)
        parent.addSubview(label)

        let hStep: CGFloat = 34
        let gridW = cell + hStep * 2
        let colXs: [CGFloat] = [(w - gridW) / 2, (w - gridW) / 2 + hStep, (w - gridW) / 2 + hStep * 2]
        let rowYs: [CGFloat] = [gridTopY, gridTopY - vStep, gridTopY - vStep * 2]  // top, mid, bottom

        let layout: [(ArcOrigin, Int, Int)] = [
            (.topLeft, 0, 0), (.top, 0, 1), (.topRight, 0, 2),
            (.left, 1, 0),                  (.right, 1, 2),
            (.bottomLeft, 2, 0), (.bottom, 2, 1), (.bottomRight, 2, 2)
        ]
        for (o, r, c) in layout {
            let b = NSButton(frame: NSRect(x: colXs[c], y: rowYs[r], width: cell, height: cell))
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.image = NSImage(systemSymbolName: o.arrowSymbol, accessibilityDescription: o.label)
            b.imagePosition = .imageOnly
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.target = self
            b.action = #selector(arcOriginClicked(_:))
            b.tag = ArcOrigin.allCases.firstIndex(of: o) ?? 0
            parent.addSubview(b)
            arcButtons[o] = b
        }
        // Center marker.
        let dot = NSTextField(labelWithString: "•")
        dot.alignment = .center
        dot.textColor = .tertiaryLabelColor
        dot.frame = NSRect(x: colXs[1], y: rowYs[1], width: cell, height: cell)
        parent.addSubview(dot)

        updateArcSelection()
    }

    @objc private func arcOriginClicked(_ sender: NSButton) {
        let origin = ArcOrigin.allCases[sender.tag]
        prefs.arcOrigin = origin.rawValue
        updateArcSelection()
    }

    private func updateArcSelection() {
        let current = ArcOrigin.from(prefs.arcOrigin)
        let base: CGFloat = isLight ? 0 : 1
        for (o, b) in arcButtons {
            let selected = (o == current)
            b.contentTintColor = selected ? .white : .secondaryLabelColor
            b.layer?.backgroundColor = selected
                ? NSColor.controlAccentColor.cgColor
                : NSColor(calibratedWhite: base, alpha: 0.08).cgColor
        }
    }

    private func addToggleRow(in parent: NSView, y: CGFloat, title: String, isOn: Bool, action: Selector) {
        addLabelRow(in: parent, y: y, title: title)
        let sw = NSSwitch(frame: NSRect(x: parent.frame.width - 16 - 42, y: y - 2, width: 42, height: 24))
        sw.state = isOn ? .on : .off
        sw.target = self
        sw.action = action
        parent.addSubview(sw)
    }

    private func addLabelRow(in parent: NSView, y: CGFloat, title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        // Width is capped well short of the right-hand control column so labels
        // can never overlap the popup / pill / switch on the same row.
        label.frame = NSRect(x: 16, y: y, width: 168, height: 18)
        parent.addSubview(label)
    }

    // MARK: - Status / appearance

    private func refreshStatus() {
        let n = store.destinations.count
        statusLabel?.stringValue = "● \(n) shortcuts configured · \(prefs.shortcut.displayString)"
    }

    /// True when the card is currently rendering in a light appearance.
    private var isLight: Bool {
        let appearance = effectView?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    private func applyAppearance() {
        switch prefs.appearance {
        case "Dark":
            window?.appearance = NSAppearance(named: .darkAqua)
            effectView?.material = .windowBackground
        case "Light":
            window?.appearance = NSAppearance(named: .aqua)
            effectView?.material = .windowBackground
        default: // Clear
            window?.appearance = NSAppearance(named: .darkAqua)
            effectView?.material = .hudWindow
        }
        // Recolor the layer-backed fills (cgColors don't auto-adapt) now that the
        // effective appearance has switched. Semantic text colors adapt on their own.
        updateHotkeyDisplay()
        updateArcSelection()
        for row in categoryRows.values { row.isLight = isLight }
    }

    // MARK: - Actions

    @objc private func toggleHideDock(_ sender: NSSwitch) {
        prefs.hideDockIcon = (sender.state == .on)
        onHideDockChanged?(prefs.hideDockIcon)
    }

    @objc private func toggleShake(_ sender: NSSwitch) {
        prefs.shakeEnabled = (sender.state == .on)
        onShakeChanged?(prefs.shakeEnabled)
    }

    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        prefs.appearance = sender.titleOfSelectedItem ?? "Clear"
        applyAppearance()
        onAppearanceChanged?()
    }

    @objc private func dismiss() {
        if recording { stopRecording() }
        window?.orderOut(nil)
    }

    private func count(of category: DestinationCategory) -> Int {
        store.destinations.filter { category.matches($0) }.count
    }

    // MARK: - Hotkey recording

    private func pillTitle(_ text: String, recording: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: recording ? NSColor.systemOrange : NSColor.labelColor
        ])
    }

    private func pillFill(highlight: Bool) -> CGColor {
        let base: CGFloat = isLight ? 0 : 1
        let alpha: CGFloat = highlight ? 0.18 : 0.10
        return NSColor(calibratedWhite: base, alpha: alpha).cgColor
    }

    private func updateHotkeyDisplay() {
        hotkeyButton?.attributedTitle = pillTitle(prefs.shortcut.displayString, recording: false)
        hotkeyButton?.layer?.backgroundColor = pillFill(highlight: false)
    }

    @objc private func recordHotkey() {
        if recording { stopRecording(); return }
        recording = true
        hotkeyButton?.attributedTitle = pillTitle("Type shortcut…", recording: true)
        hotkeyButton?.layer?.backgroundColor = pillFill(highlight: true)

        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.recording else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Escape with no modifiers cancels recording.
            if event.keyCode == 53 && mods.isEmpty {
                self.stopRecording()
                return nil
            }
            // Require at least one modifier so we don't capture ordinary typing.
            guard !mods.isEmpty else { return nil }
            let shortcut = Shortcut.from(event: event)
            self.prefs.shortcut = shortcut
            self.stopRecording()
            self.onHotkeyChanged?(shortcut)
            self.refreshStatus()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = recordMonitor { NSEvent.removeMonitor(m); recordMonitor = nil }
        updateHotkeyDisplay()
    }

    // MARK: - Start at Login (ServiceManagement)

    private var startAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleStartAtLogin(_ sender: NSSwitch) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Destination.notify(title: "Quick_Drop", body: "Login item change failed: \(error.localizedDescription)")
            sender.state = startAtLoginEnabled ? .on : .off
        }
    }
}

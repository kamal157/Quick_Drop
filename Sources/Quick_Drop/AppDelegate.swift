import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = Store()
    private let prefs = Preferences.shared
    private lazy var palette = PaletteController(store: store)
    private lazy var settings = SettingsController(store: store)
    private lazy var preferences = PreferencesController(store: store)
    private let shakeDetector = ShakeDetector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = img
        }
        applyDockPolicy()
        setupStatusItem()
        setupHotKey()
        setupShakeDetector()
        setupPreferencesWiring()
        announceLaunch()
    }

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(prefs.hideDockIcon ? .accessory : .regular)
    }

    private func setupPreferencesWiring() {
        preferences.onHideDockChanged = { hidden in
            NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        }
        preferences.onShakeChanged = { [weak self] enabled in
            if enabled { self?.shakeDetector.start() } else { self?.shakeDetector.stop() }
        }
        preferences.onManageDestinations = { [weak self] in self?.settings.show() }
        preferences.onManageCategory = { [weak self] category in self?.settings.show(category: category) }
        preferences.onHotkeyChanged = { shortcut in
            HotKey.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        }
        preferences.onAppearanceChanged = { [weak self] in self?.settings.refreshAppearance() }
    }

    /// Visible proof the agent started: briefly label the menu-bar icon so the
    /// user can locate it, then collapse back to just the icon.
    private func announceLaunch() {
        guard let button = statusItem.button else { return }
        let savedImage = button.image
        button.image = nil
        button.title = "◎ Quick_Drop ready — ⌃⌥Space"
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            button.title = ""
            button.image = savedImage
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Monochrome template glyph of the app icon (parachute + package).
            button.image = AppDelegate.menuBarImage()
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Palette", action: #selector(showPalette), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "Manage Destinations…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        let hk = NSMenuItem(title: "Hotkey: ⌃⌥Space  ·  or shake while dragging", action: nil, keyEquivalent: "")
        hk.isEnabled = false
        menu.addItem(hk)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Quick_Drop", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func setupHotKey() {
        HotKey.shared.onPressed = { [weak self] in
            self?.palette.toggle()
        }
        let sc = prefs.shortcut
        HotKey.shared.register(keyCode: sc.keyCode, modifiers: sc.modifiers)
    }

    private func setupShakeDetector() {
        shakeDetector.onShake = { [weak self] in
            // Summoned mid-drag: don't activate, or we'd cancel the Finder drag.
            self?.palette.show(activating: false)
        }
        if prefs.shakeEnabled { shakeDetector.start() }
    }

    @objc private func showPalette() {
        palette.show()
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func openPreferences() {
        preferences.show()
    }

    @objc private func reloadConfig() {
        store.load()
        Destination.notify(title: "Quick_Drop", body: "Reloaded \(store.destinations.count) destinations.")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// A monochrome template image (parachute dropping a package) for the menu
    /// bar — macOS tints it automatically for light/dark menu bars. This is the
    /// lighter, outlined variant (the solid version is `menuBarImageHeavy`).
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let lw: CGFloat = 1.05

            // Canopy: outlined dome with a scalloped base.
            let dome = NSBezierPath()
            dome.lineWidth = lw; dome.lineJoinStyle = .round; dome.lineCapStyle = .round
            dome.move(to: NSPoint(x: 2.8, y: 11.2))
            dome.curve(to: NSPoint(x: 15.2, y: 11.2),
                       controlPoint1: NSPoint(x: 2.6, y: 19.0),
                       controlPoint2: NSPoint(x: 15.4, y: 19.0))
            let bumps = 3
            let seg = (15.2 - 2.8) / CGFloat(bumps)
            for i in 0..<bumps {
                let x0 = 15.2 - CGFloat(i) * seg
                let x1 = x0 - seg
                dome.curve(to: NSPoint(x: x1, y: 11.2),
                           controlPoint1: NSPoint(x: (x0 + x1) / 2, y: 9.9),
                           controlPoint2: NSPoint(x: (x0 + x1) / 2, y: 9.9))
            }
            dome.stroke()

            // Center gore line (hint of canopy panels).
            let gore = NSBezierPath(); gore.lineWidth = 0.85
            gore.move(to: NSPoint(x: 9, y: 17.6)); gore.line(to: NSPoint(x: 9, y: 11.1))
            gore.stroke()

            // Hanger lines.
            let lines = NSBezierPath(); lines.lineWidth = lw; lines.lineCapStyle = .round
            lines.move(to: NSPoint(x: 5.0, y: 11.0)); lines.line(to: NSPoint(x: 6.7, y: 8.7))
            lines.move(to: NSPoint(x: 13.0, y: 11.0)); lines.line(to: NSPoint(x: 11.3, y: 8.7))
            lines.stroke()

            // Package box (outlined).
            let box = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 2.0, width: 7.0, height: 6.0),
                                   xRadius: 1.2, yRadius: 1.2)
            box.lineWidth = lw; box.lineJoinStyle = .round; box.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Backup: the original solid-filled (heavier) menu-bar glyph.
    static func menuBarImageHeavy() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let dome = NSBezierPath()
            dome.move(to: NSPoint(x: 2.6, y: 11.2))
            dome.curve(to: NSPoint(x: 15.4, y: 11.2),
                       controlPoint1: NSPoint(x: 2.2, y: 19.6),
                       controlPoint2: NSPoint(x: 15.8, y: 19.6))
            let bumps = 3
            let seg = (15.4 - 2.6) / CGFloat(bumps)
            for i in 0..<bumps {
                let x0 = 15.4 - CGFloat(i) * seg
                let x1 = x0 - seg
                dome.curve(to: NSPoint(x: x1, y: 11.2),
                           controlPoint1: NSPoint(x: (x0 + x1) / 2, y: 9.7),
                           controlPoint2: NSPoint(x: (x0 + x1) / 2, y: 9.7))
            }
            dome.close(); dome.fill()
            let lines = NSBezierPath(); lines.lineWidth = 1.0; lines.lineCapStyle = .round
            lines.move(to: NSPoint(x: 4.8, y: 11.0)); lines.line(to: NSPoint(x: 6.6, y: 8.6))
            lines.move(to: NSPoint(x: 13.2, y: 11.0)); lines.line(to: NSPoint(x: 11.4, y: 8.6))
            lines.stroke()
            NSBezierPath(roundedRect: NSRect(x: 5.4, y: 1.8, width: 7.2, height: 6.2),
                         xRadius: 1.1, yRadius: 1.1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

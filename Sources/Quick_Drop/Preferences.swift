import AppKit

// Lightweight user preferences backed by UserDefaults. These mirror the toggles
// in the styled preferences panel (see PreferencesController).
final class Preferences {
    static let shared = Preferences()

    private let d = UserDefaults.standard

    private init() {
        if d.object(forKey: Keys.hideDockIcon) == nil { d.set(true, forKey: Keys.hideDockIcon) }
        if d.object(forKey: Keys.shakeEnabled) == nil { d.set(true, forKey: Keys.shakeEnabled) }
        if d.object(forKey: Keys.appearance) == nil { d.set("Clear", forKey: Keys.appearance) }
    }

    private enum Keys {
        static let hideDockIcon = "hideDockIcon"
        static let shakeEnabled = "shakeEnabled"
        static let appearance = "appearance"
        static let arcOrigin = "arcOrigin"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
    }

    /// The activation hotkey for showing the palette. Defaults to ⌃⌥Space.
    var shortcut: Shortcut {
        get {
            guard d.object(forKey: Keys.hotkeyKeyCode) != nil else { return .default }
            return Shortcut(keyCode: UInt32(d.integer(forKey: Keys.hotkeyKeyCode)),
                            modifiers: UInt32(d.integer(forKey: Keys.hotkeyModifiers)))
        }
        set {
            d.set(Int(newValue.keyCode), forKey: Keys.hotkeyKeyCode)
            d.set(Int(newValue.modifiers), forKey: Keys.hotkeyModifiers)
        }
    }

    /// Which edge/corner the arc opens from (ArcOrigin rawValue). Default "right".
    var arcOrigin: String {
        get { d.string(forKey: Keys.arcOrigin) ?? "right" }
        set { d.set(newValue, forKey: Keys.arcOrigin) }
    }

    var hideDockIcon: Bool {
        get { d.bool(forKey: Keys.hideDockIcon) }
        set { d.set(newValue, forKey: Keys.hideDockIcon) }
    }

    var shakeEnabled: Bool {
        get { d.bool(forKey: Keys.shakeEnabled) }
        set { d.set(newValue, forKey: Keys.shakeEnabled) }
    }

    /// "Clear" | "Dark" | "Light"
    var appearance: String {
        get { d.string(forKey: Keys.appearance) ?? "Clear" }
        set { d.set(newValue, forKey: Keys.appearance) }
    }
}

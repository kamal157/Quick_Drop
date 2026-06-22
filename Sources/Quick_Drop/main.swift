import AppKit

// Entry point. We run as an "accessory" app: no Dock icon, no menu bar app menu,
// just a status-bar item and a global hotkey that summons the radial palette.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

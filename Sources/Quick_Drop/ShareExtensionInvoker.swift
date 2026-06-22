import AppKit

// Invokes a macOS Share extension (e.g. LocalSend's "Send" share sheet) by title
// and performs it directly with the dropped files.
//
// The legacy `NSSharingService.sharingServices(forItems:)` API only returns
// built-in services and never third-party app extensions. `NSSharingServicePicker`,
// however, hands its delegate the FULL proposed list — extensions included — so
// we use that as a discovery channel: find the matching extension, perform it
// with our items, and return an empty list so no picker UI is shown.
//
// Note: the extension must be enabled in System Settings → Login Items &
// Extensions → Sharing. If it isn't, we fall back to opening the app with the
// files (and tell the user).
final class ShareExtensionInvoker: NSObject, NSSharingServicePickerDelegate {
    static let shared = ShareExtensionInvoker()

    private var picker: NSSharingServicePicker?
    private var anchorWindow: NSWindow?
    private var anchorView: NSView?
    private var matchKey = ""
    private var displayName = ""
    private var fallbackAppPath: String?

    /// Send `items` to the first share service whose title contains `key`
    /// (case-insensitive). If not found, open `fallbackAppPath` with the items.
    func send(_ items: [URL], toServiceTitleContaining key: String, name: String, fallbackAppPath: String? = nil) {
        matchKey = key.lowercased()
        displayName = name
        self.fallbackAppPath = fallbackAppPath

        // A small anchor window for the (transient) picker. It must be a real,
        // keyed, on-screen window or the picker won't call its delegate.
        let mouse = NSEvent.mouseLocation
        let win = NSWindow(contentRect: NSRect(x: mouse.x - 3, y: mouse.y - 3, width: 6, height: 6),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .floating
        win.backgroundColor = .clear
        win.alphaValue = 0.02
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        anchorWindow = win
        anchorView = view

        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        self.picker = picker
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.anchorView else { return }
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        if let svc = proposedServices.first(where: { $0.title.lowercased().contains(matchKey) }) {
            // Found the extension — perform it directly and suppress the picker UI.
            DispatchQueue.main.async { [weak self] in
                svc.perform(withItems: items)
                self?.cleanup()
            }
            return []
        }

        // Extension not enabled/found — open the app with the files instead.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let appPath = self.fallbackAppPath,
               let urls = items as? [URL], !urls.isEmpty {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-a", appPath] + urls.map { $0.path }
                try? task.run()
            }
            Destination.notify(title: "Quick_Drop",
                               body: "Enable the \(self.displayName) extension in System Settings → Login Items & Extensions → Sharing for direct send.")
            self.cleanup()
        }
        return []
    }

    private func cleanup() {
        anchorWindow?.orderOut(nil)
        anchorWindow = nil
        anchorView = nil
        picker = nil
    }
}

import AppKit
import UniformTypeIdentifiers

// A single pinned target in the palette.
enum DestinationKind: String, Codable {
    case folder   // a directory: dropped files are copied (or moved) into it
    case app      // an application: dropped files are opened with it; click launches it
    case script   // an executable script: dropped file paths are passed as arguments
    case share    // a macOS Share Service (AirDrop, Messages, Mail, …) via NSSharingService
}

struct Destination: Codable {
    var name: String
    var kind: DestinationKind
    var path: String
    /// For folders only: move files instead of copying them.
    var moveOnDrop: Bool?
    /// Optional custom icon file (png/icns). Falls back to the system icon for `path`.
    var iconPath: String?
    /// For `share` kind only: which Share Service to use — "airdrop", "messages", or "mail".
    var service: String? = nil
    /// Whether this destination appears in the palette. nil == enabled.
    var enabled: Bool? = nil
    /// File categories this destination accepts (FileCategory raw values), e.g.
    /// ["image","pdf"]. nil/empty means it accepts any file type.
    var accepts: [String]? = nil

    var isEnabled: Bool { enabled ?? true }

    /// True if this destination should be offered for a drag containing the
    /// given file categories.
    func acceptsAny(of categories: Set<String>) -> Bool {
        guard let accepts = accepts, !accepts.isEmpty else { return true }
        if accepts.contains("any") { return true }
        return !Set(accepts).isDisjoint(with: categories)
    }

    var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }

    var icon: NSImage {
        if let iconPath = iconPath {
            let p = (iconPath as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: p) { return img }
            // iconPath may point at an app/bundle — use its system icon.
            if FileManager.default.fileExists(atPath: p) {
                return NSWorkspace.shared.icon(forFile: p)
            }
        }
        // Share destinations have no file path; prefer the real app icon, then
        // fall back to an SF Symbol per service.
        if kind == .share {
            if let appPath = Destination.shareAppPath(for: service),
               FileManager.default.fileExists(atPath: appPath) {
                return NSWorkspace.shared.icon(forFile: appPath)
            }
            let symbol = Destination.shareSymbol(for: service)
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: name) {
                return img
            }
        }
        let resolved = url.path
        if FileManager.default.fileExists(atPath: resolved) {
            return NSWorkspace.shared.icon(forFile: resolved)
        }
        // Generic placeholder when the path is missing.
        return NSWorkspace.shared.icon(for: .data)
    }

    // MARK: - Click (no files dropped)

    func activate() {
        switch kind {
        case .folder, .app:
            NSWorkspace.shared.open(url)
        case .script:
            runScript(with: [])
        case .share:
            // Nothing to share on a bare click; share needs files.
            Destination.notify(title: "Quick_Drop", body: "Drag files onto \(name) to share them.")
        }
    }

    // MARK: - Drop

    func handleDrop(urls: [URL]) {
        guard !urls.isEmpty else { activate(); return }
        switch kind {
        case .folder:
            copyOrMove(urls: urls)
        case .app:
            openWithApp(urls: urls)
        case .script:
            runScript(with: urls.map { $0.path })
        case .share:
            performShare(urls: urls)
        }
    }

    private func performShare(urls: [URL]) {
        guard !urls.isEmpty else {
            Destination.notify(title: "Quick_Drop", body: "Drag files onto \(name) to share them.")
            return
        }
        let key = (service ?? "").lowercased()

        // AirDrop / Messages / Mail are reliable built-in services with public
        // constants — perform them directly.
        if let svc = Destination.builtInService(for: key) {
            NSApp.activate(ignoringOtherApps: true)
            guard svc.canPerform(withItems: urls) else {
                Destination.notify(title: "Quick_Drop", body: "\(name) can't accept those items.")
                return
            }
            svc.perform(withItems: urls)
            return
        }

        // Everything else — Notes, Reminders, LocalSend and any other third-party
        // share extension — is discovered and invoked through the picker delegate,
        // which (unlike the legacy API) enumerates app extensions.
        ShareExtensionInvoker.shared.send(urls, toServiceTitleContaining: key, name: name,
                                          fallbackAppPath: Destination.shareAppPath(for: service))
    }

    /// A built-in NSSharingService for the well-known keys, or nil.
    static func builtInService(for key: String) -> NSSharingService? {
        let named: NSSharingService.Name?
        switch key {
        case "messages", "message": named = .composeMessage
        case "mail", "email":       named = .composeEmail
        case "airdrop", "":         named = .sendViaAirDrop
        default:                     return nil
        }
        return named.flatMap { NSSharingService(named: $0) }
    }

    private func copyOrMove(urls: [URL]) {
        let fm = FileManager.default
        let move = moveOnDrop ?? false
        for src in urls {
            let dest = url.appendingPathComponent(src.lastPathComponent)
            do {
                if fm.fileExists(atPath: dest.path) {
                    // Avoid clobbering: append a numeric suffix.
                    let unique = Destination.uniqueDestination(for: dest, fm: fm)
                    if move { try fm.moveItem(at: src, to: unique) }
                    else { try fm.copyItem(at: src, to: unique) }
                } else {
                    if move { try fm.moveItem(at: src, to: dest) }
                    else { try fm.copyItem(at: src, to: dest) }
                }
            } catch {
                Destination.notify(title: "Quick_Drop", body: "Failed for \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func openWithApp(urls: [URL]) {
        // Use the `open` tool: it reliably delivers the documents to the app
        // (firing application:openFiles:/open:), launching it or routing to a
        // running instance — which is exactly how LocalSend queues files to send.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", url.path] + urls.map { $0.path }
        do {
            try task.run()
        } catch {
            // Fallback to the Workspace API.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: url, configuration: config) { _, err in
                if let err = err {
                    Destination.notify(title: "Quick_Drop", body: "Open failed: \(err.localizedDescription)")
                }
            }
        }
    }

    private func runScript(with args: [String]) {
        let process = Process()
        process.executableURL = url
        process.arguments = args
        do {
            try process.run()
        } catch {
            // Fall back to /bin/sh if the file is not directly executable.
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = [url.path] + args
            do { try shell.run() }
            catch { Destination.notify(title: "Quick_Drop", body: "Script failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Helpers

    static func uniqueDestination(for url: URL, fm: FileManager) -> URL {
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    /// App bundle whose icon best represents a share destination, if any.
    static func shareAppPath(for service: String?) -> String? {
        switch (service ?? "").lowercased() {
        case "messages", "message": return "/System/Applications/Messages.app"
        case "mail", "email":       return "/System/Applications/Mail.app"
        case "notes":               return "/System/Applications/Notes.app"
        case "reminders":           return "/System/Applications/Reminders.app"
        case "localsend":           return "/Applications/LocalSend.app"
        case "airdrop":             return "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"
        default:                     return nil
        }
    }

    /// SF Symbol name to display for a share destination (icon fallback).
    static func shareSymbol(for service: String?) -> String {
        switch (service ?? "").lowercased() {
        case "messages", "message": return "message.fill"
        case "mail", "email":       return "envelope.fill"
        case "notes":               return "note.text"
        case "reminders":           return "checklist"
        case "localsend":           return "paperplane.fill"
        case "airdrop":             return "dot.radiowaves.right"
        default:                     return "square.and.arrow.up"
        }
    }

    static func notify(title: String, body: String) {
        // Logged to Console rather than posted as a system notification, which
        // would require a bundle identifier and user authorization.
        NSLog("[%@] %@", title, body)
    }
}

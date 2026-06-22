import AppKit

// Loads and persists the list of destinations as JSON in
// ~/Library/Application Support/Quick_Drop/destinations.json
final class Store {
    private(set) var destinations: [Destination] = []

    private var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Quick_Drop", isDirectory: true)
    }

    var configURL: URL {
        supportDir.appendingPathComponent("destinations.json")
    }

    init() {
        load()
    }

    func load() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configURL.path) {
            destinations = Store.defaultDestinations()
            save()
            return
        }
        do {
            let data = try Data(contentsOf: configURL)
            destinations = try JSONDecoder().decode([Destination].self, from: data)
        } catch {
            Destination.notify(title: "Quick_Drop", body: "Could not read config, using defaults.")
            destinations = Store.defaultDestinations()
        }
    }

    /// Replace the whole list (used by the Settings window) and persist.
    func replaceAll(_ items: [Destination]) {
        destinations = items
        save()
    }

    func add(_ destination: Destination) {
        destinations.append(destination)
        save()
    }

    func remove(at index: Int) {
        guard destinations.indices.contains(index) else { return }
        destinations.remove(at: index)
        save()
    }

    func update(_ destination: Destination, at index: Int) {
        guard destinations.indices.contains(index) else { return }
        destinations[index] = destination
        save()
    }

    func save() {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let data = try encoder.encode(destinations)
            // Atomic write so a crash mid-write can't truncate the config.
            try data.write(to: configURL, options: .atomic)
        } catch {
            // Don't fail silently: a lost save means lost destination edits.
            Destination.notify(title: "Quick_Drop",
                               body: "Could not save destinations: \(error.localizedDescription)")
        }
    }

    func openConfigInEditor() {
        // Make sure it exists on disk first.
        if !FileManager.default.fileExists(atPath: configURL.path) { save() }
        NSWorkspace.shared.open(configURL)
    }

    static func defaultDestinations() -> [Destination] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = home.appendingPathComponent("Desktop").path
        let downloads = home.appendingPathComponent("Downloads").path
        let documents = home.appendingPathComponent("Documents").path
        return [
            Destination(name: "Desktop", kind: .folder, path: desktop, moveOnDrop: false, iconPath: nil),
            Destination(name: "Downloads", kind: .folder, path: downloads, moveOnDrop: false, iconPath: nil),
            Destination(name: "Documents", kind: .folder, path: documents, moveOnDrop: false, iconPath: nil),
            Destination(name: "Preview", kind: .app, path: "/System/Applications/Preview.app", moveOnDrop: nil, iconPath: nil),
            Destination(name: "AirDrop", kind: .share, path: "", moveOnDrop: nil, iconPath: nil, service: "airdrop"),
            Destination(name: "Messages", kind: .share, path: "", moveOnDrop: nil, iconPath: nil, service: "messages"),
            Destination(name: "Mail", kind: .share, path: "", moveOnDrop: nil, iconPath: nil, service: "mail"),
            Destination(name: "Notes", kind: .share, path: "", moveOnDrop: nil, iconPath: nil, service: "notes")
        ]
    }
}

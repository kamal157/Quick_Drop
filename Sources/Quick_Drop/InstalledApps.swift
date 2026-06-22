import AppKit

// Enumerates installed applications from the standard locations, so the editor
// can offer a pick-list instead of a free-text path.
struct InstalledApp {
    let name: String
    let path: String
}

enum InstalledApps {
    private static let searchPaths: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
    ]

    /// All `.app` bundles found, de-duplicated by name and sorted alphabetically.
    static func all() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for dir in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let name = (entry as NSString).deletingPathExtension
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                apps.append(InstalledApp(name: name, path: (dir as NSString).appendingPathComponent(entry)))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

import Foundation
import UniformTypeIdentifiers

// Maps a file to a coarse category used for filtering which destinations appear
// in the palette for a given drag.
enum FileCategory {
    // Raw values match what Destination.accepts stores.
    static let all = ["image", "video", "audio", "pdf", "text", "folder", "other"]

    static func category(for url: URL) -> String {
        let type: UTType?
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]), let ct = values.contentType {
            type = ct
        } else {
            type = UTType(filenameExtension: url.pathExtension)
        }
        guard let t = type else { return "other" }

        if t.conforms(to: .image) { return "image" }
        if t.conforms(to: .movie) || t.conforms(to: .audiovisualContent) { return "video" }
        if t.conforms(to: .audio) { return "audio" }
        if t.conforms(to: .pdf) { return "pdf" }
        if t.conforms(to: .folder) || t.conforms(to: .directory) { return "folder" }
        if t.conforms(to: .text) || t.conforms(to: .sourceCode) { return "text" }
        return "other"
    }

    static func categories(for urls: [URL]) -> Set<String> {
        Set(urls.map { category(for: $0) })
    }

    /// Human label for the editor checkboxes.
    static func label(_ raw: String) -> String {
        switch raw {
        case "image": return "Images"
        case "video": return "Video"
        case "audio": return "Audio"
        case "pdf": return "PDF"
        case "text": return "Text"
        case "folder": return "Folders"
        default: return "Other"
        }
    }
}

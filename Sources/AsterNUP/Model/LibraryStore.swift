import Foundation
import AppKit

/// The persisted library: ~/Library/Application Support/AsterNUP/library.json (written atomically).
final class LibraryStore: ObservableObject {
    @Published private(set) var entries: [GameEntry] = []

    init() { load() }

    func load() {
        guard let d = try? Data(contentsOf: Paths.library) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let e = try? dec.decode([GameEntry].self, from: d) { entries = e }
        else {
            // Keep an unreadable library aside instead of overwriting it.
            let aside = Paths.library.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: Paths.library, to: aside)
            AppLog.write("library.json unreadable; kept a copy at \(aside.path)")
        }
    }

    func save() {
        Paths.ensure(Paths.support)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(entries).write(to: Paths.library, options: .atomic) }
        catch { AppLog.write("library save failed: \(error)") }
    }

    func upsert(_ e: GameEntry) {
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
        save()
    }

    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; save() }

    func entry(_ id: UUID) -> GameEntry? { entries.first { $0.id == id } }

    func managedEntry(titleID: String) -> GameEntry? { entries.first { $0.kind == .managed && $0.titleID?.uppercased() == titleID.uppercased() } }

    /// Copies artwork into AsterNUP's own folder so the tile survives the source moving.
    static func importArtwork(from path: String?, for id: UUID) -> String? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        Paths.ensure(Paths.artwork)
        let ext = URL(fileURLWithPath: path).pathExtension.isEmpty ? "png" : URL(fileURLWithPath: path).pathExtension
        let dst = Paths.artwork.appendingPathComponent("\(id.uuidString).\(ext)")
        try? FileManager.default.removeItem(at: dst)
        do { try FileManager.default.copyItem(atPath: path, toPath: dst.path); return dst.path } catch { return nil }
    }

    /// Artwork for an existing app: its icon, rendered to PNG.
    static func appIconArtwork(app: URL, for id: UUID) -> String? {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 512, height: 512)
        guard let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        Paths.ensure(Paths.artwork)
        let dst = Paths.artwork.appendingPathComponent("\(id.uuidString).png")
        do { try png.write(to: dst); return dst.path } catch { return nil }
    }
}

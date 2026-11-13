import Foundation

/// ZIP backups of a game's save folder, verified by extracting and comparing every file's SHA-256.
enum SaveBackup {
    struct Result { var zip: URL; var files: Int; var bytes: Int64 }

    static func backup(saveFolder: URL, title: String, into folder: URL) async throws -> Result {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: saveFolder.path, isDirectory: &isDir), isDir.boolValue else {
            throw BackendError("There is no save folder yet at \(saveFolder.path). Play and save once first.")
        }
        let source = try hashes(in: saveFolder)
        guard !source.isEmpty else { throw BackendError("The save folder is empty: nothing to back up.") }
        let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dir = folder.appendingPathComponent(safe, isDirectory: true)
        Paths.ensure(dir)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let zip = dir.appendingPathComponent("\(safe) save \(f.string(from: Date())).zip")
        let tmpZip = zip.appendingPathExtension("partial")
        let r = await Proc.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", saveFolder.path, tmpZip.path])
        guard r.status == 0 else { try? fm.removeItem(at: tmpZip); throw BackendError("ditto failed: \(r.err)") }
        // Verify: extract into a temporary folder and compare every file.
        let check = fm.temporaryDirectory.appendingPathComponent("asternup-verify-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: check) }
        let x = await Proc.run("/usr/bin/ditto", ["-x", "-k", tmpZip.path, check.path])
        guard x.status == 0 else { try? fm.removeItem(at: tmpZip); throw BackendError("The ZIP could not be read back: \(x.err)") }
        let extracted = try hashes(in: check.appendingPathComponent(saveFolder.lastPathComponent))
        guard extracted == source else {
            try? fm.removeItem(at: tmpZip)
            throw BackendError("Verification failed: the ZIP's contents differ from the save folder. Nothing was kept.")
        }
        try fm.moveItem(at: tmpZip, to: zip)
        let bytes = source.values.reduce(Int64(0)) { $0 + $1.1 }
        return Result(zip: zip, files: source.count, bytes: bytes)
    }

    /// relative path → (sha256, size)
    static func hashes(in root: URL) throws -> [String: (String, Int64)] {
        var out: [String: (String, Int64)] = [:]
        let rootPath = root.resolvingSymlinksInPath().path
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return out }
        for case let u as URL in en {
            let v = try u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard v.isRegularFile == true else { continue }
            let rel = String(u.resolvingSymlinksInPath().path.dropFirst(rootPath.count))
            out[rel] = (try FileHash.sha256(u), Int64(v.fileSize ?? 0))
        }
        return out
    }
}

extension Dictionary where Key == String, Value == (String, Int64) {
    static func == (a: Self, b: Self) -> Bool {
        a.count == b.count && a.allSatisfy { k, v in b[k].map { $0.0 == v.0 && $0.1 == v.1 } ?? false }
    }
}

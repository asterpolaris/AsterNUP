import Foundation
import CryptoKit

enum Paths {
    static let fm = FileManager.default
    static let home = fm.homeDirectoryForCurrentUser
    /// ASTERNUP_DATA_DIR relocates AsterNUP's own data (tests use it to keep the real library untouched).
    static let dataOverride = ProcessInfo.processInfo.environment["ASTERNUP_DATA_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    static let support = dataOverride ?? home.appendingPathComponent("Library/Application Support/AsterNUP", isDirectory: true)
    static let library = support.appendingPathComponent("library.json")
    static let homeSettings = support.appendingPathComponent("home-settings.json")
    static let artwork = support.appendingPathComponent("Artwork", isDirectory: true)
    static let staging = support.appendingPathComponent("Staging", isDirectory: true)
    static let builds = support.appendingPathComponent("Builds", isDirectory: true)
    static let inspections = support.appendingPathComponent("Inspections", isDirectory: true)
    /// Installed game apps live where Finder can open them.
    static let games = dataOverride?.appendingPathComponent("Games", isDirectory: true) ?? home.appendingPathComponent("Applications/AsterNUP Games", isDirectory: true)
    static let logs = home.appendingPathComponent("Library/Logs/AsterNUP", isDirectory: true)

    /// The nxnative checkout. Override with the ASTERNUP_BACKEND environment variable or the `BackendPath` default.
    static var backendCheckout: URL {
        if let p = ProcessInfo.processInfo.environment["ASTERNUP_BACKEND"], !p.isEmpty { return URL(fileURLWithPath: p) }
        if let p = UserDefaults.standard.string(forKey: "BackendPath"), !p.isEmpty { return URL(fileURLWithPath: p) }
        return support.appendingPathComponent("Backend/nxnative", isDirectory: true)
    }

    /// The backend's own Python environment (Homebrew's Python refuses system-wide pip installs, PEP 668).
    static var pythonVenv: URL {
        if let p = ProcessInfo.processInfo.environment["ASTERNUP_VENV"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return home.appendingPathComponent("Library/Application Support/AsterNUP/Backend/venv", isDirectory: true)
    }

    /// Bundled resources (Contents/Resources/Backend), with a fallback to the source tree for `swift run`.
    static func resource(_ name: String) -> URL {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Backend/\(name)"), fm.fileExists(atPath: r.path) { return r }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Backend/\(name)")
        return src
    }

    static func ensure(_ url: URL) { try? fm.createDirectory(at: url, withIntermediateDirectories: true) }
}

/// Log file for AsterNUP itself.
enum AppLog {
    static let url: URL = { Paths.ensure(Paths.logs); return Paths.logs.appendingPathComponent("AsterNUP.log") }()
    static func write(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}

struct ProcResult { var status: Int32; var out: String; var err: String }

enum Proc {
    /// PATH for tools a GUI app does not inherit (Homebrew, python.org Python).
    static let toolPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func env(_ extra: [String: String] = [:]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        let venvBin = Paths.pythonVenv.appendingPathComponent("bin").path
        let venv = FileManager.default.isExecutableFile(atPath: venvBin + "/python3") ? venvBin + ":" : ""
        e["PATH"] = venv + toolPath + ":" + (e["PATH"] ?? "")
        e.removeValue(forKey: "VIRTUAL_ENV"); e.removeValue(forKey: "PYTHONHOME"); e.removeValue(forKey: "PYTHONPATH")
        e["PYTHONDONTWRITEBYTECODE"] = "1"
        for (k, v) in extra { e[k] = v }
        return e
    }

    static func run(_ exe: String, _ args: [String], cwd: URL? = nil, extraEnv: [String: String] = [:]) async -> ProcResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                if exe.hasPrefix("/") { p.executableURL = URL(fileURLWithPath: exe); p.arguments = args }
                else { p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = [exe] + args }
                p.environment = env(extraEnv)
                if let cwd { p.currentDirectoryURL = cwd }
                let o = Pipe(), e = Pipe()
                p.standardOutput = o; p.standardError = e
                do { try p.run() } catch {
                    cont.resume(returning: ProcResult(status: -1, out: "", err: error.localizedDescription)); return
                }
                var od = Data(), ed = Data()
                let g = DispatchGroup()
                g.enter(); DispatchQueue.global().async { od = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                g.enter(); DispatchQueue.global().async { ed = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                p.waitUntilExit(); g.wait()
                cont.resume(returning: ProcResult(status: p.terminationStatus,
                                                  out: String(decoding: od, as: UTF8.self),
                                                  err: String(decoding: ed, as: UTF8.self)))
            }
        }
    }

    static func which(_ tool: String) -> String? {
        for d in toolPath.split(separator: ":") {
            let p = "\(d)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}

enum FileHash {
    static func sha256(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

func freeSpace(at url: URL) -> Int64? {
    var u = url
    while !FileManager.default.fileExists(atPath: u.path) { u.deleteLastPathComponent() }
    let v = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return v?.volumeAvailableCapacityForImportantUsage
}

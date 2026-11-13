import Foundation

/// One nxnative build: runs the documented packing command with `--progress json`, stages the app,
/// validates it and only then swaps it into place. The dump, any previously working app and saves are never touched on failure.
final class BuildJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case preflight, running, validating, installing
        case succeeded(URL), failed(String), cancelled
        var isActive: Bool { switch self { case .preflight, .running, .validating, .installing: return true; default: return false } }
    }

    let id = UUID()
    let request: BuildRequest
    unowned let backend: NXNativeBackend

    @Published var state: State = .preflight
    @Published var stageIndex = 0
    @Published var stageCount = 0
    @Published var stageName = "Checking"
    @Published var step = ""
    @Published var fraction: Double?
    @Published var eta: Double?
    @Published var countText = ""
    @Published var messages: [String] = []
    @Published var bundleID: String?
    @Published var iconPath: String?
    @Published var warnings: [String] = []

    private(set) var command: [String] = []
    private(set) var startedAt = Date()
    private(set) var toolchain = ""
    private var process: Process?
    private var cancelRequested = false
    private var stdoutBuffer = Data()
    let titleID: String
    let workDir: URL
    let stagingDir: URL
    let stderrLog: URL
    var stagedApp: URL { stagingDir.appendingPathComponent("\(request.appName).app") }
    var installedApp: URL { Paths.games.appendingPathComponent("\(request.appName).app") }
    var logDir: URL { workDir.appendingPathComponent("logs") }

    init(backend: NXNativeBackend, request: BuildRequest) {
        self.backend = backend
        self.request = request
        titleID = request.report.title_id ?? "unknown"
        workDir = Paths.builds.appendingPathComponent(titleID, isDirectory: true)
        stagingDir = Paths.staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        stderrLog = Paths.logs.appendingPathComponent("build-\(titleID)-\(stamp).log")
    }

    func say(_ s: String) { messages.append(s); if messages.count > 200 { messages.removeFirst(messages.count - 200) } }

    @MainActor
    func start() async {
        startedAt = Date()
        state = .preflight
        // Disk space: nxnative asks for about twice the game's size plus 10 GB.
        let need = request.report.size * 2 + 10 * 1_000_000_000
        Paths.ensure(Paths.builds)
        if let free = freeSpace(at: Paths.builds), free < need {
            fail("Not enough disk space: the build needs about \(need.byteString) free, \(free.byteString) is available. Free some space and try again.")
            return
        }
        guard let py = backend.pythonPath else { fail("No arm64 Python 3.12+ found."); return }
        let st = await backend.status()
        guard st.canBuild else {
            fail("The build toolchain is incomplete: " + st.checks.filter { $0.state == .missing }.map { "\($0.name) (\($0.fix))" }.joined(separator: "; "))
            return
        }
        toolchain = st.checks.map { "\($0.name): \($0.detail)" }.joined(separator: " | ")
        for d in [workDir, stagingDir, Paths.logs] { Paths.ensure(d) }

        var args = [backend.checkout.appendingPathComponent("scripts/build_ipa_from_nsp.py").path, request.input.path,
                    "--platform", "mac-app", "--progress", "json", "--no-seen-shaders",
                    "--work-dir", workDir.path, "-o", stagedApp.path, "--app-name", request.appName]
        if let v = request.package ?? request.report.selected_version.map({ "v\($0)" }) { args += ["--package", v] }
        if let icon = request.report.icon { args += ["--fallback-icon", icon] }
        if let id = request.signingIdentity, !id.isEmpty { args += ["--mac-sign", id] }
        if let t = request.teamID, !t.isEmpty { args += ["--team-id", t] }
        command = [py] + args
        say("$ " + command.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " "))
        AppLog.write("build start: " + command.joined(separator: " "))

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        p.arguments = ["-arm64", py] + args
        p.currentDirectoryURL = backend.checkout
        p.environment = Proc.env()
        let out = Pipe()
        FileManager.default.createFile(atPath: stderrLog.path, contents: nil)
        let errHandle = try? FileHandle(forWritingTo: stderrLog)
        p.standardOutput = out
        p.standardError = errHandle ?? FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        process = p
        state = .running
        do { try p.run() } catch { fail("Could not start the build: \(error.localizedDescription)"); return }
        let status: Int32 = await withCheckedContinuation { c in
            DispatchQueue.global().async { p.waitUntilExit(); c.resume(returning: p.terminationStatus) }
        }
        out.fileHandleForReading.readabilityHandler = nil
        try? errHandle?.close()
        process = nil
        if cancelRequested || status == 143 || status == 130 {
            cleanupStaging()
            state = .cancelled
            say("Build cancelled. The dump, the installed app and saves were left as they were.")
            return
        }
        guard status == 0 else {
            let red = messages.last(where: { $0.hasPrefix("[RED] ") })?.dropFirst(6)
            cleanupStaging()
            fail((red.map(String.init) ?? "The build stopped (exit \(status)).") + "\nLogs: \(logDir.path) and \(stderrLog.path)")
            return
        }
        await validateAndInstall()
    }

    private func consume(_ d: Data) {
        stdoutBuffer.append(d)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[stdoutBuffer.startIndex..<nl]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            guard let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let ev = j["ev"] as? String else {
                if let s = String(data: line, encoding: .utf8), !s.isEmpty { say(s) }
                continue
            }
            switch ev {
            case "stage":
                stageIndex = j["k"] as? Int ?? stageIndex; stageCount = j["n"] as? Int ?? stageCount
                stageName = j["name"] as? String ?? stageName; step = j["step"] as? String ?? ""
                fraction = nil; eta = nil; countText = ""
            case "step":
                step = j["step"] as? String ?? j["name"] as? String ?? step; fraction = nil; countText = ""
            case "progress":
                fraction = j["frac"] as? Double
                eta = j["eta"] as? Double
                let done = j["done"] as? Double ?? 0, total = j["total"] as? Double ?? 0, unit = j["unit"] as? String ?? ""
                countText = unit == "B" ? "\(Int64(done).byteString) of \(Int64(total).byteString)" : "\(Int(done)) of \(Int(total))\(unit.isEmpty ? "" : " \(unit)")"
                if let note = j["note"] as? String, !note.isEmpty { countText += " · \(note)" }
            case "stage_end":
                let name = j["name"] as? String ?? ""
                if let s = j["summary"] as? String, !s.isEmpty { say("✓ \(name): \(s)") }
                if j["warn"] as? Bool == true { warnings.append("\(name) finished without its output (see logs)") }
            case "game":
                bundleID = j["bundle_id"] as? String
                if let icon = j["icon"] as? String, FileManager.default.fileExists(atPath: icon) {
                    // Copy now: the build folder may be cleaned before the build ends.
                    Paths.ensure(Paths.artwork)
                    let dst = Paths.artwork.appendingPathComponent("\(titleID)-build.\(URL(fileURLWithPath: icon).pathExtension)")
                    try? FileManager.default.removeItem(at: dst)
                    try? FileManager.default.copyItem(atPath: icon, toPath: dst.path)
                    iconPath = dst.path
                }
            case "shaders_stale":
                say("Shaders will be rebuilt (\(j["reason"] as? String ?? "changed")): \(j["count"] as? Int ?? 0) libraries")
            case "say":
                if let m = j["msg"] as? String { say(m) }
            default: break
            }
        }
    }

    func cancel() {
        cancelRequested = true
        if let p = process, p.isRunning { p.terminate() }   // SIGTERM: nxnative stops its tools, then exits 143
        else if state == .preflight { state = .cancelled }
    }

    @MainActor
    private func validateAndInstall() async {
        state = .validating
        stageName = "Validating"; step = "Checking the generated app"; fraction = nil
        let app = stagedApp
        let fm = FileManager.default
        let exe = app.appendingPathComponent("Contents/MacOS/nxnative")
        guard fm.isExecutableFile(atPath: exe.path) else { cleanupStaging(); fail("The build reported success but \(exe.path) is missing."); return }
        let lipo = await Proc.run("/usr/bin/lipo", ["-archs", exe.path])
        guard lipo.out.contains("arm64") else { cleanupStaging(); fail("The generated executable is not ARM64 (\(lipo.out.trimmingCharacters(in: .whitespacesAndNewlines)))."); return }
        // Every Mach-O in Contents/MacOS must be arm64.
        if let items = try? fm.contentsOfDirectory(atPath: app.appendingPathComponent("Contents/MacOS").path) {
            for i in items {
                let r = await Proc.run("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/\(i)").path])
                if r.status == 0 && !r.out.contains("arm64") { cleanupStaging(); fail("\(i) is not ARM64."); return }
            }
        }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        if let t = info["DMTitleID"] as? String, t.uppercased() != titleID.uppercased() {
            cleanupStaging(); fail("The app's DMTitleID \(t) does not match the dump's title ID \(titleID)."); return
        }
        let cs = await Proc.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        if cs.status != 0 { warnings.append("codesign --verify reported: \(cs.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        if bundleID == nil { bundleID = info["CFBundleIdentifier"] as? String }

        // Swap into place: keep the previous app until the new one is in.
        state = .installing
        stageName = "Installing"; step = installedApp.path
        Paths.ensure(Paths.games)
        let previous = installedApp.deletingLastPathComponent().appendingPathComponent(".\(request.appName).previous.app")
        try? fm.removeItem(at: previous)
        do {
            if fm.fileExists(atPath: installedApp.path) { try fm.moveItem(at: installedApp, to: previous) }
            do { try fm.moveItem(at: app, to: installedApp) }
            catch {
                if fm.fileExists(atPath: previous.path) { try? fm.moveItem(at: previous, to: installedApp) }
                throw error
            }
            try? fm.removeItem(at: previous)
        } catch {
            fail("Installing failed: \(error.localizedDescription). The previous app (if any) was restored; the built app is in \(stagingDir.path).")
            return
        }
        cleanupStaging()
        AppLog.write("build ok: \(installedApp.path)")
        state = .succeeded(installedApp)
    }

    private func cleanupStaging() { try? FileManager.default.removeItem(at: stagingDir) }

    @MainActor private func fail(_ m: String) {
        AppLog.write("build failed: \(m)")
        say("[RED] " + m)
        state = .failed(m)
    }

    func record(outcome: String) -> BuildRecord {
        BuildRecord(command: command, backendCommit: backend.pin.commit, toolchain: toolchain, startedAt: startedAt, finishedAt: Date(),
                    outcome: outcome, workDir: workDir.path, logDir: logDir.path)
    }
}

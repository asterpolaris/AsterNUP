import Foundation

/// nxnative (https://github.com/seedds/nxnative) as an AsterNUP backend, following its front-end contract (docs/frontends.md).
final class NXNativeBackend: GameBackend {
    let id = "nxnative"
    let displayName = "nxnative"
    let pin: BackendPin
    private(set) var pythonPath: String?

    init() {
        struct Pins: Decodable { var backends: [BackendPin] }
        let url = Paths.resource("pins.json")
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(Pins.self, from: d), let b = p.backends.first(where: { $0.id == "nxnative" }) {
            pin = b
        } else {
            pin = BackendPin(id: "nxnative", name: "nxnative", repository: "https://github.com/seedds/nxnative.git",
                             commit: "034e91a8a64a78fb09173f9d23750c900af52b83", commit_date: "2026-11-12",
                             requires: .init(macos: "26.6", xcode: "27.2", metal_toolchain: "xcodebuild -downloadComponent MetalToolchain",
                                             python: "3.12", brew: ["xcodegen", "zstd", "glslang"], pip: ["lz4", "capstone>=5,<6", "fonttools", "nsz", "zbic"]),
                             build_command: ["python3", "scripts/build_ipa_from_nsp.py", "{input}", "--platform", "mac-app"])
        }
    }

    var checkout: URL { Paths.backendCheckout }

    // MARK: Status

    func findPython() async -> (String, String)? {
        let candidates = [Paths.pythonVenv.appendingPathComponent("bin/python3").path] + Self.basePythons
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            let r = await Proc.run("/usr/bin/arch", ["-arm64", c, "-c", "import sys,platform;print('%d.%d.%d'%sys.version_info[:3], platform.machine())"])
            let parts = r.out.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard r.status == 0, parts.count == 2, parts[1] == "arm64" else { continue }
            let v = parts[0].split(separator: ".").compactMap { Int($0) }
            if v.count >= 2, (v[0], v[1]) >= (3, 12) { pythonPath = c; return (c, parts[0]) }
        }
        return nil
    }

    /// Pythons a venv can be made from; 3.14 first (nxnative's primary version, zstd built in).
    static let basePythons = ["/opt/homebrew/opt/python@3.14/bin/python3.14", "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3.14",
                              "/opt/homebrew/opt/python@3.13/bin/python3.13", "/opt/homebrew/opt/python@3.12/bin/python3.12",
                              "/opt/homebrew/bin/python3", "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/usr/local/bin/python3"]

    /// Creates AsterNUP's backend venv (if needed) and installs nxnative's Python modules into it.
    func preparePythonEnvironment(log: @escaping (String) -> Void) async throws {
        let venvPy = Paths.pythonVenv.appendingPathComponent("bin/python3").path
        if !FileManager.default.isExecutableFile(atPath: venvPy) {
            var base: String?
            for c in Self.basePythons where FileManager.default.isExecutableFile(atPath: c) {
                let r = await Proc.run("/usr/bin/arch", ["-arm64", c, "-c", "import sys,platform;assert sys.version_info>=(3,12) and platform.machine()=='arm64'"])
                if r.status == 0 { base = c; break }
            }
            guard let base else { throw BackendError("No arm64 Python 3.12+ found. Install one with: brew install python@3.14") }
            log("Creating the Python environment from \(base)…")
            Paths.ensure(Paths.pythonVenv.deletingLastPathComponent())
            let r = await Proc.run("/usr/bin/arch", ["-arm64", base, "-m", "venv", Paths.pythonVenv.path])
            if r.status != 0 { throw BackendError("python -m venv failed: \(r.err)") }
        }
        log("Installing lz4, capstone, fonttools, nsz, zbic…")
        let ver = await Proc.run("/usr/bin/arch", ["-arm64", venvPy, "-c", "import sys;print(sys.version_info>=(3,14))"])
        var pkgs = pin.requires.pip
        if !ver.out.contains("True") { pkgs.append("backports.zstd") }
        let r = await Proc.run("/usr/bin/arch", ["-arm64", venvPy, "-m", "pip", "install", "--quiet", "--disable-pip-version-check"] + pkgs)
        if r.status != 0 { throw BackendError("pip install failed:\n" + String(r.err.suffix(800))) }
        pythonPath = nil
        log("Python environment ready at \(Paths.pythonVenv.path)")
    }

    func status() async -> BackendStatus {
        var checks: [ToolCheck] = []
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osOK = (os.majorVersion, os.minorVersion) >= (26, 6)
        checks.append(ToolCheck(name: "macOS \(pin.requires.macos)+", state: osOK ? .ok : .missing,
                                detail: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", fix: "Update macOS in System Settings."))
        // Checkout
        var head: String?
        if FileManager.default.fileExists(atPath: checkout.appendingPathComponent("scripts/build_ipa_from_nsp.py").path) {
            let r = await Proc.run("/usr/bin/git", ["-C", checkout.path, "rev-parse", "HEAD"])
            head = r.status == 0 ? r.out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        let pinned = head == pin.commit
        checks.append(ToolCheck(name: "nxnative @ \(pin.commit.prefix(10))",
                                state: head == nil ? .missing : (pinned ? .ok : .warning),
                                detail: head == nil ? "No checkout at \(checkout.path)" : (pinned ? "Pinned revision checked out" : "Checkout is at \(head!.prefix(10)), pin is \(pin.commit.prefix(10))"),
                                fix: "Choose Set up backend (fetches the pinned revision)."))
        // Python
        var pyOK = false, zstdOK = false
        if let (py, v) = await findPython() {
            pyOK = true
            checks.append(ToolCheck(name: "Python \(pin.requires.python)+ (arm64)", state: .ok, detail: "\(v) at \(py)"))
            let mods = await Proc.run("/usr/bin/arch", ["-arm64", py, "-c", """
                import importlib.util as u
                need={'lz4':'lz4','capstone':'capstone','fontTools':'fonttools','nsz':'nsz'}
                miss=[p for m,p in need.items() if u.find_spec(m) is None]
                z = u.find_spec('compression.zstd') if __import__('sys').version_info>=(3,14) else u.find_spec('backports.zstd')
                print('zstd' if z else 'nozstd'); print(' '.join(miss))
                """])
            let lines = mods.out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            zstdOK = lines.first == "zstd"
            let miss = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : "unknown"
            checks.append(ToolCheck(name: "Python modules", state: miss.isEmpty && zstdOK ? .ok : .missing,
                                    detail: miss.isEmpty ? (zstdOK ? "lz4, capstone, fontTools, nsz, zstd" : "zstd module missing") : "Missing: \(miss)",
                                    fix: "Choose Set up Python environment below (or run scripts/install.sh --no-open): installs into \(Paths.pythonVenv.path)"))
        } else {
            checks.append(ToolCheck(name: "Python \(pin.requires.python)+ (arm64)", state: .missing, detail: "No arm64 Python 3.12+ found", fix: "brew install python@3.14"))
        }
        // Xcode + Metal
        let sel = await Proc.run("/usr/bin/xcode-select", ["-p"])
        let devDir = sel.out.trimmingCharacters(in: .whitespacesAndNewlines)
        let xv = await Proc.run("/usr/bin/xcrun", ["xcodebuild", "-version"])
        let xcodeLine = xv.out.split(separator: "\n").first.map(String.init) ?? ""
        let hasXcode = xv.status == 0 && xcodeLine.hasPrefix("Xcode")
        let rightXcode = xcodeLine == "Xcode \(pin.requires.xcode)"
        checks.append(ToolCheck(name: "Xcode \(pin.requires.xcode)", state: hasXcode ? (rightXcode ? .ok : .warning) : .missing,
                                detail: hasXcode ? "\(xcodeLine) at \(devDir)" : "Active developer directory is \(devDir.isEmpty ? "unset" : devDir) (Command Line Tools only)",
                                fix: "Install Xcode \(pin.requires.xcode) from developer.apple.com/download, then: sudo xcode-select -s /Applications/Xcode.app"))
        let metal = await Proc.run("/usr/bin/xcrun", ["-f", "metal"])
        checks.append(ToolCheck(name: "Metal toolchain", state: metal.status == 0 ? .ok : .missing,
                                detail: metal.status == 0 ? metal.out.trimmingCharacters(in: .whitespacesAndNewlines) : "metal compiler not found",
                                fix: pin.requires.metal_toolchain))
        // Homebrew tools
        let tools = [("xcodegen", "xcodegen"), ("zstd", "zstd"), ("glslang", "glslangValidator")]
        let missing = tools.filter { Proc.which($0.1) == nil }.map(\.0)
        checks.append(ToolCheck(name: "Homebrew tools", state: missing.isEmpty ? .ok : .missing,
                                detail: missing.isEmpty ? "xcodegen, zstd, glslang" : "Missing: \(missing.joined(separator: ", "))",
                                fix: "brew install " + missing.joined(separator: " ")))
        let canInspect = head != nil && pyOK && zstdOK
        var canBuild = canInspect && osOK && checks.allSatisfy { $0.state != .missing }
        if ProcessInfo.processInfo.environment["ASTERNUP_TEST_FAKE_TOOLCHAIN"] == "1" {
            // Test harness only (Tests/run_ui_tests.sh): lets a fake backend exercise staging, validation and install.
            canBuild = canInspect
            checks.append(ToolCheck(name: "TEST MODE", state: .warning, detail: "ASTERNUP_TEST_FAKE_TOOLCHAIN=1: toolchain checks bypassed"))
        }
        return BackendStatus(checkoutPath: checkout.path, checkoutCommit: head, pinnedCommit: pin.commit, checks: checks, canInspect: canInspect, canBuild: canBuild)
    }

    func preparePinnedCheckout(log: @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
            Paths.ensure(checkout.deletingLastPathComponent())
            log("Cloning \(pin.repository)…")
            let r = await Proc.run("/usr/bin/git", ["clone", "--quiet", pin.repository, checkout.path])
            if r.status != 0 { throw BackendError("git clone failed: \(r.err)") }
        } else {
            let dirty = await Proc.run("/usr/bin/git", ["-C", checkout.path, "status", "--porcelain", "--untracked-files=no"])
            if !dirty.out.isEmpty { throw BackendError("The backend checkout at \(checkout.path) has local changes; AsterNUP will not overwrite them. Commit or stash them, or set another BackendPath.") }
            log("Fetching…")
            _ = await Proc.run("/usr/bin/git", ["-C", checkout.path, "fetch", "--quiet", "origin"])
        }
        log("Checking out \(pin.commit.prefix(10))…")
        let co = await Proc.run("/usr/bin/git", ["-C", checkout.path, "checkout", "--quiet", "--detach", pin.commit])
        if co.status != 0 { throw BackendError("git checkout \(pin.commit) failed: \(co.err)") }
        log("Backend pinned at \(pin.commit.prefix(10)).")
    }

    // MARK: Profiles

    func supportedProfiles() -> [GameProfile] {
        let games = checkout.appendingPathComponent("dm/games")
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: games, includingPropertiesForKeys: nil) else { return [] }
        var out: [GameProfile] = []
        for d in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try? String(contentsOf: d.appendingPathComponent("game.tsv"), encoding: .utf8) else { continue }
            var name = "", tid = d.lastPathComponent, pkg = "", builds: [String] = []
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let c = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                guard c.count >= 2 else { continue }
                switch c[0] {
                case "name": name = c[1]
                case "title_id": tid = c[1]
                case "package": pkg = c[1]
                case "build": builds.append(c.count > 2 ? "\(c[1]) (\(c[2]))" : c[1])
                default: break
                }
            }
            let readme = d.appendingPathComponent("README.md")
            out.append(GameProfile(titleID: tid.uppercased(), name: name.isEmpty ? tid : name, package: pkg, builds: builds,
                                   readme: FileManager.default.fileExists(atPath: readme.path) ? readme : nil))
        }
        return out
    }

    // MARK: Inspect

    func inspect(_ input: URL, verifyAllHashes: Bool, package: String?, progress: @escaping (String, Double?) -> Void) async throws -> InspectionReport {
        if pythonPath == nil { _ = await findPython() }
        guard let py = pythonPath else { throw BackendError("No arm64 Python 3.12+ was found. Install one with: brew install python@3.14") }
        guard FileManager.default.fileExists(atPath: checkout.appendingPathComponent("scripts/pack_nup.py").path) else {
            throw BackendError("The nxnative backend is not set up yet. Open Backend from the dock and choose Set up backend.")
        }
        Paths.ensure(Paths.inspections)
        var args = ["-arm64", py, "-E", "-P", Paths.resource("asternup_inspect.py").path, "--backend", checkout.path,
                    "--icon-out", Paths.inspections.path, input.path]
        if verifyAllHashes { args.append("--verify") }
        if let package { args += ["--package", package] }
        let finalArgs = args
        return try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
            p.arguments = finalArgs
            p.environment = Proc.env()
            let o = Pipe(), e = Pipe()
            p.standardOutput = o; p.standardError = e
            let errBox = Box("")
            let lock = NSLock()
            e.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                let s = String(decoding: d, as: UTF8.self)
                lock.lock(); errBox.value += s; lock.unlock()
                for line in s.split(separator: "\n") {
                    if let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let m = j["msg"] as? String {
                        let done = (j["done"] as? Double) ?? 0, total = (j["total"] as? Double) ?? 0
                        DispatchQueue.main.async { progress(m, total > 0 ? done / total : nil) }
                    }
                }
            }
            DispatchQueue.global().async {
                do { try p.run() } catch { cont.resume(throwing: error); return }
                let data = o.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                e.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus != 0 {
                    lock.lock(); let t = errBox.value; lock.unlock()
                    AppLog.write("inspect failed (\(p.terminationStatus)): \(t)")
                    cont.resume(throwing: BackendError("The inspector stopped unexpectedly (exit \(p.terminationStatus)). Details: \(AppLog.url.path)\n" + String(t.suffix(600))))
                    return
                }
                do { cont.resume(returning: try JSONDecoder().decode(InspectionReport.self, from: data)) }
                catch { cont.resume(throwing: BackendError("Could not read the inspector's report: \(error)")) }
            }
        }
    }

    func makeBuildJob(for request: BuildRequest) -> BuildJob { BuildJob(backend: self, request: request) }

    // MARK: Settings, saves, logs (docs/frontends.md)

    func settings(forApp app: URL) -> LauncherSettings? {
        let u = app.appendingPathComponent("Contents/Resources/dm/launcher.json")
        guard let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(LauncherSettings.self, from: d)
    }

    func savedChoice(_ env: String, bundleID: String) -> String? {
        CFPreferencesAppSynchronize(bundleID as CFString)
        return CFPreferencesCopyAppValue("launcher.\(env)" as CFString, bundleID as CFString) as? String
    }

    /// Only choices that differ from the tested default are kept: pass nil to remove the key.
    func setSavedChoice(_ env: String, value: String?, bundleID: String) {
        CFPreferencesSetAppValue("launcher.\(env)" as CFString, value as CFString?, bundleID as CFString)
        CFPreferencesAppSynchronize(bundleID as CFString)
    }

    func saveFolder(titleID: String) -> URL {
        Paths.home.appendingPathComponent("Library/Application Support/nxnative/\(titleID.uppercased())/save", isDirectory: true)
    }

    func logFile(titleID: String) -> URL {
        Paths.home.appendingPathComponent("Library/Logs/nxnative/\(titleID.uppercased()).log")
    }

    func launchEnvironment(for entry: GameEntry) -> [String: String] {
        // AsterNUP draws the settings itself; the game's saved choices still apply (frontends.md, "Starting a game").
        ["DM_LAUNCHER": "0"]
    }
}

struct BackendError: LocalizedError {
    var message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Banner: Identifiable, Equatable {
    enum Style { case info, success, error }
    let id = UUID()
    var style: Style
    var text: String
    var detail: String = ""
}

struct OverlayItem: Identifiable {
    enum Kind { case list(ListPanel), sectioned(SectionedPanel), report(ReportPanel), build(BuildPanel), busy(BusyPanel) }
    let id = UUID()
    let kind: Kind
    var surface: NavSurface {
        switch kind {
        case .list(let p): return p
        case .sectioned(let p): return p
        case .report(let p): return p
        case .build(let p): return p
        case .busy(let p): return p
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Zone { case row, dock }
    struct DockItem: Identifiable { let id: String; let label: String; let systemImage: String }

    let library = LibraryStore()
    let sessions = SessionManager()
    let input = InputRouter()
    let backend = NXNativeBackend()

    @Published var overlays: [OverlayItem] = []
    @Published var zone: Zone = .row
    @Published var rowIndex = 0
    @Published var dockIndex = 0
    @Published var banner: Banner?
    @Published var backendStatus: BackendStatus?
    @Published var activeBuild: BuildJob?
    @Published var settings = HomeSettings() { didSet { saveSettings(); applySettings() } }
    @Published var clock = Date()
    weak var window: NSWindow?

    let dock: [DockItem] = [
        DockItem(id: "import", label: "Import a dump", systemImage: "square.and.arrow.down"),
        DockItem(id: "app", label: "Choose an existing game app", systemImage: "app.badge"),
        DockItem(id: "controllers", label: "Controllers", systemImage: "gamecontroller"),
        DockItem(id: "backend", label: "Backend & toolchain", systemImage: "wrench.and.screwdriver"),
        DockItem(id: "settings", label: "Home settings", systemImage: "gearshape"),
        DockItem(id: "exit", label: "Exit AsterNUP", systemImage: "power"),
    ]

    private var bannerTask: Task<Void, Never>?
    private var cancellables: [Any] = []

    init() {
        loadSettings()
        sessions.adopt(library.entries)
        input.onAction = { [weak self] a in self?.handle(a) }
        input.onHome = { [weak self] in self?.homePressed() }
        sessions.onGameExited = { [weak self] id, _ in self?.gameExited(id) }
        input.settings = settings
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.clock = Date() } }
        cleanupStaleStaging()
        Task { await refreshBackendStatus() }
    }

    // MARK: Items on the row

    var entries: [GameEntry] { library.entries }
    var rowCount: Int { entries.count + 1 }   // + "Add a game"
    var focusedEntry: GameEntry? { zone == .row && entries.indices.contains(rowIndex) ? entries[rowIndex] : nil }

    func entryIndex(_ id: UUID) -> Int? { entries.firstIndex { $0.id == id } }

    // MARK: Input routing

    func handle(_ a: NavAction) {
        if a == .home { homePressed(); return }
        if let top = overlays.last {
            if !top.surface.handle(a), a == .back { popOverlay() }
            return
        }
        handleHome(a)
    }

    private func handleHome(_ a: NavAction) {
        switch (zone, a) {
        case (.row, .left): rowIndex = max(0, rowIndex - 1)
        case (.row, .right): rowIndex = min(rowCount - 1, rowIndex + 1)
        case (.row, .down), (.row, .shoulderR): zone = .dock
        case (.dock, .up), (.dock, .shoulderL), (.dock, .back): zone = .row
        case (.dock, .left): dockIndex = max(0, dockIndex - 1)
        case (.dock, .right): dockIndex = min(dock.count - 1, dockIndex + 1)
        case (.row, .confirm):
            if let e = focusedEntry { play(e) } else { showAddGame() }
        case (.dock, .confirm): activateDock(dock[dockIndex].id)
        case (.row, .plus), (.row, .y): if let e = focusedEntry { showOptions(e.id) }
        case (.row, .x): if let e = focusedEntry, sessions.isRunning(e.id) { confirmClose(e) }
        case (.row, .minus): if let e = focusedEntry { showOptions(e.id, section: 3) }
        default: break
        }
    }

    var hints: [Hint] {
        if let top = overlays.last { return top.surface.hints }
        if zone == .dock { return [Hint(button: "A", label: "OK"), Hint(button: "B", label: "Back")] }
        guard let e = focusedEntry else { return [Hint(button: "A", label: "Add a game")] }
        if sessions.isRunning(e.id) {
            return [Hint(button: "A", label: "Resume"), Hint(button: "X", label: "Close software"), Hint(button: "+", label: "Options")]
        }
        return [Hint(button: "A", label: e.isInstalled ? "Start" : "Not installed"), Hint(button: "+", label: "Options")]
    }

    func pushOverlay(_ k: OverlayItem.Kind) { overlays.append(OverlayItem(kind: k)) }
    func popOverlay() { if !overlays.isEmpty { overlays.removeLast() } }
    func popAll() { overlays.removeAll() }

    // MARK: Banners

    func show(_ style: Banner.Style, _ text: String, detail: String = "", seconds: Double = 6) {
        banner = Banner(style: style, text: text, detail: detail)
        bannerTask?.cancel()
        let s = style == .error ? max(seconds, 12) : seconds
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(s * 1e9))
            if !Task.isCancelled { self?.banner = nil }
        }
    }

    // MARK: HOME, play, resume, close

    func homePressed() {
        if let g = sessions.frontmostGame {
            bringForward()
            if let i = entryIndex(g) { zone = .row; rowIndex = i }
            return
        }
        if NSApp.isActive, overlays.isEmpty, let g = sessions.lastActiveGame ?? sessions.running.keys.first, let e = library.entry(g) {
            play(e)   // HOME on Home goes back to the game
        } else if !NSApp.isActive {
            bringForward()
        }
    }

    func bringForward() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // macOS's cooperative activation can refuse to take focus from the app in front. If a game is still in front,
        // hide it (it keeps running; Resume unhides and reactivates the same instance) and activate again.
        Task { @MainActor in
            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if NSApp.isActive { return }
                if let g = sessions.frontmostGame, let app = sessions.running[g] { app.hide() }
                NSApp.activate(ignoringOtherApps: true)
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func play(_ e: GameEntry) {
        guard sessions.isRunning(e.id) || e.isInstalled else {
            show(.error, "\(e.title) is not installed", detail: e.sourcePath != nil ? "Open Options → Manage software → Rebuild." : "Choose the app again.")
            return
        }
        let resuming = sessions.isRunning(e.id)
        if !resuming, e.kind == .managed, let other = runningManagedGame(except: e.id) {
            confirmSecondGame(start: e, running: other); return
        }
        if !resuming, e.kind == .managed, settings.checkBeforePlaying {
            let pids = Set(sessions.running.values.map(\.processIdentifier))
            var r = PlayReadiness.check(excluding: pids)
            AppLog.write("play check: others \(PlayReadiness.gb(r.othersBytes)) of \(PlayReadiness.gb(r.physical)), swap \(PlayReadiness.gb(r.swapUsedBytes)), low power \(r.lowPowerMode), thermal \(r.thermal.rawValue), heavy: \(r.heavyApps.map { "\($0.name) \(PlayReadiness.gb($0.bytes))" }.joined(separator: ", "))")
            // UI tests: measure for real, but decide the outcome so the result doesn't depend on what else is open.
            switch ProcessInfo.processInfo.environment["ASTERNUP_TEST_PLAY_CHECK"] {
            case "clear"?: r.heavyApps = []; r.lowPowerMode = false; r.thermal = .nominal
            case "lowpower"?: r.heavyApps = []; r.lowPowerMode = true; r.thermal = .nominal
            default: break
            }
            if r.hasIssues { showPlayCheck(e, r); return }
        }
        launch(e, resuming: resuming)
    }

    /// Shown before an nxnative game starts when something on the Mac would cost it frames.
    private func showPlayCheck(_ e: GameEntry, _ r: PlayReadiness) {
        var msg: [String] = []
        if r.memoryTight {
            msg.append("Other apps are holding \(PlayReadiness.gb(r.othersBytes)) of this Mac's \(PlayReadiness.gb(r.physical)) of memory. \(e.title) needs most of it for itself (Ocarina of Time keeps about 11 GB), so macOS would swap and the game would stutter. Quitting apps you don't need gives it the room.")
            if r.swapUsedBytes > 1 << 30 { msg.append("macOS is already using \(PlayReadiness.gb(r.swapUsedBytes)) of swap.") }
        }
        if r.lowPowerMode { msg.append("Low Power Mode is on: the GPU runs at lower clocks and the game will drop frames. Turn it off in System Settings › Battery.") }
        if r.hot { msg.append("This Mac is running hot (thermal state: \(r.thermal == .critical ? "critical" : "serious")) and is slowing itself down. Let it cool, or improve airflow.") }

        var rows: [ListPanel.Row] = []
        if r.memoryTight {
            let apps = r.heavyApps
            rows.append(.init(label: "Quit \(apps.count == 1 ? apps[0].name : "these \(apps.count) apps") and play",
                              detail: "Each app is asked to quit normally, so it can still ask you to save.", systemImage: "bolt.fill",
                              action: { [weak self] in self?.popOverlay(); self?.quitApps(apps, thenLaunch: e) }))
            for a in apps {
                rows.append(.init(label: "Quit \(a.name)", detail: PlayReadiness.gb(a.bytes), image: a.app.icon, action: { [weak self] in
                    guard let self, case .list(let p)? = self.overlays.last?.kind, let i = p.rows.firstIndex(where: { $0.label == "Quit \(a.name)" }) else { return }
                    a.app.terminate()
                    p.rows[i].label = "Asked \(a.name) to quit"; p.rows[i].enabled = false
                    p.move(1)
                }))
            }
        }
        if r.lowPowerMode {
            rows.append(.init(label: "Open Battery settings", systemImage: "battery.100", action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
            }))
        }
        rows.append(.init(label: "Play now", systemImage: "play.fill", action: { [weak self] in self?.popOverlay(); self?.launch(e, resuming: false) }))
        rows.append(.init(label: "Cancel", action: { [weak self] in self?.popOverlay() }))
        pushOverlay(.list(ListPanel(title: "Make \(e.title) run smoother", message: msg.joined(separator: "\n\n"), rows: rows)))
    }

    /// Ask each app to quit (as ⌘Q would), wait for them, then start the game. Apps that stay open (a save prompt) are named.
    private func quitApps(_ apps: [PlayReadiness.HeavyApp], thenLaunch e: GameEntry) {
        for a in apps { a.app.terminate() }
        show(.info, "Quitting \(apps.count) app\(apps.count == 1 ? "" : "s")…", seconds: 10)
        Task {
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline, apps.contains(where: { !$0.app.isTerminated }) {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            let left = apps.filter { !$0.app.isTerminated }.map(\.name)
            AppLog.write("play check: quit \(apps.count - left.count) of \(apps.count) apps\(left.isEmpty ? "" : "; still open: " + left.joined(separator: ", "))")
            if left.isEmpty { show(.success, "Memory freed for \(e.title)") }
            else { show(.info, "Still open: \(left.joined(separator: ", "))", detail: "They may be asking to save. Starting \(e.title) anyway.") }
            launch(e, resuming: false)
        }
    }

    /// Another nxnative game that is running now, if any.
    func runningManagedGame(except id: UUID) -> GameEntry? {
        sessions.running.keys.filter { $0 != id }.compactMap { library.entry($0) }.first { $0.kind == .managed }
    }

    /// nxnative games each take most of the Mac's memory (Ocarina of Time: about 11 GB resident, 9.4 GB wired on a 16 GB Mac,
    /// per its game note), and the note warns that a game running beside it can push the Mac over. Ask before starting a second one.
    private func confirmSecondGame(start e: GameEntry, running other: GameEntry) {
        let gb = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        let p = ListPanel(title: "Close \(other.title) first?",
                          message: "\(other.title) is still running. nxnative games each use most of this Mac's \(gb) GB of memory (Ocarina of Time alone keeps about 11 GB); running two at once can make macOS swap heavily, stutter or crash. Unsaved progress in \(other.title) will be lost if you close it.",
                          rows: [
                            .init(label: "Cancel", action: { [weak self] in self?.popOverlay() }),
                            .init(label: "Close it and start", destructive: true, action: { [weak self] in
                                guard let self else { return }
                                self.popOverlay()
                                Task {
                                    if await self.sessions.requestQuit(other.id) { self.launch(e, resuming: false) }
                                    else { self.show(.error, "\(other.title) did not quit", detail: "Close it with X on its tile (Force quit is offered there), then start \(e.title).") }
                                }
                            }),
                            .init(label: "Start anyway", action: { [weak self] in self?.popOverlay(); self?.launch(e, resuming: false) }),
                          ], defaultFocus: 0, layout: .buttons)
        pushOverlay(.list(p))
    }

    private func launch(_ e: GameEntry, resuming: Bool) {
        var env: [String: String] = [:], args: [String] = []
        if e.kind == .managed {
            env = backend.launchEnvironment(for: e)
        }
        env.merge(e.launchEnvironment) { _, new in new }
        args = e.launchArguments
        Task {
            do {
                try await sessions.launchOrResume(e, environment: env, arguments: args)
                if !resuming {
                    var u = e; u.lastPlayed = Date(); library.upsert(u)
                }
            } catch {
                show(.error, "Could not start \(e.title)", detail: error.localizedDescription)
            }
        }
    }

    func confirmClose(_ e: GameEntry) {
        let p = ListPanel(title: "Close \(e.title)?", message: "Unsaved progress will be lost.", rows: [
            .init(label: "Cancel", action: { [weak self] in self?.popOverlay() }),
            .init(label: "Close", destructive: true, action: { [weak self] in
                self?.popOverlay(); self?.close(e)
            }),
        ], defaultFocus: 0, layout: .buttons)
        pushOverlay(.list(p))
    }

    private func close(_ e: GameEntry) {
        show(.info, "Closing \(e.title)…", seconds: 15)
        Task {
            if await sessions.requestQuit(e.id) {
                show(.success, "\(e.title) closed")
            } else {
                let p = ListPanel(title: "\(e.title) is not responding", message: "Force quitting loses anything not saved.", rows: [
                    .init(label: "Keep waiting", action: { [weak self] in self?.popOverlay() }),
                    .init(label: "Force quit", destructive: true, action: { [weak self] in self?.popOverlay(); self?.sessions.forceQuit(e.id) }),
                ], defaultFocus: 0, layout: .buttons)
                pushOverlay(.list(p))
            }
        }
    }

    private func gameExited(_ id: UUID) {
        if let i = entryIndex(id) { zone = .row; rowIndex = i }
        objectWillChange.send()
        bringForward()
        // Exit codes are not visible for apps started through Launch Services: read the end of the game's log instead.
        if let e = library.entry(id), e.kind == .managed, let tid = e.titleID {
            let log = backend.logFile(titleID: tid)
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)   // let the game finish writing its log
                if let why = Self.abnormalExit(log: log) {
                    show(.error, "\(e.title) stopped: \(why.0)", detail: "\(why.1)\nLog: \(log.path)", seconds: 30)
                    AppLog.write("game exit (\(tid)): \(why.0) | \(why.1)")
                }
            }
        }
    }

    /// (summary, detail) when the end of an nxnative log shows the game did not quit normally; nil for a normal quit.
    nonisolated static func abnormalExit(log: URL) -> (String, String)? {
        // nxnative starts a fresh log each run (the previous one becomes <title ID>.prev.log); ignore one not written recently.
        guard let m = (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(m) < 300, let h = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        let tail = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
        let lines = tail.split(separator: "\n").map(String.init)
        let report = "To report it: python3 scripts/bug_report.py in the backend checkout (nxnative issues #1326, #1605, #2011 track GPU hangs in this game)."
        if let l = lines.last(where: { $0.contains("GPU access revoked") }) {
            return ("macOS revoked its GPU access after a GPU hang", l.trimmingCharacters(in: .whitespaces) + "\n" + report)
        }
        if lines.contains(where: { $0.contains("Insufficient Memory") }) || lines.contains(where: { $0.contains("[RED]") && $0.lowercased().contains("out of memory") }) {
            return ("it ran out of GPU memory", "Close other apps (and other games) and start it again; keep Dynamic resolution off.")
        }
        if let l = lines.last(where: { $0.contains("nn::diag abort") || $0.contains("FATAL") }) {
            return ("the game aborted", l.trimmingCharacters(in: .whitespaces) + "\n" + report)
        }
        return nil
    }

    // MARK: Dock

    func activateDock(_ id: String) {
        switch id {
        case "import": showDumpPicker()
        case "app": showAppPicker()
        case "controllers": showControllers()
        case "backend": showBackend()
        case "settings": showHomeSettings()
        case "exit": confirmExit()
        default: break
        }
    }

    func showAddGame() {
        let p = ListPanel(title: "Add a game", rows: [
            .init(label: "Import a dump", detail: "A .nup file or an ExeFS/RomFS folder. AsterNUP reads it in place and builds a Mac app.", systemImage: "square.and.arrow.down",
                  action: { [weak self] in self?.popOverlay(); self?.showDumpPicker() }),
            .init(label: "Choose an existing game app", detail: "Register a macOS game app you already have.", systemImage: "app.badge",
                  action: { [weak self] in self?.popOverlay(); self?.showAppPicker() }),
            .init(label: "Cancel", action: { [weak self] in self?.popOverlay() }),
        ])
        pushOverlay(.list(p))
    }

    func confirmExit() {
        let running = sessions.running.keys.compactMap { library.entry($0) }
        var rows: [ListPanel.Row] = [.init(label: "Cancel", action: { [weak self] in self?.popOverlay() })]
        if !running.isEmpty {
            rows.append(.init(label: "Close games and exit", destructive: true, action: { [weak self] in
                guard let self else { return }
                self.popOverlay()
                Task {
                    for e in running { _ = await self.sessions.requestQuit(e.id) }
                    NSApp.terminate(nil)
                }
            }))
            rows.append(.init(label: "Exit, keep games running", action: { NSApp.terminate(nil) }))
        } else {
            rows.append(.init(label: "Exit", action: { NSApp.terminate(nil) }))
        }
        let msg = running.isEmpty ? "" : "Running: " + running.map(\.title).joined(separator: ", ")
        pushOverlay(.list(ListPanel(title: "Exit AsterNUP?", message: msg, rows: rows, defaultFocus: 0, layout: .buttons)))
    }

    // MARK: Import a dump

    /// Controller-friendly list of .nup files and dump folders found in the usual places, plus Finder.
    func showDumpPicker() {
        var rows: [ListPanel.Row] = [
            .init(label: "Browse with Finder…", detail: "Select a .nup file or an ExeFS/RomFS folder", systemImage: "folder",
                  action: { [weak self] in self?.popOverlay(); self?.browseForDump() }),
        ]
        for url in Self.findDumps() {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0).byteString } ?? "folder"
            rows.append(.init(label: url.lastPathComponent, detail: "\(url.deletingLastPathComponent().path) · \(size)", systemImage: url.pathExtension == "nup" ? "shippingbox" : "folder.badge.gearshape",
                              action: { [weak self] in self?.popOverlay(); self?.importDump(url) }))
        }
        if rows.count == 1 { rows[0].detail += ". No dumps were found in Downloads, Desktop, Documents, ~/Games or external drives; you can also drop one onto this window." }
        rows.append(.init(label: "Cancel", action: { [weak self] in self?.popOverlay() }))
        pushOverlay(.list(ListPanel(title: "Import a dump", message: "AsterNUP never modifies, moves or renames your dump.", rows: rows)))
    }

    nonisolated static func findDumps() -> [URL] {
        let fm = FileManager.default
        var roots = ["Downloads", "Desktop", "Documents", "Games"].map { Paths.home.appendingPathComponent($0) }
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) {
            roots += vols.filter { $0.path != "/Volumes/Macintosh HD" }
        }
        var out: [URL] = []
        for r in roots {
            guard let en = fm.enumerator(at: r, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in en {
                if en.level > 3 { en.skipDescendants(); continue }
                if u.pathExtension.lowercased() == "nup" { out.append(u) }
                else if (u.lastPathComponent == "exefs" || u.lastPathComponent == "ExeFS"), fm.fileExists(atPath: u.appendingPathComponent("main.npdm").path) {
                    let parent = u.deletingLastPathComponent()
                    out.append(parent.lastPathComponent == "base" ? parent.deletingLastPathComponent() : parent)
                    en.skipDescendants()
                }
                if out.count > 40 { break }
            }
        }
        return Array(Set(out)).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func browseForDump() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = false
        p.message = "Select a .nup file, or a folder with exefs/ and romfs/ (or base/ and updates/)"
        p.prompt = "Inspect"
        if p.runModal() == .OK, let u = p.url { importDump(u) }
        bringForward()
    }

    func handleDrop(_ urls: [URL]) {
        guard let u = urls.first else { return }
        if u.pathExtension == "app" { registerApp(u) } else { importDump(u) }
    }

    func importDump(_ url: URL, verify: Bool = false, package: String? = nil) {
        let busy = BusyPanel(title: verify ? "Verifying every file in \(url.lastPathComponent)…" : "Inspecting \(url.lastPathComponent)…")
        busy.detail = "Reading in place. Nothing is written to your dump."
        pushOverlay(.busy(busy))
        Task {
            if backendStatus?.canInspect != true { await refreshBackendStatus() }
            do {
                let r = try await backend.inspect(url, verifyAllHashes: verify, package: package) { msg, frac in
                    busy.detail = msg; busy.fraction = frac
                }
                if overlays.last?.surface === busy { popOverlay() }
                showReport(r, input: url)
            } catch {
                if overlays.last?.surface === busy { popOverlay() }
                let msg = error.localizedDescription
                let p = ListPanel(title: "Can't inspect \(url.lastPathComponent)", message: msg, rows: [
                    .init(label: "Set up backend", action: { [weak self] in self?.popOverlay(); self?.showBackend() }),
                    .init(label: "Close", action: { [weak self] in self?.popOverlay() }),
                ], defaultFocus: 0, layout: .buttons)
                pushOverlay(.list(p))
            }
        }
    }

    func showReport(_ r: InspectionReport, input: URL) {
        let canBuild = backendStatus?.canBuild == true
        let existing = r.title_id.flatMap { library.managedEntry(titleID: $0) }
        var buttons: [ListPanel.Row] = []
        if r.playable {
            if canBuild {
                buttons.append(.init(label: existing == nil ? "Build & install" : "Rebuild & replace", action: { [weak self] in self?.confirmBuild(r, input: input) }))
            } else {
                buttons.append(.init(label: "Set up toolchain to build", action: { [weak self] in self?.showBackend() }))
            }
        }
        if r.kind == "nup" && r.integrity != "all-files-verified" {
            buttons.append(.init(label: "Verify all hashes", action: { [weak self] in self?.popOverlay(); self?.importDump(input, verify: true) }))
        }
        let versions = r.packages.filter { $0.kind == "base" || $0.kind == "update" }.map(\.version)
        if versions.count > 1 {
            buttons.append(.init(label: "Other version", action: { [weak self] in
                guard let self else { return }
                let rows = versions.map { v in ListPanel.Row(label: "v\(v)", detail: v == r.selected_version ? "selected" : "", action: { [weak self] in
                    self?.popOverlay(); self?.popOverlay(); self?.importDump(input, package: "v\(v)") }) }
                self.pushOverlay(.list(ListPanel(title: "Package version", rows: rows)))
            }))
        }
        buttons.append(.init(label: "Close", action: { [weak self] in self?.popOverlay() }))
        pushOverlay(.report(ReportPanel(report: r, input: input, buttons: buttons)))
    }

    func confirmBuild(_ r: InspectionReport, input: URL) {
        let name = Self.appName(for: r)
        let need = r.size * 2 + 10_000_000_000
        let free = freeSpace(at: Paths.builds) ?? 0
        let msg = """
        \(name) · \(r.title_id ?? "") · package v\(r.selected_version ?? 0)
        Backend nxnative @ \(backend.pin.commit.prefix(10)), full shader set. The first build takes 30–60 minutes.
        Disk: about \(need.byteString) needed, \(free.byteString) free.
        Output: \(Paths.games.appendingPathComponent("\(name).app").path)
        """
        let p = ListPanel(title: "Build \(name)?", message: msg, rows: [
            .init(label: "Cancel", action: { [weak self] in self?.popOverlay() }),
            .init(label: "Build", enabled: free >= need, action: { [weak self] in
                self?.popOverlay(); self?.popOverlay(); self?.startBuild(r, input: input, name: name)
            }),
        ], defaultFocus: 1, layout: .buttons)
        pushOverlay(.list(p))
    }

    static func appName(for r: InspectionReport) -> String {
        let t = r.displayTitle
        let cleaned = t.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
        return cleaned.isEmpty ? (r.title_id ?? "Game") : cleaned
    }

    func startBuild(_ r: InspectionReport, input: URL, name: String) {
        guard activeBuild?.state.isActive != true else { show(.error, "A build is already running"); return }
        let existing = r.title_id.flatMap { library.managedEntry(titleID: $0) }
        if let existing, sessions.isRunning(existing.id) {
            show(.error, "Close \(existing.title) before rebuilding it"); return
        }
        let d = UserDefaults.standard
        let req = BuildRequest(input: input, report: r, appName: name,
                               signingIdentity: d.string(forKey: "GameSigningIdentity"), teamID: d.string(forKey: "TeamID"),
                               package: r.selected_version.map { "v\($0)" }, existingEntry: existing)
        let job = backend.makeBuildJob(for: req)
        activeBuild = job
        showBuildPanel(job)
        Task {
            await job.start()
            finishBuild(job, report: r, input: input)
        }
    }

    func showBuildPanel(_ job: BuildJob) {
        let p = BuildPanel(job: job)
        p.onClose = { [weak self] in self?.popOverlay() }
        p.onOpenLogs = { NSWorkspace.shared.activateFileViewerSelecting([job.stderrLog]) }
        p.onCancelRequested = { [weak self] in
            let c = ListPanel(title: "Cancel the build?", message: "Your dump, any installed version of this game and its saves are kept.", rows: [
                .init(label: "Keep building", action: { [weak self] in self?.popOverlay() }),
                .init(label: "Cancel build", destructive: true, action: { [weak self] in self?.popOverlay(); job.cancel() }),
            ], defaultFocus: 0, layout: .buttons)
            self?.pushOverlay(.list(c))
        }
        pushOverlay(.build(p))
    }

    private func finishBuild(_ job: BuildJob, report r: InspectionReport, input: URL) {
        switch job.state {
        case .succeeded(let app):
            var e = job.request.existingEntry ?? GameEntry(kind: .managed, title: job.request.appName)
            e.kind = .managed
            e.title = job.request.appName
            e.titleID = r.title_id
            e.platform = r.platform
            e.packageVersion = r.selected_version
            e.packageLabelVersion = r.labels.display_version
            e.verifiedDisplayVersion = r.verifiedVersion?.0
            e.buildIDs = r.build_ids
            e.profileMatch = r.profile?.match
            e.backendID = backend.id
            e.backendCommit = backend.pin.commit
            e.sourcePath = input.path
            e.appPath = app.path
            e.bundleID = job.bundleID ?? "org.nxnative.\((r.title_id ?? "").lowercased())"
            if let tid = r.title_id {
                e.saveFolder = backend.saveFolder(titleID: tid).path
                e.logPath = backend.logFile(titleID: tid).path
            }
            e.artworkPath = LibraryStore.importArtwork(from: job.iconPath ?? r.icon, for: e.id) ?? e.artworkPath
            e.lastBuild = job.record(outcome: "succeeded")
            library.upsert(e)
            if let i = entryIndex(e.id) { zone = .row; rowIndex = i }
            show(.success, "\(e.title) is installed", detail: app.path + (job.warnings.isEmpty ? "" : " · " + job.warnings.joined(separator: "; ")))
        case .failed(let m):
            show(.error, "Build failed", detail: m)
        case .cancelled:
            show(.info, "Build cancelled", detail: "Nothing was changed.")
        default: break
        }
    }

    // MARK: Existing game apps

    func showAppPicker() {
        let fm = FileManager.default
        var apps: [URL] = []
        for dir in [Paths.games, URL(fileURLWithPath: "/Applications"), Paths.home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications/Games")] {
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                apps += items.filter { $0.pathExtension == "app" }
            }
        }
        let known = Set(entries.compactMap { $0.appURL?.standardizedFileURL })
        let candidates = Array(Set(apps.map(\.standardizedFileURL))).filter { !known.contains($0) }.sorted {
            let ga = Self.isGameApp($0), gb = Self.isGameApp($1)
            return ga != gb ? ga : $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
        var rows: [ListPanel.Row] = [.init(label: "Browse with Finder…", systemImage: "folder", action: { [weak self] in self?.popOverlay(); self?.browseForApp() })]
        for a in candidates {
            let icon = NSWorkspace.shared.icon(forFile: a.path); icon.size = NSSize(width: 48, height: 48)
            rows.append(.init(label: a.deletingPathExtension().lastPathComponent,
                              detail: (Self.isGameApp(a) ? "Game · " : "") + a.deletingLastPathComponent().path, image: icon,
                              action: { [weak self] in self?.popOverlay(); self?.registerApp(a) }))
        }
        rows.append(.init(label: "Cancel", action: { [weak self] in self?.popOverlay() }))
        pushOverlay(.list(ListPanel(title: "Choose an existing game app", message: "Games (and nxnative builds) are listed first.", rows: rows)))
    }

    nonisolated static func isGameApp(_ u: URL) -> Bool {
        guard let info = NSDictionary(contentsOf: u.appendingPathComponent("Contents/Info.plist")) else { return false }
        if info["DMTitleID"] != nil { return true }
        return (info["LSApplicationCategoryType"] as? String)?.contains("games") == true
    }

    func browseForApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.prompt = "Add to AsterNUP"
        if p.runModal() == .OK, let u = p.url { registerApp(u) }
        bringForward()
    }

    func registerApp(_ url: URL) {
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        if let existing = entries.first(where: { $0.appURL?.standardizedFileURL == url.standardizedFileURL }) {
            if let i = entryIndex(existing.id) { zone = .row; rowIndex = i }
            show(.info, "\(existing.title) is already in the library"); return
        }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        var e = GameEntry(kind: .external, title: name)
        e.appPath = url.path
        e.bundleID = info["CFBundleIdentifier"] as? String
        if let tid = info["DMTitleID"] as? String {
            // An nxnative game app built elsewhere: it follows the same settings, save and log contract.
            e.kind = .managed
            e.titleID = tid.uppercased()
            e.backendID = backend.id
            e.saveFolder = backend.saveFolder(titleID: tid).path
            e.logPath = backend.logFile(titleID: tid).path
            e.verifiedDisplayVersion = info["CFBundleShortVersionString"] as? String
        }
        e.artworkPath = LibraryStore.appIconArtwork(app: url, for: e.id)
        library.upsert(e)
        if let i = entryIndex(e.id) { zone = .row; rowIndex = i }
        show(.success, "\(name) added to the library")
    }

    // MARK: Per-game options

    func showOptions(_ id: UUID, section: Int = 0) {
        guard let e = library.entry(id) else { return }
        var sections: [SectionedPanel.Section] = []
        sections.append(SectionedPanel.Section(title: "Game settings", rows: gameSettingRows(e)))
        sections.append(SectionedPanel.Section(title: "Launch", rows: launchRows(e)))
        sections.append(SectionedPanel.Section(title: "Save data", rows: saveRows(e)))
        sections.append(SectionedPanel.Section(title: "Manage software", rows: manageRows(e)))
        let sub = [e.verifiedDisplayVersion.map { "Ver. \($0)" }, e.titleID, sessions.isRunning(id) ? "Playing" : nil].compactMap { $0 }.joined(separator: " · ")
        let p = SectionedPanel(title: e.title, subtitle: sub, artwork: e.artworkPath, sections: sections)
        p.section = min(section, sections.count - 1)
        pushOverlay(.sectioned(p))
    }

    private func gameSettingRows(_ e: GameEntry) -> [SectionedPanel.Row] {
        guard e.kind == .managed, let app = e.appURL, let bid = e.bundleID else {
            return [.init(label: "This app's integration supports launch, resume (HOME) and close.", note: "Settings are changed inside the app.", kind: .info)]
        }
        guard let s = backend.settings(forApp: app), !s.settings.isEmpty else {
            return [.init(label: "This build offers no settings.", note: "Its tested defaults are used.", kind: .info)]
        }
        let be = backend
        var current: [String: String] = [:]
        for st in s.settings { current[st.env] = be.savedChoice(st.env, bundleID: bid) ?? st.default ?? "" }
        let box = Box(current)
        var rows: [SectionedPanel.Row] = []
        var lastSection: String?
        for st in s.settings {
            let sec = st.section ?? "Game"
            let note = [sec != lastSection ? sec : nil, st.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            lastSection = sec
            let def = st.default ?? ""
            let set: (String) -> Void = { v in
                box.value[st.env] = v
                be.setSavedChoice(st.env, value: v == def ? nil : v, bundleID: bid)   // only differences from the tested default are kept
            }
            let visible: () -> Bool = {
                guard let n = st.needs, let eq = n.firstIndex(of: "=") else { return true }
                let k = String(n[..<eq]), v = String(n[n.index(after: eq)...])
                guard s.settings.contains(where: { $0.env == k }) else { return true }
                return box.value[k] == v
            }
            let kind: SectionedPanel.Kind
            switch st.kind {
            case "choice":
                kind = .choice(options: (st.options ?? []).compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }, get: { box.value[st.env] ?? def }, set: set)
            case "toggle":
                let on = st.on ?? "on", off = st.off ?? "off"
                kind = .toggle(get: { box.value[st.env] == on }, set: { set($0 ? on : off) })
            case "range":
                kind = .range(min: st.min ?? 0, max: st.max ?? 1, step: st.step ?? 0.05,
                              get: { Double(box.value[st.env] ?? def) ?? 0 },
                              set: { v in set(String(format: (st.step ?? 0.05) < 1 ? "%.2f" : "%.0f", v)) },
                              format: { v in String(format: (st.step ?? 0.05) < 1 ? "%.2f" : "%.0f", v) })
            default:
                kind = .info
            }
            rows.append(.init(label: st.label, note: note, kind: kind, visible: visible))
        }
        rows.append(.init(label: "Reset to tested defaults", kind: .action({
            for st in s.settings { be.setSavedChoice(st.env, value: nil, bundleID: bid); box.value[st.env] = st.default ?? "" }
        })))
        return rows
    }

    private func launchRows(_ e: GameEntry) -> [SectionedPanel.Row] {
        var rows: [SectionedPanel.Row] = []
        if e.kind == .managed, let tid = e.titleID {
            let lib = library, id = e.id
            rows.append(.init(label: "Frame-time capture", note: "Writes per-frame timing (DM_NVN_TSV) to ~/Library/Logs/AsterNUP/perf for performance reports. Applies at the next start.",
                              kind: .toggle(get: { lib.entry(id)?.launchEnvironment["DM_NVN_TSV"] != nil }, set: { on in
                                  guard var x = lib.entry(id) else { return }
                                  if on {
                                      let dir = Paths.logs.appendingPathComponent("perf"); Paths.ensure(dir)
                                      x.launchEnvironment["DM_NVN_TSV"] = dir.appendingPathComponent("\(tid)-latest.tsv").path
                                      x.launchEnvironment["DM_NVN_TSV_CALLS"] = "0"
                                  } else { x.launchEnvironment["DM_NVN_TSV"] = nil; x.launchEnvironment["DM_NVN_TSV_CALLS"] = nil }
                                  lib.upsert(x)
                              })))
        }
        rows.append(.init(label: "HOME returns here", note: "Short-press HOME (or \(settings.homeShortcut.rawValue)) during play. Holding HOME is left to the game.", kind: .info))
        if !e.launchArguments.isEmpty { rows.append(.init(label: "Arguments", value: e.launchArguments.joined(separator: " "), kind: .info)) }
        return rows
    }

    private func saveRows(_ e: GameEntry) -> [SectionedPanel.Row] {
        guard let sf = e.saveFolder else {
            return [.init(label: "Save location unknown", note: "This app manages its own saves.", kind: .info)]
        }
        let url = URL(fileURLWithPath: sf)
        return [
            .init(label: "Save folder", note: sf, kind: .info),
            .init(label: "Reveal save folder", kind: .action({
                if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                else { NSWorkspace.shared.open(url.deletingLastPathComponent().deletingLastPathComponent()) }
            })),
            .init(label: "Create ZIP backup", note: sessions.isRunning(e.id) ? "Close the game first: a backup is made only after it exits." : "Verified by extracting and comparing every file.",
                  kind: .action({ [weak self] in self?.backupSaves(e) }), enabled: !sessions.isRunning(e.id)),
            .init(label: "Reveal backups", note: settings.backupFolder, kind: .action({ [weak self] in
                guard let self else { return }
                let u = URL(fileURLWithPath: self.settings.backupFolder); Paths.ensure(u); NSWorkspace.shared.open(u)
            })),
        ]
    }

    private func manageRows(_ e: GameEntry) -> [SectionedPanel.Row] {
        var rows: [SectionedPanel.Row] = []
        func info(_ l: String, _ v: String?) { if let v, !v.isEmpty { rows.append(.init(label: l, value: v, kind: .info)) } }
        info("Title ID", e.titleID)
        info("Platform", e.platform)
        info("Package version", e.packageVersion.map { "v\($0)" })
        info("Verified version", e.verifiedDisplayVersion)
        info("Package label", e.packageLabelVersion.map { "\($0) (typed by the packer, not verified)" })
        info("Build ID (main)", e.buildIDs["main"])
        info("Profile match", e.profileMatch)
        info("Backend", e.backendCommit.map { "nxnative @ \($0.prefix(10))" })
        info("App", e.appPath)
        info("Dump", e.sourcePath)
        rows.append(.init(label: "Reveal app in Finder", kind: .action({ if let u = e.appURL { NSWorkspace.shared.activateFileViewerSelecting([u]) } }), enabled: e.isInstalled))
        if let lp = e.logPath {
            rows.append(.init(label: "Open game log", note: lp, kind: .action({
                let u = URL(fileURLWithPath: lp)
                if FileManager.default.fileExists(atPath: lp) { NSWorkspace.shared.activateFileViewerSelecting([u]) } else { NSWorkspace.shared.open(u.deletingLastPathComponent()) }
            })))
        }
        if let lb = e.lastBuild {
            rows.append(.init(label: "Open build logs", note: lb.logDir, kind: .action({ NSWorkspace.shared.open(URL(fileURLWithPath: lb.logDir)) })))
        }
        if let src = e.sourcePath {
            let exists = FileManager.default.fileExists(atPath: src)
            rows.append(.init(label: "Rebuild from dump", note: exists ? src : "The dump is not at \(src) any more.", kind: .action({ [weak self] in
                self?.popAll(); self?.importDump(URL(fileURLWithPath: src))
            }), enabled: exists && !sessions.isRunning(e.id)))
        }
        rows.append(.init(label: "Remove from library", note: "Keeps the app, the dump and the saves.", kind: .action({ [weak self] in self?.confirmRemove(e) })))
        return rows
    }

    func confirmRemove(_ e: GameEntry) {
        pushOverlay(.list(ListPanel(title: "Remove \(e.title) from the library?", message: "The app, your dump and the saves stay on disk.", rows: [
            .init(label: "Cancel", action: { [weak self] in self?.popOverlay() }),
            .init(label: "Remove", destructive: true, action: { [weak self] in
                guard let self else { return }
                self.popAll(); self.library.remove(e.id); self.rowIndex = min(self.rowIndex, self.rowCount - 1)
            }),
        ], defaultFocus: 0, layout: .buttons)))
    }

    func backupSaves(_ e: GameEntry) {
        guard !sessions.isRunning(e.id) else { show(.error, "Close \(e.title) first"); return }
        guard let sf = e.saveFolder else { return }
        let busy = BusyPanel(title: "Backing up \(e.title)'s save…")
        pushOverlay(.busy(busy))
        Task {
            do {
                let r = try await SaveBackup.backup(saveFolder: URL(fileURLWithPath: sf), title: e.title, into: URL(fileURLWithPath: settings.backupFolder))
                if overlays.last?.surface === busy { popOverlay() }
                show(.success, "Backup verified: \(r.files) files, \(r.bytes.byteString)", detail: r.zip.path)
            } catch {
                if overlays.last?.surface === busy { popOverlay() }
                show(.error, "Backup failed", detail: error.localizedDescription)
            }
        }
    }

    // MARK: Backend & Home settings

    func refreshBackendStatus() async {
        backendStatus = await backend.status()
    }

    func showBackend() {
        let p = SectionedPanel(title: "Backend & toolchain", subtitle: "nxnative pinned at \(backend.pin.commit.prefix(10)) (\(backend.pin.commit_date))", sections: [])
        func rebuild() {
            let st = backendStatus
            var checks: [SectionedPanel.Row] = (st?.checks ?? []).map {
                .init(label: $0.name, note: $0.state == .ok ? $0.detail : "\($0.detail)\nFix: \($0.fix)", kind: .info, status: $0.state)
            }
            checks.insert(.init(label: st?.summary ?? "Checking…", kind: .info), at: 0)
            checks.append(.init(label: "Check again", kind: .action({ [weak self] in
                Task { await self?.refreshBackendStatus(); rebuild() }
            })))
            checks.append(.init(label: "Set up backend (fetch pinned revision)", note: backend.checkout.path, kind: .action({ [weak self] in
                guard let self else { return }
                let busy = BusyPanel(title: "Setting up nxnative…"); self.pushOverlay(.busy(busy))
                Task {
                    do { try await self.backend.preparePinnedCheckout { busy.detail = $0 } ; self.show(.success, "Backend pinned at \(self.backend.pin.commit.prefix(10))") }
                    catch { self.show(.error, "Backend setup failed", detail: error.localizedDescription) }
                    if self.overlays.last?.surface === busy { self.popOverlay() }
                    await self.refreshBackendStatus(); rebuild()
                }
            })))
            checks.append(.init(label: "Set up Python environment", note: "Creates AsterNUP's own Python environment and installs the backend's modules: \(Paths.pythonVenv.path)", kind: .action({ [weak self] in
                guard let self else { return }
                let busy = BusyPanel(title: "Setting up Python…"); self.pushOverlay(.busy(busy))
                Task {
                    do { try await self.backend.preparePythonEnvironment { busy.detail = $0 }; self.show(.success, "Python environment ready") }
                    catch { self.show(.error, "Python setup failed", detail: error.localizedDescription) }
                    if self.overlays.last?.surface === busy { self.popOverlay() }
                    await self.refreshBackendStatus(); rebuild()
                }
            })))
            checks.append(.init(label: "Copy fix commands", note: "Copies the commands for every missing piece.", kind: .action({ [weak self] in
                let cmds = (self?.backendStatus?.checks ?? []).filter { $0.state != .ok && !$0.fix.isEmpty }.map(\.fix).joined(separator: "\n")
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmds, forType: .string)
                self?.show(.info, "Copied \(cmds.split(separator: "\n").count) commands")
            })))
            let profiles = backend.supportedProfiles().map {
                SectionedPanel.Row(label: $0.name, note: "\($0.titleID) · builds: \($0.builds.joined(separator: ", "))", kind: .info)
            }
            p.sections = [
                .init(title: "Status", rows: checks),
                .init(title: "Supported games (\(profiles.count))", rows: profiles.isEmpty ? [.init(label: "Set up the backend to list its game profiles.", kind: .info)] : profiles),
                .init(title: "Signing", rows: signingRows()),
            ]
            p.tick += 1
        }
        rebuild()
        pushOverlay(.sectioned(p))
        Task { await refreshBackendStatus(); rebuild() }
    }

    private func signingRows() -> [SectionedPanel.Row] {
        let d = UserDefaults.standard
        return [
            .init(label: "Game app signing identity",
                  note: "Set with: defaults write com.asterpolaris.AsterNUP GameSigningIdentity \"Apple Development: …\". nxnative signs game apps without Hardened Runtime (it maps executable memory).",
                  value: d.string(forKey: "GameSigningIdentity").flatMap { $0.isEmpty ? nil : $0 } ?? "Ad-hoc (default)", kind: .info),
            .init(label: "Team ID", note: "defaults write com.asterpolaris.AsterNUP TeamID ABCDE12345", value: d.string(forKey: "TeamID") ?? "not set", kind: .info),
        ]
    }

    func showHomeSettings() {
        let p = SectionedPanel(title: "Home settings", sections: [])
        p.sections = [
            .init(title: "Display", rows: [
                .init(label: "Appearance", kind: .choice(options: HomeSettings.Appearance.allCases.map { ($0.rawValue, $0.rawValue.capitalized) },
                                                         get: { [weak self] in self?.settings.appearance.rawValue ?? "system" },
                                                         set: { [weak self] v in self?.settings.appearance = .init(rawValue: v) ?? .system })),
                .init(label: "Start in full screen", kind: .toggle(get: { [weak self] in self?.settings.startFullscreen ?? true }, set: { [weak self] v in self?.settings.startFullscreen = v })),
                .init(label: "Toggle full screen now", kind: .action({ [weak self] in self?.window?.toggleFullScreen(nil) })),
            ]),
            .init(title: "Playing", rows: [
                .init(label: "Check this Mac before starting a game", note: "Before an nxnative game starts, AsterNUP lists apps holding the memory the game needs (and offers to quit them), and warns about Low Power Mode and heat. Shown only when something would cost frames.",
                      kind: .toggle(get: { [weak self] in self?.settings.checkBeforePlaying ?? true }, set: { [weak self] v in self?.settings.checkBeforePlaying = v })),
            ]),
            .init(title: "HOME button", rows: [
                .init(label: "Controller HOME returns to AsterNUP", note: "Short press. If macOS keeps your controller's HOME button, use the shortcut or − and + below.",
                      kind: .toggle(get: { [weak self] in self?.settings.controllerHome ?? true }, set: { [weak self] v in self?.settings.controllerHome = v })),
                .init(label: "Press − and + together for HOME", kind: .toggle(get: { [weak self] in self?.settings.minusPlusHome ?? false }, set: { [weak self] v in self?.settings.minusPlusHome = v })),
                .init(label: "Keyboard HOME shortcut", note: "Works while a game is in front.",
                      kind: .choice(options: HomeSettings.HomeShortcut.allCases.map { ($0.rawValue, $0.rawValue) },
                                    get: { [weak self] in self?.settings.homeShortcut.rawValue ?? "Off" },
                                    set: { [weak self] v in self?.settings.homeShortcut = .init(rawValue: v) ?? .off })),
            ]),
            .init(title: "Data", rows: [
                .init(label: "Backup folder", note: settings.backupFolder, kind: .action({ [weak self] in
                    let o = NSOpenPanel(); o.canChooseDirectories = true; o.canChooseFiles = false; o.canCreateDirectories = true
                    if o.runModal() == .OK, let u = o.url { self?.settings.backupFolder = u.path }
                    self?.bringForward()
                })),
                .init(label: "Library file", note: Paths.library.path, kind: .action({ NSWorkspace.shared.activateFileViewerSelecting([Paths.library]) })),
                .init(label: "AsterNUP log", note: AppLog.url.path, kind: .action({ NSWorkspace.shared.activateFileViewerSelecting([AppLog.url]) })),
                .init(label: "Installed games folder", note: Paths.games.path, kind: .action({ Paths.ensure(Paths.games); NSWorkspace.shared.open(Paths.games) })),
            ]),
        ]
        pushOverlay(.sectioned(p))
    }

    // MARK: Controllers

    func showControllers() {
        let p = SectionedPanel(title: "Controllers", subtitle: "Nintendo Switch Pro Controller, Joy-Con, Switch 2 controllers, and other gamepads", sections: [])
        func rebuild() {
            let list = input.controllers
            var connected: [SectionedPanel.Row] = list.map {
                .init(label: $0.name, note: "\($0.family) · \($0.profile) · via \($0.source)\n\($0.faceMapping)", kind: .info, status: .ok)
            }
            if connected.isEmpty {
                connected.append(.init(label: "No controller connected", note: "Pair a Pro Controller or Joy-Con: hold its small Sync button, then choose it in System Settings › Bluetooth. A Joy-Con pair can be combined in System Settings › Game Controllers. USB works too.", kind: .info, status: .warning))
            }
            connected.append(.init(label: "Refresh", kind: .action({ rebuild() })))
            connected.append(.init(label: "Open Bluetooth settings", kind: .action({
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            })))
            connected.append(.init(label: "Open Game Controllers settings", note: "Where macOS decides whether apps may use each controller's HOME button, and combines Joy-Con pairs.", kind: .action({
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Game-Controller-Settings.extension")!)
            })))
            let buttons: [SectionedPanel.Row] = [
                .init(label: "Face buttons", note: "By label: the button printed A confirms and B goes back, as on a Nintendo Switch (A is on the right). By position: the bottom button confirms, as on Xbox. PlayStation controllers always go by position.",
                      kind: .choice(options: HomeSettings.ButtonLayout.allCases.map { ($0.rawValue, $0.rawValue) },
                                    get: { [weak self] in self?.settings.buttonLayout.rawValue ?? "By label" },
                                    set: { [weak self] v in self?.settings.buttonLayout = .init(rawValue: v) ?? .byLabel })),
                .init(label: "HOME returns to AsterNUP", note: "A short press. Holding HOME for 2 seconds stays the game's quit prompt.",
                      kind: .toggle(get: { [weak self] in self?.settings.controllerHome ?? true }, set: { [weak self] v in self?.settings.controllerHome = v })),
                .init(label: "Press − and + together for HOME", note: "For a controller whose HOME button macOS keeps for itself.",
                      kind: .toggle(get: { [weak self] in self?.settings.minusPlusHome ?? false }, set: { [weak self] v in self?.settings.minusPlusHome = v })),
                .init(label: "Read other gamepads as raw HID", note: "Nintendo and other gamepads that macOS pairs but does not list as game controllers (some Switch Online controllers, adapters).",
                      kind: .toggle(get: { [weak self] in self?.settings.hidFallback ?? true }, set: { [weak self] v in self?.settings.hidFallback = v })),
            ]
            let sw2Games = entries.filter { e in
                guard e.kind == .managed, let app = e.appURL else { return false }
                return backend.settings(forApp: app)?.settings.contains { $0.env == "DM_SW2" } == true
            }
            let sw2: [SectionedPanel.Row] = [
                .init(label: "How Switch 2 controllers connect", note: "Joy-Con 2 and Pro Controller 2 speak Nintendo's own Bluetooth LE protocol: they never appear in macOS Bluetooth settings or to AsterNUP's Home screen. nxnative games connect them directly. Turn the setting on, start the game, then hold the controller's Sync button until its lights sweep (once). Afterwards any button press wakes it while the game runs. Use the keyboard HOME shortcut (\(settings.homeShortcut.rawValue)) to come back to AsterNUP while playing with one.", kind: .info),
                .init(label: "Turn on in every installed game", note: sw2Games.isEmpty ? "No installed game offers it yet." : "\(sw2Games.count) game(s): " + sw2Games.map(\.title).joined(separator: ", "),
                      kind: .action({ [weak self] in self?.setSwitch2(true, in: sw2Games) }), enabled: !sw2Games.isEmpty),
                .init(label: "Turn off in every installed game", kind: .action({ [weak self] in self?.setSwitch2(false, in: sw2Games) }), enabled: !sw2Games.isEmpty),
            ]
            p.sections = [.init(title: "Connected (\(list.count))", rows: connected), .init(title: "Buttons & HOME", rows: buttons), .init(title: "Switch 2 controllers", rows: sw2)]
            p.tick += 1
        }
        rebuild()
        pushOverlay(.sectioned(p))
    }

    private func setSwitch2(_ on: Bool, in games: [GameEntry]) {
        for e in games {
            guard let app = e.appURL, let bid = e.bundleID, let st = backend.settings(forApp: app)?.settings.first(where: { $0.env == "DM_SW2" }) else { continue }
            let value = on ? (st.on ?? "1") : (st.off ?? "0")
            backend.setSavedChoice("DM_SW2", value: value == st.default ? nil : value, bundleID: bid)
        }
        show(.success, "Switch 2 controllers \(on ? "on" : "off") in \(games.count) game(s)", detail: on ? "Start the game, then hold Sync on the controller until its lights sweep." : "")
    }

    // MARK: Settings persistence

    private func loadSettings() {
        if let d = try? Data(contentsOf: Paths.homeSettings), let s = try? JSONDecoder().decode(HomeSettings.self, from: d) { settings = s }
    }
    private func saveSettings() {
        Paths.ensure(Paths.support)
        if let d = try? JSONEncoder().encode(settings) { try? d.write(to: Paths.homeSettings, options: .atomic) }
    }
    func applySettings() {
        input.settings = settings
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func cleanupStaleStaging() {
        // Leftovers of a build interrupted by quitting AsterNUP. Installed apps are never here.
        try? FileManager.default.removeItem(at: Paths.staging)
    }
}

/// Reference box for closures that edit a value shown in a panel.
final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

import AppKit

/// Tracks the actual running game apps. One live session per library entry; resuming reactivates the same instance.
final class SessionManager: ObservableObject {
    @Published private(set) var running: [UUID: NSRunningApplication] = [:]
    /// The entry whose app was last frontmost (HOME returns from it, Resume goes back to it).
    @Published var lastActiveGame: UUID?
    var onGameExited: ((UUID, Int32?) -> Void)?
    var onGameActivated: ((UUID) -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if let (id, _) = self.running.first(where: { $0.value.processIdentifier == app.processIdentifier }) {
                self.running[id] = nil
                if self.lastActiveGame == id { self.lastActiveGame = nil }
                self.onGameExited?(id, nil)
            }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if let (id, _) = self.running.first(where: { $0.value.processIdentifier == app.processIdentifier }) {
                self.lastActiveGame = id
                self.onGameActivated?(id)
            }
        })
    }

    func isRunning(_ id: UUID) -> Bool { running[id].map { !$0.isTerminated } ?? false }

    /// Re-adopt game apps that are already running (e.g. after AsterNUP restarts).
    func adopt(_ entries: [GameEntry]) {
        for e in entries {
            guard let url = e.appURL?.standardizedFileURL else { continue }
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL == url && !$0.isTerminated }) {
                running[e.id] = app
            }
        }
    }

    /// Start the game, or bring the existing session forward.
    func launchOrResume(_ e: GameEntry, environment: [String: String], arguments: [String]) async throws {
        if let app = running[e.id], !app.isTerminated {
            app.unhide()
            app.activate()
            lastActiveGame = e.id
            return
        }
        guard let url = e.appURL, FileManager.default.fileExists(atPath: url.path) else {
            throw BackendError("The game app is missing at \(e.appPath ?? "?"). Rebuild it or choose the app again.")
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        cfg.createsNewApplicationInstance = false
        cfg.environment = environment
        cfg.arguments = arguments
        cfg.addsToRecentItems = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        await MainActor.run {
            running[e.id] = app
            lastActiveGame = e.id
        }
    }

    /// Graceful quit (the same as ⌘Q in the game). Returns false if the app is still running after the timeout.
    func requestQuit(_ id: UUID, timeout: TimeInterval = 15) async -> Bool {
        guard let app = running[id], !app.isTerminated else { return true }
        _ = await MainActor.run { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.isTerminated { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return app.isTerminated
    }

    func forceQuit(_ id: UUID) { running[id]?.forceTerminate() }

    var frontmostGame: UUID? {
        guard let f = NSWorkspace.shared.frontmostApplication else { return nil }
        return running.first(where: { $0.value.processIdentifier == f.processIdentifier })?.key
    }
}

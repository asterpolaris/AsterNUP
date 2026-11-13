// A stand-in "game" app for exercising AsterNUP without a real game: it follows the nxnative Mac app
// contract (DMTitleID, Contents/Resources/dm/launcher.json, saved choices in its preferences domain,
// save folder ~/Library/Application Support/nxnative/<title ID>/save) and shows a running frame counter.
// It contains no game code or data. Build: Tests/build_standin.sh
import AppKit

let tid = Bundle.main.object(forInfoDictionaryKey: "DMTitleID") as? String ?? "0100000000ABC000"
let saveDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/nxnative/\(tid)/save")

final class GameView: NSView {
    var frame0 = 0
    var timer: Timer?
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ r: NSRect) {
        NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.2, alpha: 1).setFill(); r.fill()
        let scale = UserDefaults.standard.string(forKey: "launcher.DM_RENDER_SCALE") ?? "default"
        let fps = UserDefaults.standard.string(forKey: "launcher.DM_FPS_TARGET") ?? "default"
        let env = ProcessInfo.processInfo.environment
        let s = """
        Stand-in Game (\(tid))
        frame \(frame0)
        saved choices: DM_FPS_TARGET=\(fps) DM_RENDER_SCALE=\(scale)
        launch env: DM_LAUNCHER=\(env["DM_LAUNCHER"] ?? "unset")
        Press S to save · ⌘Q to quit
        """
        s.draw(at: NSPoint(x: 40, y: bounds.midY - 60), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white])
    }
    override func keyDown(with e: NSEvent) {
        if e.charactersIgnoringModifiers == "s" { save() } else { super.keyDown(with: e) }
    }
    func save() {
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        try? "frame=\(frame0)\n".write(to: saveDir.appendingPathComponent("slot0.sav"), atomically: true, encoding: .utf8)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        let v = GameView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        window = NSWindow(contentRect: v.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Stand-in Game"
        window.contentView = v; window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(v)
        v.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in v.frame0 += 1; v.needsDisplay = true }
        if ProcessInfo.processInfo.environment["STANDIN_AUTOSAVE"] == "1" { v.save() }
        NSApp.activate(ignoringOtherApps: true)
        let m = NSMenu(); let i = NSMenuItem(); m.addItem(i); let am = NSMenu()
        am.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); i.submenu = am; NSApp.mainMenu = m
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let d = Delegate()
app.delegate = d
app.setActivationPolicy(.regular)
app.run()

import AppKit

/// Scripted UI checks without Screen Recording permission: `AsterNUP --windowed --ui-test script.txt`.
/// Lines: `wait <s>`, `press <action>` (up down left right confirm back x y plus minus shoulderL shoulderR home),
/// `snap <png path>` (renders AsterNUP's own window), `import <path>`, `register <app path>`, `appearance light|dark|system`,
/// `state <json path>` (dumps focus/overlay state), `quit`.
@MainActor
enum UITestHarness {
    static func run(script: URL, model: AppModel, window: NSWindow) {
        guard let text = try? String(contentsOf: script, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        Task { @MainActor in
            for line in lines {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                let arg = parts.count > 1 ? parts[1] : ""
                switch parts[0] {
                case "wait": try? await Task.sleep(nanoseconds: UInt64((Double(arg) ?? 1) * 1e9))
                case "press": if let a = action(arg) { model.handle(a) }
                case "snap": snap(window, to: URL(fileURLWithPath: arg))
                case "import": model.importDump(URL(fileURLWithPath: arg))
                case "register": model.registerApp(URL(fileURLWithPath: arg))
                case "appearance": model.settings.appearance = HomeSettings.Appearance(rawValue: arg) ?? .system
                case "state": dumpState(model, to: URL(fileURLWithPath: arg))
                case "quit": NSApp.terminate(nil)
                default: AppLog.write("ui-test: unknown line \(line)")
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    static func action(_ s: String) -> NavAction? {
        ["up": .up, "down": .down, "left": .left, "right": .right, "confirm": .confirm, "back": .back, "x": .x, "y": .y,
         "plus": .plus, "minus": .minus, "shoulderL": .shoulderL, "shoulderR": .shoulderR, "home": .home][s]
    }

    static func snap(_ w: NSWindow, to url: URL) {
        guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    static func dumpState(_ m: AppModel, to url: URL) {
        let d: [String: Any] = [
            "zone": m.zone == .row ? "row" : "dock", "rowIndex": m.rowIndex, "dockIndex": m.dockIndex,
            "overlays": m.overlays.map { String(describing: $0.kind).components(separatedBy: "(").first ?? "" },
            "entries": m.entries.map { ["title": $0.title, "kind": $0.kind.rawValue, "app": $0.appPath ?? "", "running": m.sessions.isRunning($0.id), "pid": m.sessions.running[$0.id]?.processIdentifier ?? 0] },
            "banner": m.banner?.text ?? "", "frontmostGame": m.sessions.frontmostGame?.uuidString ?? "",
            "appActive": NSApp.isActive, "hints": m.hints.map { "\($0.button) \($0.label)" },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
    }
}

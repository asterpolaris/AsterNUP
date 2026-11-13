import SwiftUI

/// Anything that can take controller input while it is the top surface.
protocol NavSurface: AnyObject {
    /// Returns false to let the coordinator handle it (B closes the surface).
    func handle(_ a: NavAction) -> Bool
    /// Hints shown in the bottom bar while this surface is on top.
    var hints: [Hint] { get }
}

struct Hint: Hashable { var button: String; var label: String }

// MARK: - List panel: menus, pickers, confirmations

final class ListPanel: ObservableObject, NavSurface {
    struct Row: Identifiable {
        let id = UUID()
        var label: String
        var detail: String = ""
        var systemImage: String?
        var image: NSImage?
        var enabled: Bool = true
        var destructive: Bool = false
        var action: () -> Void
    }
    enum Layout { case vertical, buttons }

    let title: String
    let message: String
    @Published var rows: [Row]
    @Published var focus: Int
    let layout: Layout
    var onCancel: (() -> Void)?

    init(title: String, message: String = "", rows: [Row], defaultFocus: Int = 0, layout: Layout = .vertical, onCancel: (() -> Void)? = nil) {
        self.title = title; self.message = message; self.rows = rows; self.layout = layout; self.onCancel = onCancel
        focus = min(max(defaultFocus, 0), max(rows.count - 1, 0))
    }

    func move(_ d: Int) {
        guard !rows.isEmpty else { return }
        var i = focus
        for _ in rows.indices {
            i = (i + d + rows.count) % rows.count
            if rows[i].enabled { focus = i; return }
        }
    }

    func handle(_ a: NavAction) -> Bool {
        switch (a, layout) {
        case (.up, .vertical), (.left, .buttons): move(-1)
        case (.down, .vertical), (.right, .buttons): move(1)
        case (.confirm, _): if rows.indices.contains(focus), rows[focus].enabled { rows[focus].action() }
        case (.back, _): onCancel?(); return false
        default: break
        }
        return true
    }

    var hints: [Hint] { [Hint(button: "A", label: "OK"), Hint(button: "B", label: "Back")] }
}

// MARK: - Sectioned panel: per-game options, Home settings, backend status

final class SectionedPanel: ObservableObject, NavSurface {
    enum Kind {
        case action(() -> Void)
        case choice(options: [(String, String)], get: () -> String, set: (String) -> Void)
        case toggle(get: () -> Bool, set: (Bool) -> Void)
        case range(min: Double, max: Double, step: Double, get: () -> Double, set: (Double) -> Void, format: (Double) -> String)
        case info
    }
    struct Row: Identifiable {
        let id = UUID()
        var label: String
        var note: String = ""
        var value: String = ""
        var kind: Kind
        var enabled: Bool = true
        var visible: () -> Bool = { true }
        var status: ToolCheck.State?
    }
    struct Section: Identifiable { let id = UUID(); var title: String; var rows: [Row] }

    let title: String
    let subtitle: String
    let artwork: String?
    @Published var sections: [Section]
    @Published var section = 0
    @Published var row = 0
    @Published var column = 0   // 0: sections list, 1: rows
    @Published var tick = 0      // bumps to redraw values

    init(title: String, subtitle: String = "", artwork: String? = nil, sections: [Section]) {
        self.title = title; self.subtitle = subtitle; self.artwork = artwork; self.sections = sections
    }

    var visibleRows: [Row] { sections.indices.contains(section) ? sections[section].rows.filter { $0.visible() } : [] }

    func valueText(_ r: Row) -> String {
        switch r.kind {
        case .choice(let opts, let get, _): let v = get(); return opts.first { $0.0 == v }?.1 ?? v
        case .toggle(let get, _): return get() ? "On" : "Off"
        case .range(_, _, _, let get, _, let f): return f(get())
        case .action, .info: return r.value
        }
    }

    private func adjust(_ d: Int) {
        let rows = visibleRows
        guard rows.indices.contains(row), rows[row].enabled else { return }
        switch rows[row].kind {
        case .choice(let opts, let get, let set):
            guard !opts.isEmpty else { return }
            let i = opts.firstIndex { $0.0 == get() } ?? 0
            set(opts[(i + d + opts.count) % opts.count].0)
        case .toggle(let get, let set): set(!get())
        case .range(let lo, let hi, let st, let get, let set, _):
            let v = ((get() + Double(d) * st) / st).rounded() * st
            set(Swift.min(hi, Swift.max(lo, v)))
        default: return
        }
        tick += 1
    }

    func handle(_ a: NavAction) -> Bool {
        let rows = visibleRows
        switch a {
        case .up:
            if column == 0 { section = max(0, section - 1); row = 0 } else { row = max(0, row - 1) }
        case .down:
            if column == 0 { section = min(sections.count - 1, section + 1); row = 0 } else { row = min(rows.count - 1, row + 1) }
        case .right:
            if column == 0 { if !rows.isEmpty { column = 1; row = min(row, rows.count - 1) } } else { adjust(1) }
        case .left:
            if column == 1 {
                if rows.indices.contains(row), case .action = rows[row].kind { column = 0 }
                else if rows.indices.contains(row), case .info = rows[row].kind { column = 0 }
                else { adjust(-1) }
            }
        case .confirm:
            if column == 0 { if !rows.isEmpty { column = 1; row = 0 } }
            else if rows.indices.contains(row), rows[row].enabled {
                if case .action(let f) = rows[row].kind { f() } else { adjust(1) }
            }
        case .back:
            if column == 1 { column = 0; return true }
            return false
        case .shoulderL: section = max(0, section - 1); row = 0
        case .shoulderR: section = min(sections.count - 1, section + 1); row = 0
        default: break
        }
        return true
    }

    var hints: [Hint] {
        column == 0 ? [Hint(button: "A", label: "Select"), Hint(button: "B", label: "Close")]
                    : [Hint(button: "◀▶", label: "Change"), Hint(button: "A", label: "OK"), Hint(button: "B", label: "Back")]
    }
}

// MARK: - Inspection report

final class ReportPanel: ObservableObject, NavSurface {
    let report: InspectionReport
    let input: URL
    @Published var buttons: [ListPanel.Row]
    @Published var focus = 0
    @Published var scroll = 0
    var onCancel: (() -> Void)?

    init(report: InspectionReport, input: URL, buttons: [ListPanel.Row]) {
        self.report = report; self.input = input; self.buttons = buttons
        focus = buttons.firstIndex { $0.enabled } ?? 0
    }

    func handle(_ a: NavAction) -> Bool {
        switch a {
        case .left: if let i = (0..<focus).reversed().first(where: { buttons[$0].enabled }) { focus = i }
        case .right: if let i = (focus + 1..<buttons.count).first(where: { buttons[$0].enabled }) { focus = i }
        case .up: scroll = max(0, scroll - 1)
        case .down: scroll += 1
        case .confirm: if buttons.indices.contains(focus), buttons[focus].enabled { buttons[focus].action() }
        case .back: onCancel?(); return false
        default: break
        }
        return true
    }
    var hints: [Hint] { [Hint(button: "◀▶", label: "Choose"), Hint(button: "▲▼", label: "Scroll"), Hint(button: "A", label: "OK"), Hint(button: "B", label: "Cancel")] }
}

// MARK: - Build progress

final class BuildPanel: ObservableObject, NavSurface {
    let job: BuildJob
    var onCancelRequested: () -> Void = {}
    var onClose: () -> Void = {}
    var onOpenLogs: () -> Void = {}
    @Published var focus = 0
    init(job: BuildJob) { self.job = job }

    var buttons: [String] { job.state.isActive ? ["Cancel build", "Run in background"] : ["Close", "Open logs"] }

    func handle(_ a: NavAction) -> Bool {
        switch a {
        case .left: focus = max(0, focus - 1)
        case .right: focus = min(buttons.count - 1, focus + 1)
        case .confirm:
            if job.state.isActive { focus == 0 ? onCancelRequested() : onClose() }
            else { focus == 0 ? onClose() : onOpenLogs() }
        case .back:
            onClose(); return true
        default: break
        }
        return true
    }
    var hints: [Hint] { [Hint(button: "A", label: "OK"), Hint(button: "B", label: job.state.isActive ? "Run in background" : "Close")] }
}

/// A non-interactive busy state (e.g. "Inspecting…").
final class BusyPanel: ObservableObject, NavSurface {
    @Published var title: String
    @Published var detail: String = ""
    @Published var fraction: Double?
    init(title: String) { self.title = title }
    func handle(_ a: NavAction) -> Bool { true }
    var hints: [Hint] { [] }
}

import SwiftUI

struct OverlayView: View {
    let item: OverlayItem
    var body: some View {
        switch item.kind {
        case .list(let p): ListPanelView(panel: p)
        case .sectioned(let p): SectionedPanelView(panel: p)
        case .report(let p): ReportPanelView(panel: p)
        case .build(let p): BuildPanelView(panel: p, job: p.job)
        case .busy(let p): BusyPanelView(panel: p)
        }
    }
}

struct PanelChrome<Content: View>: View {
    var width: CGFloat = 720
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) var scheme
    var body: some View {
        content
            .padding(28)
            .frame(width: width)
            .background(Theme.shape(Theme.panelRadius).fill(.thickMaterial))
            .overlay(Theme.shape(Theme.panelRadius).strokeBorder(Theme.separator(scheme), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
    }
}

/// A push button. The focused one is filled with the accent colour, like a default button on the Mac.
struct PanelButton: View {
    let label: String
    let focused: Bool
    var destructive = false
    var enabled = true
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Text(label).font(.body.weight(.semibold))
            .frame(minWidth: 132).padding(.vertical, 10).padding(.horizontal, 18)
            .foregroundStyle(focused ? Color.white : destructive ? Theme.danger : Color.primary)
            .background {
                if focused { Theme.shape(Theme.rowRadius).fill((destructive ? Theme.danger : Theme.focus).gradient) }
                else { Theme.shape(Theme.rowRadius).fill(Theme.tile(scheme)) }
            }
            .shadow(color: (destructive ? Theme.danger : Theme.focus).opacity(focused ? 0.35 : 0), radius: 8, y: 3)
            .scaleEffect(focused ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: focused)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Theme.shape(Theme.rowRadius))
    }
}

/// A grouped container, like a section in System Settings.
struct GroupCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) var scheme
    var body: some View {
        content
            .background(Theme.shape(12).fill(Theme.card(scheme)))
            .overlay(Theme.shape(12).strokeBorder(Theme.separator(scheme).opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: List panel

struct ListPanelView: View {
    @ObservedObject var panel: ListPanel
    @Environment(\.colorScheme) var scheme
    var body: some View {
        PanelChrome(width: panel.layout == .buttons ? 560 : 720) {
            VStack(alignment: panel.layout == .buttons ? .center : .leading, spacing: 14) {
                if panel.layout == .buttons {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                }
                Text(panel.title).font(panel.layout == .buttons ? .title3.bold() : .title2.bold())
                    .multilineTextAlignment(panel.layout == .buttons ? .center : .leading)
                if !panel.message.isEmpty {
                    Text(panel.message).font(panel.layout == .buttons ? .callout : .body).foregroundStyle(.secondary).textSelection(.enabled)
                        .multilineTextAlignment(panel.layout == .buttons ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if panel.layout == .buttons {
                    HStack(spacing: 12) {
                        ForEach(Array(panel.rows.enumerated()), id: \.element.id) { i, r in
                            PanelButton(label: r.label, focused: panel.focus == i, destructive: r.destructive, enabled: r.enabled)
                                .onTapGesture { if r.enabled { panel.focus = i; r.action() } }
                        }
                    }.padding(.top, 8)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(panel.rows.enumerated()), id: \.element.id) { i, r in
                                    row(r, focused: panel.focus == i)
                                        .id(r.id)
                                        .onTapGesture { if r.enabled { panel.focus = i; r.action() } }
                                }
                            }.padding(6)
                        }
                        .frame(maxHeight: 460)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(Theme.shape(14).fill(Theme.card(scheme)))
                        .onChange(of: panel.focus) { _, i in
                            if panel.rows.indices.contains(i) { withAnimation { proxy.scrollTo(panel.rows[i].id, anchor: .center) } }
                        }
                    }
                }
            }
        }
    }

    /// A list row; the focused one is highlighted with the accent colour, like a selected row in a Mac list.
    @ViewBuilder func row(_ r: ListPanel.Row, focused: Bool) -> some View {
        HStack(spacing: 12) {
            if let img = r.image { Image(nsImage: img).resizable().frame(width: 34, height: 34) }
            else if let s = r.systemImage {
                SettingsIcon(systemImage: s, color: r.destructive ? Theme.danger : Theme.focus, size: 30)
                    .overlay(Theme.shape(7).strokeBorder(.white.opacity(focused ? 0.6 : 0), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.body.weight(.semibold))
                    .foregroundStyle(focused ? Color.white : r.destructive ? Theme.danger : Color.primary)
                if !r.detail.isEmpty {
                    Text(r.detail).font(.callout).lineLimit(2)
                        .foregroundStyle(focused ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            Spacer()
            if focused { Image(systemName: "chevron.right").font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.85)) }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.shape(9).fill(focused ? AnyShapeStyle(Theme.focus.gradient) : AnyShapeStyle(Color.clear)))
        .opacity(r.enabled ? 1 : 0.45)
        .contentShape(Rectangle())
    }
}

// MARK: Sectioned panel (options / settings)

struct SectionedPanelView: View {
    @ObservedObject var panel: SectionedPanel
    @Environment(\.colorScheme) var scheme

    static func icon(for section: String) -> (String, Color) {
        switch section.lowercased() {
        case let t where t.contains("game settings"): return ("slider.horizontal.3", .blue)
        case let t where t.contains("launch"): return ("play.fill", .green)
        case let t where t.contains("save"): return ("externaldrive.fill", .orange)
        case let t where t.contains("manage"): return ("shippingbox.fill", .gray)
        case let t where t.contains("status"): return ("checkmark.seal.fill", .green)
        case let t where t.contains("supported"): return ("square.grid.2x2.fill", .purple)
        case let t where t.contains("signing"): return ("signature", .gray)
        case let t where t.contains("display"): return ("display", .blue)
        case let t where t.contains("playing"): return ("bolt.fill", .orange)
        case let t where t.contains("home button"): return ("house.fill", .indigo)
        case let t where t.contains("data"): return ("folder.fill", .cyan)
        case let t where t.contains("connected"): return ("dot.radiowaves.left.and.right", .teal)
        case let t where t.contains("switch 2"): return ("antenna.radiowaves.left.and.right", .red)
        case let t where t.contains("button") || t.contains("control"): return ("gamecontroller.fill", .pink)
        default: return ("circle.fill", .gray)
        }
    }

    var body: some View {
        let _ = panel.tick
        PanelChrome(width: 980) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    if let img = loadImage(panel.artwork) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 52, height: 52).clipShape(Theme.shape(12))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(panel.title).font(.title2.bold())
                        if !panel.subtitle.isEmpty { Text(panel.subtitle).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
                HStack(alignment: .top, spacing: 18) {
                    sidebar
                    ScrollViewReader { proxy in
                        ScrollView {
                            GroupCard {
                                VStack(spacing: 0) {
                                    let rows = panel.visibleRows
                                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                                        rowView(r, focused: panel.column == 1 && panel.row == i)
                                            .id(r.id)
                                            .onTapGesture { panel.column = 1; panel.row = i; _ = panel.handle(.confirm) }
                                        if i < rows.count - 1 { Divider().padding(.leading, 16).opacity(0.6) }
                                    }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: .infinity)
                        .onChange(of: panel.row) { _, i in
                            let rows = panel.visibleRows
                            if rows.indices.contains(i) { withAnimation { proxy.scrollTo(rows[i].id, anchor: .center) } }
                        }
                    }
                }
                .frame(height: 540)
            }
        }
    }

    /// A System Settings–style sidebar. The selection is accent-filled while it has the focus, grey otherwise.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(panel.sections.enumerated()), id: \.element.id) { i, s in
                let selected = panel.section == i, active = selected && panel.column == 0
                let (symbol, color) = Self.icon(for: s.title)
                HStack(spacing: 10) {
                    SettingsIcon(systemImage: symbol, color: color, size: 24)
                    Text(s.title).font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(active ? Color.white : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7).padding(.horizontal, 9)
                .frame(width: 236, alignment: .leading)
                .background(Theme.shape(8).fill(active ? AnyShapeStyle(Theme.focus.gradient) : selected ? AnyShapeStyle(Theme.tile(scheme)) : AnyShapeStyle(Color.clear)))
                .contentShape(Rectangle())
                .onTapGesture { panel.section = i; panel.row = 0; panel.column = 0 }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.shape(14).fill(Theme.card(scheme)))
    }

    @ViewBuilder func rowView(_ r: SectionedPanel.Row, focused: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let s = r.status {
                Image(systemName: s == .ok ? "checkmark.circle.fill" : s == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(s == .ok ? Theme.playing : s == .warning ? Theme.warning : Theme.danger)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(r.label).font(.body.weight(.medium))
                if !r.note.isEmpty { Text(r.note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control(r, focused: focused)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.shape(Theme.rowRadius).fill(focused ? Theme.focus.opacity(0.14) : Color.clear))
        .overlay(Theme.shape(Theme.rowRadius).strokeBorder(Theme.focus, lineWidth: focused ? 2.5 : 0))
        .opacity(r.enabled ? 1 : 0.45)
        .contentShape(Rectangle())
    }

    /// The value side of a row, drawn as the matching Mac control (switch, pop-up button, stepper).
    @ViewBuilder func control(_ r: SectionedPanel.Row, focused: Bool) -> some View {
        switch r.kind {
        case .action:
            Image(systemName: "chevron.right").font(.callout.weight(.semibold)).foregroundStyle(.tertiary)
        case .info:
            Text(r.value).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing)
        case .toggle(let get, _):
            Toggle("", isOn: .constant(get())).toggleStyle(.switch).labelsHidden().allowsHitTesting(false)
        case .choice:
            HStack(spacing: 6) {
                if focused { Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(Theme.focus) }
                Text(panel.valueText(r)).font(.callout.weight(.medium))
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                if focused { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.focus) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.shape(7).fill(Theme.tile(scheme)))
        case .range:
            HStack(spacing: 10) {
                Image(systemName: "minus").font(.caption.weight(.bold)).foregroundStyle(focused ? Theme.focus : .secondary)
                Text(panel.valueText(r)).font(.callout.weight(.medium).monospacedDigit()).frame(minWidth: 44)
                Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(focused ? Theme.focus : .secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.shape(7).fill(Theme.tile(scheme)))
        }
    }
}

// MARK: Inspection report

struct ReportPanelView: View {
    @ObservedObject var panel: ReportPanel
    @Environment(\.colorScheme) var scheme
    var r: InspectionReport { panel.report }

    var body: some View {
        PanelChrome(width: 980) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    Group {
                        if let img = loadImage(r.icon) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
                        else { Image(systemName: "shippingbox.fill").font(.system(size: 46)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.tile(scheme)) }
                    }
                    .frame(width: 112, height: 112).clipShape(Theme.shape(22))
                    .overlay(Theme.shape(22).strokeBorder(Theme.separator(scheme), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(r.displayTitle).font(.title.bold())
                        verdict
                        Label(URL(fileURLWithPath: r.input).lastPathComponent + " · " + r.size.byteString + " · read in place, not modified", systemImage: "lock.doc")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if !r.issues.isEmpty { issues.id(1) }
                            facts.id(0)
                            packages.id(2)
                        }.padding(2)
                    }
                    .frame(height: 380)
                    .onChange(of: panel.scroll) { _, s in withAnimation { proxy.scrollTo(min(s, 2), anchor: .top) } }
                }
                HStack(spacing: 12) {
                    Spacer()
                    ForEach(Array(panel.buttons.enumerated()), id: \.element.id) { i, b in
                        PanelButton(label: b.label, focused: panel.focus == i, enabled: b.enabled)
                            .onTapGesture { if b.enabled { panel.focus = i; b.action() } }
                    }
                }
            }
        }
    }

    private var verdict: some View {
        let (text, color, icon): (String, Color, String) = {
            switch r.verdict {
            case "supported": return ("Supported build: matches the pinned backend's profile", Theme.playing, "checkmark.seal.fill")
            case "provisional": return ("Playable input, but not a registered build (provisional)", Theme.warning, "exclamationmark.triangle.fill")
            default: return ("Can't build this input yet", Theme.danger, "xmark.octagon.fill")
            }
        }()
        return Label(text, systemImage: icon).font(.callout.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func fact(_ k: String, _ v: String, note: String = "", warn: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(k).font(.callout).foregroundStyle(.secondary).frame(width: 180, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v).font(.callout.monospaced()).textSelection(.enabled)
                    if !note.isEmpty { Text(note).font(.caption).foregroundStyle(warn ? Theme.warning : .secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().padding(.leading, 14).opacity(0.5)
        }
    }

    private var facts: some View {
        GroupCard { VStack(alignment: .leading, spacing: 0) {
            fact("Title ID", r.title_id ?? "—")
            fact("Platform", r.platform ?? "—")
            fact("Input", r.kind == "nup" ? "NUP container v1" : (r.kind == "folder" ? "Dump folder (ExeFS/RomFS)" : (r.kind ?? "—")))
            fact("Layout", layoutText)
            fact("Package version", r.selected_version.map { "v\($0)" } ?? "—", note: "From the package record (NCM version)")
            if let (v, src) = r.verifiedVersion { fact("Verified version", v, note: "From \(src)") }
            if let l = r.labels.display_version {
                fact("Package label", l, note: "Typed by the packer. AsterNUP could not verify this against the game.", warn: true)
            }
            fact("Build ID (main)", r.build_ids["main"] ?? "—", note: r.build_ids_verified ? "Read from the module itself (SHA-256 checked)" : "Not verified")
            ForEach(r.build_ids.keys.filter { $0 != "main" }.sorted(), id: \.self) { k in fact("Build ID (\(k))", r.build_ids[k] ?? "") }
            fact("Profile", profileText)
            fact("Integrity", integrityText)
            if !r.dlc.isEmpty { fact("DLC", r.dlc.joined(separator: ", ")) }
        }.padding(.vertical, 4) }
    }

    private var layoutText: String {
        switch r.layout {
        case "base": return "Base game only"
        case "base+update": return "Base game + update (complete)"
        case "standalone-update": return "Standalone update (no base game in this input)"
        default: return r.layout ?? "—"
        }
    }

    private var profileText: String {
        guard let p = r.profile else { return "—" }
        switch p.match {
        case "exact": return "\(p.name ?? "") (\(p.id ?? "")): exact match, registered \(p.matched_version ?? "")"
        case "mismatch": return "\(p.name ?? ""): code differs from the registered build"
        case "unregistered": return "\(p.name ?? ""): registered builds are " + (p.registered ?? []).map { "\($0.version) (\($0.display ?? "?"))" }.joined(separator: ", ")
        default: return "No profile in the pinned backend"
        }
    }

    private var integrityText: String {
        switch r.integrity {
        case "toc-verified": return "Table of contents and code modules verified (SHA-256); game data not yet hashed"
        case "all-files-verified": return "Every file verified against its SHA-256"
        case "damaged": return "Damaged"
        case "not-applicable": return "Folder input (no hashes to check)"
        default: return "Not checked"
        }
    }

    private var issues: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(r.issues, id: \.self) { i in
                let tint = i.severity == "error" ? Theme.danger : i.severity == "warning" ? Theme.warning : Theme.focus
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: i.severity == "error" ? "xmark.octagon.fill" : i.severity == "warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.title3).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i.message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if !i.action.isEmpty { Text("Next step: \(i.action)").font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.shape(12).fill(tint.opacity(0.10)))
                .overlay(Theme.shape(12).strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
            }
        }
    }

    private var packages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Package contents").font(.headline).padding(.leading, 4)
            GroupCard { VStack(alignment: .leading, spacing: 6) { ForEach(r.packages, id: \.self) { p in
                HStack {
                    Text(p.kind.capitalized).frame(width: 80, alignment: .leading)
                    Text(verbatim: "v\(p.version)").font(.callout.monospaced()).frame(width: 110, alignment: .leading)
                    Text(p.bytes.byteString).frame(width: 90, alignment: .leading)
                    Text([p.has_exefs ? "ExeFS" : nil, p.has_romfs ? "RomFS" : nil, p.standalone_update ? "standalone" : nil].compactMap { $0 }.joined(separator: " + "))
                    if let l = p.labels?.display_version { Text("label \(l)").foregroundStyle(Theme.warning) }
                    if p.version == r.selected_version && (p.kind != "base" || r.selected_version == 0) {
                        Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.focus)
                    }
                    Spacer(minLength: 0)
                }.font(.callout)
            }}.padding(.horizontal, 14).padding(.vertical, 10) }
        }
    }
}

// MARK: Build progress

struct BuildPanelView: View {
    @ObservedObject var panel: BuildPanel
    @ObservedObject var job: BuildJob
    @Environment(\.colorScheme) var scheme
    var body: some View {
        PanelChrome(width: 860) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if let img = loadImage(job.iconPath ?? job.request.report.icon) { Image(nsImage: img).resizable().frame(width: 64, height: 64).clipShape(Theme.shape(14)) }
                    VStack(alignment: .leading) {
                        Text("Building \(job.request.appName)").font(.title2.bold())
                        Text(stateText).foregroundStyle(stateColor).font(.headline)
                    }
                    Spacer()
                }
                if job.state.isActive {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(job.stageCount > 0 ? "Stage \(job.stageIndex) of \(job.stageCount): \(job.stageName)" : job.stageName).font(.headline)
                        if !job.step.isEmpty { Text(job.step).font(.callout).foregroundStyle(Color.secondary) }
                        if let f = job.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                        HStack {
                            Text(job.countText).font(.caption.monospacedDigit())
                            Spacer()
                            if let eta = job.eta { Text("About \(Self.duration(eta)) left").font(.caption) }
                        }.foregroundStyle(Color.secondary)
                        if job.stageCount > 0 { ProgressView(value: Double(max(job.stageIndex - 1, 0)), total: Double(job.stageCount)).tint(.secondary) }
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(job.messages.suffix(80).enumerated()), id: \.offset) { i, m in
                                Text(m).font(.caption.monospaced()).foregroundStyle(m.hasPrefix("[RED]") ? Theme.danger : Color.secondary).textSelection(.enabled).id(i)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200).padding(12).background(Theme.shape(12).fill(Theme.card(scheme)))
                    .overlay(Theme.shape(12).strokeBorder(Theme.separator(scheme).opacity(0.5), lineWidth: 0.5))
                    .onChange(of: job.messages.count) { _, _ in proxy.scrollTo(min(job.messages.count, 80) - 1, anchor: .bottom) }
                }
                Text("Logs: \(job.logDir.path)").font(.caption).foregroundStyle(Color.secondary).textSelection(.enabled)
                HStack(spacing: 12) {
                    Spacer()
                    ForEach(Array(panel.buttons.enumerated()), id: \.offset) { i, b in
                        PanelButton(label: b, focused: panel.focus == i, destructive: job.state.isActive && i == 0)
                            .onTapGesture { panel.focus = i; _ = panel.handle(.confirm) }
                    }
                }
            }
        }
    }

    var stateText: String {
        switch job.state {
        case .preflight: return "Checking disk space and toolchain…"
        case .running: return "Building…"
        case .validating: return "Validating the generated app…"
        case .installing: return "Installing…"
        case .succeeded: return "Installed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled. Nothing was changed."
        }
    }
    var stateColor: Color {
        switch job.state { case .succeeded: return Theme.playing; case .failed: return Theme.danger; default: return Theme.focus }
    }
    static func duration(_ s: Double) -> String {
        s >= 3600 ? String(format: "%.0f h %.0f min", (s / 3600).rounded(.down), (s.truncatingRemainder(dividingBy: 3600) / 60).rounded())
            : s >= 60 ? "\(Int((s / 60).rounded())) min" : "\(Int(s)) s"
    }
}

struct BusyPanelView: View {
    @ObservedObject var panel: BusyPanel
    @Environment(\.colorScheme) var scheme
    var body: some View {
        PanelChrome(width: 480) {
            VStack(spacing: 16) {
                if let f = panel.fraction { ProgressView(value: f) } else { ProgressView().controlSize(.large) }
                Text(panel.title).font(.title3.bold()).multilineTextAlignment(.center)
                if !panel.detail.isEmpty { Text(panel.detail).font(.callout).foregroundStyle(Color.secondary).multilineTextAlignment(.center) }
            }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var input: InputRouter
    @Environment(\.colorScheme) var scheme
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            HomeView()
                .blur(radius: model.overlays.isEmpty ? 0 : 8)
                .scaleEffect(model.overlays.isEmpty ? 1 : 0.985)
                .allowsHitTesting(model.overlays.isEmpty)
            if !model.overlays.isEmpty {
                Color.black.opacity(scheme == .dark ? 0.40 : 0.18).ignoresSafeArea()
                    .onTapGesture { model.handle(.back) }
                    .transition(.opacity)
                ForEach(model.overlays) { o in
                    OverlayView(item: o).opacity(o.id == model.overlays.last?.id ? 1 : 0)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            VStack {
                if let b = model.banner { BannerView(banner: b).transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
            }
            .padding(.top, 64)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.banner)
            if dropTargeted { DropTargetView() }
        }
        .background { AmbientBackground(artwork: model.focusedEntry?.artworkPath) }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: model.overlays.count)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { model.handleDrop([url]) } }
                }
            }
            return true
        }
    }
}

struct DropTargetView: View {
    var body: some View {
        ZStack {
            Theme.shape(28).fill(.regularMaterial)
            Theme.shape(28).strokeBorder(Theme.focus, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            VStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 54, weight: .light)).foregroundStyle(Theme.focus)
                Text("Drop to add").font(.title.weight(.semibold))
                Text("A .nup, a dump folder or a game app").font(.title3).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .allowsHitTesting(false)
    }
}

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var input: InputRouter
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            topBar.padding(.horizontal, 44).padding(.top, 26)
            Spacer(minLength: 16)
            focusedTitle.padding(.horizontal, 64).frame(height: 64, alignment: .bottomLeading)
            tileRow.frame(height: 320)
            Spacer(minLength: 16)
            dockRow
            Spacer(minLength: 16)
            bottomBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
            Text("AsterNUP").font(.system(size: 20, weight: .semibold))
            if let st = model.backendStatus, !st.canBuild {
                Label(st.canInspect ? "Finish setup to build games" : "Finish setup", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(Theme.separator(scheme), lineWidth: 0.5))
                    .contentShape(Capsule())
                    .onTapGesture { model.showBackend() }
                    .help("Open Backend & Toolchain")
            }
            if let job = model.activeBuild, job.state.isActive {
                BuildChip(job: job).onTapGesture { model.showBuildPanel(job) }
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: input.controllerNames.isEmpty ? "gamecontroller" : "gamecontroller.fill")
                    .foregroundStyle(input.controllerNames.isEmpty ? Color.secondary : Theme.focus)
                    .help(input.controllerNames.isEmpty ? "No controller connected" : input.controllerNames.joined(separator: ", "))
                Text(model.clock, style: .time).monospacedDigit()
            }
            .font(.system(size: 17, weight: .medium))
        }
    }

    private var focusedTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let e = model.focusedEntry {
                Text(e.title).font(.system(size: 30, weight: .bold)).lineLimit(1)
                if let v = e.verifiedDisplayVersion { Text("Version \(v)").font(.title3).foregroundStyle(.secondary) }
                if sessions.isRunning(e.id) { PlayingBadge() }
            } else if model.zone == .row {
                Text("Add a game").font(.system(size: 30, weight: .bold))
            }
            Spacer()
        }
        .animation(nil, value: model.rowIndex)
    }

    private var tileRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    ForEach(Array(library.entries.enumerated()), id: \.element.id) { i, e in
                        GameTile(entry: e, focused: model.zone == .row && model.rowIndex == i,
                                 playing: sessions.isRunning(e.id),
                                 building: model.activeBuild?.state.isActive == true && model.activeBuild?.titleID == e.titleID)
                            .id(e.id)
                            .onTapGesture {
                                if model.zone == .row && model.rowIndex == i { model.play(e) } else { model.zone = .row; model.rowIndex = i }
                            }
                            .contextMenu {
                                Button(sessions.isRunning(e.id) ? "Resume" : "Start") { model.play(e) }
                                Button("Options…") { model.showOptions(e.id) }
                                if sessions.isRunning(e.id) { Button("Close Software…") { model.confirmClose(e) } }
                            }
                    }
                    AddTile(focused: model.zone == .row && model.rowIndex == library.entries.count)
                        .id("add")
                        .onTapGesture { model.zone = .row; model.rowIndex = library.entries.count; model.showAddGame() }
                }
                .padding(.horizontal, 64).padding(.vertical, 34)
            }
            .onChange(of: model.rowIndex) { _, i in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    if library.entries.indices.contains(i) { proxy.scrollTo(library.entries[i].id, anchor: .center) } else { proxy.scrollTo("add", anchor: .center) }
                }
            }
        }
    }

    private var dockRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 22) {
                ForEach(Array(model.dock.enumerated()), id: \.element.id) { i, d in
                    DockButton(item: d, focused: model.zone == .dock && model.dockIndex == i, destructive: d.id == "exit")
                        .onTapGesture { model.zone = .dock; model.dockIndex = i; model.activateDock(d.id) }
                }
            }
            Text(model.zone == .dock ? model.dock[model.dockIndex].label : " ")
                .font(.callout.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            Label(input.controllerNames.first ?? "Keyboard & mouse", systemImage: "gamecontroller")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            ForEach(model.hints, id: \.self) { h in
                HStack(spacing: 6) { ButtonGlyph(label: h.button); Text(h.label).font(.callout.weight(.medium)) }
            }
        }
        .padding(.horizontal, 44).frame(height: 54)
        .background(alignment: .top) { Rectangle().fill(Theme.separator(scheme)).frame(height: 0.5).opacity(0.6) }
    }
}

struct DockButton: View {
    let item: AppModel.DockItem
    let focused: Bool
    var destructive = false
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Image(systemName: item.systemImage)
            .font(.system(size: 21, weight: .medium))
            .frame(width: 56, height: 56)
            .foregroundStyle(focused ? Color.white : destructive ? Theme.danger : Color.primary)
            .background {
                if focused { Circle().fill((destructive ? Theme.danger : Theme.focus).gradient) }
                else { Circle().fill(.regularMaterial).overlay(Circle().strokeBorder(Theme.separator(scheme), lineWidth: 0.5)) }
            }
            .scaleEffect(focused ? 1.12 : 1)
            .shadow(color: .black.opacity(focused ? 0.25 : 0.08), radius: focused ? 12 : 3, y: focused ? 6 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: focused)
            .help(item.label)
            .contentShape(Circle())
    }
}

struct GameTile: View {
    let entry: GameEntry
    let focused: Bool
    let playing: Bool
    let building: Bool
    @Environment(\.colorScheme) var scheme
    static let side: CGFloat = 236

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let img = loadImage(entry.artworkPath) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Theme.focus.opacity(0.85), Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Text(entry.title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            .multilineTextAlignment(.center).padding(18))
                }
            }
            .frame(width: Self.side, height: Self.side)
            .background(Theme.tile(scheme))
            .clipShape(Theme.shape(Theme.tileRadius))
            // A hairline edge and a glassy highlight, like a lifted card on Apple TV.
            .overlay(Theme.shape(Theme.tileRadius).strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.5), lineWidth: 0.5))
            .overlay(
                LinearGradient(colors: [.white.opacity(focused ? 0.22 : 0), .clear], startPoint: .topLeading, endPoint: .center)
                    .clipShape(Theme.shape(Theme.tileRadius)).allowsHitTesting(false)
            )
            .saturation(entry.isInstalled || playing ? 1 : 0.2)
            .opacity(entry.isInstalled || playing ? 1 : 0.6)
            Group {
                if playing { PlayingBadge() }
                else if building { TileBadge(text: "Building", systemImage: "hammer.fill", tint: Theme.warning) }
                else if !entry.isInstalled { TileBadge(text: "Not installed", systemImage: "exclamationmark.circle", tint: nil) }
            }
            .padding(12)
        }
        .frame(width: Self.side, height: Self.side)
        .shadow(color: .black.opacity(focused ? 0 : 0.10), radius: 6, y: 3)
        .focusRing(focused, radius: Theme.tileRadius, lift: true)
    }
}

struct AddTile: View {
    let focused: Bool
    @Environment(\.colorScheme) var scheme
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .medium))
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.tile(scheme)))
            Text("Add a game").font(.headline)
        }
        .foregroundStyle(.secondary)
        .frame(width: GameTile.side, height: GameTile.side)
        .background(Theme.shape(Theme.tileRadius).fill(.regularMaterial))
        .overlay(Theme.shape(Theme.tileRadius).strokeBorder(Theme.separator(scheme), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
        .focusRing(focused, radius: Theme.tileRadius, lift: true)
    }
}

struct TileBadge: View {
    let text: String
    let systemImage: String
    let tint: Color?
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
            .background {
                if let tint { Capsule().fill(tint.gradient) } else { Capsule().fill(.thickMaterial) }
            }
    }
}

struct PlayingBadge: View {
    var body: some View { TileBadge(text: "Playing", systemImage: "play.fill", tint: Theme.playing) }
}

struct BuildChip: View {
    @ObservedObject var job: BuildJob
    @Environment(\.colorScheme) var scheme
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("\(job.request.appName): \(job.stageName)\(job.fraction.map { " \(Int($0 * 100))%" } ?? "")").font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Theme.separator(scheme), lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

/// A notification-style banner (material, app-style icon, title and detail).
struct BannerView: View {
    let banner: Banner
    @Environment(\.colorScheme) var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: banner.style == .error ? "xmark.octagon.fill" : banner.style == .success ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(banner.style == .error ? Theme.danger : banner.style == .success ? Theme.playing : Theme.focus)
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.text).font(.headline)
                if !banner.detail.isEmpty { Text(banner.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: 640)
        .background(Theme.shape(18).fill(.regularMaterial))
        .overlay(Theme.shape(18).strokeBorder(Theme.separator(scheme), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .fixedSize(horizontal: false, vertical: true)
    }
}

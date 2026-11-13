import AppKit
import SwiftUI

@main
enum AsterNUPMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var model: AppModel!
    /// Files macOS hands over before the model exists (opening a .nup launches AsterNUP and delivers it first).
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            model = AppModel()
            let root = RootView()
                .environmentObject(model)
                .environmentObject(model.library)
                .environmentObject(model.sessions)
                .environmentObject(model.input)
                .frame(minWidth: 1100, minHeight: 700)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.title = "AsterNUP"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.collectionBehavior = [.fullScreenPrimary]
            window.contentView = NSHostingView(rootView: root)
            window.setFrameAutosaveName("AsterNUPHome")
            window.center()
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
            model.window = window
            model.applySettings()
            buildMenu()
            NSApp.activate(ignoringOtherApps: true)
            let args = ProcessInfo.processInfo.arguments
            if model.settings.startFullscreen && !args.contains("--windowed") { window.toggleFullScreen(nil) }
            if let i = args.firstIndex(of: "--import"), args.indices.contains(i + 1) { model.importDump(URL(fileURLWithPath: args[i + 1])) }
            if !pendingURLs.isEmpty { model.handleDrop(pendingURLs); pendingURLs = [] }
            if let i = args.firstIndex(of: "--ui-test"), args.indices.contains(i + 1) {
                UITestHarness.run(script: URL(fileURLWithPath: args[i + 1]), model: model, window: window)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            if let model { model.bringForward(); model.popAll(); model.handleDrop(urls) } else { pendingURLs += urls }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated { model?.objectWillChange.send() }
    }

    static let repository = URL(string: "https://github.com/asterpolaris/AsterNUP")!

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About AsterNUP", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Backend & Toolchain…", action: #selector(showBackend), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services"); NSApp.servicesMenu = services.submenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide AsterNUP", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AsterNUP", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "Library")
        file.addItem(withTitle: "Import a Dump…", action: #selector(importDump), keyEquivalent: "o").target = self
        file.addItem(withTitle: "Add an Existing Game App…", action: #selector(chooseApp), keyEquivalent: "O").target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Controllers…", action: #selector(showControllers), keyEquivalent: "").target = self
        fileItem.submenu = file

        // Edit: lets ⌘C copy selectable text (title IDs, build IDs, log paths) from the panels.
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        let fs = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = view

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(.separator())
        win.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Getting Started", action: #selector(openDoc(_:)), keyEquivalent: "?").representedObject = "docs/GETTING_STARTED.md"
        help.addItem(withTitle: "Adding Games", action: #selector(openDoc(_:)), keyEquivalent: "").representedObject = "docs/ADDING_GAMES.md"
        help.addItem(withTitle: "Controllers", action: #selector(openDoc(_:)), keyEquivalent: "").representedObject = "docs/CONTROLLERS.md"
        help.addItem(withTitle: "Smoothest Play", action: #selector(openDoc(_:)), keyEquivalent: "").representedObject = "docs/PERFORMANCE.md"
        help.addItem(withTitle: "Troubleshooting", action: #selector(openDoc(_:)), keyEquivalent: "").representedObject = "docs/TROUBLESHOOTING.md"
        help.addItem(.separator())
        help.addItem(withTitle: "Acknowledgements", action: #selector(openDoc(_:)), keyEquivalent: "").representedObject = "ACKNOWLEDGEMENTS.md"
        help.addItem(withTitle: "Report an Issue…", action: #selector(openDoc(_:)), keyEquivalent: "").representedObject = "issues/new/choose"
        for item in help.items { item.target = self }
        helpItem.submenu = help
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    @objc func openDoc(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = path.hasSuffix(".md") ? Self.repository.appendingPathComponent("blob/main/\(path)") : Self.repository.appendingPathComponent(path)
        NSWorkspace.shared.open(url)
    }

    @objc func showAbout() {
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        credits.append(NSAttributedString(string: "A controller-first game library for Apple silicon Macs.\n\nGames are built by ", attributes: body))
        credits.append(NSAttributedString(string: "nxnative", attributes: body.merging([.link: URL(string: "https://github.com/seedds/nxnative")!]) { $1 }))
        credits.append(NSAttributedString(string: ". Thanks to everyone listed in the ", attributes: body))
        credits.append(NSAttributedString(string: "acknowledgements", attributes: body.merging([.link: Self.repository.appendingPathComponent("blob/main/ACKNOWLEDGEMENTS.md")]) { $1 }))
        credits.append(NSAttributedString(string: ".\n\nNot affiliated with Nintendo or any game publisher.", attributes: body))
        let centered = NSMutableParagraphStyle(); centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .init(rawValue: "Copyright"): "MIT License · AsterNUP contributors"])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func importDump() { MainActor.assumeIsolated { model.popAll(); model.showDumpPicker() } }
    @objc func chooseApp() { MainActor.assumeIsolated { model.popAll(); model.showAppPicker() } }
    @objc func showBackend() { MainActor.assumeIsolated { model.popAll(); model.showBackend() } }
    @objc func showSettings() { MainActor.assumeIsolated { model.popAll(); model.showHomeSettings() } }
    @objc func showControllers() { MainActor.assumeIsolated { model.popAll(); model.showControllers() } }
}

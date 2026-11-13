import AppKit
import GameController
import Carbon.HIToolbox

enum NavAction: Equatable {
    case up, down, left, right
    case confirm      // A / Return / Space
    case back         // B / Escape
    case x            // X / "x": close software
    case y            // Y / "y"
    case plus         // + / "o": options
    case minus        // − / "i": info
    case shoulderL, shoulderR   // L / R / Tab: switch between the tile row and the dock
    case home
}

/// Controller, keyboard and global-shortcut input. Navigation goes to the active surface only while AsterNUP is frontmost;
/// HOME is watched in the background too, so it can bring the launcher forward over a running game.
final class InputRouter: ObservableObject {
    struct ControllerInfo: Hashable {
        var name: String; var family: String; var profile: String; var source: String; var faceMapping: String
    }
    @Published private(set) var controllerNames: [String] = []
    @Published private(set) var controllers: [ControllerInfo] = []
    let hid = HIDGamepads()
    var onAction: ((NavAction) -> Void)?
    var onHome: (() -> Void)?
    var settings = HomeSettings() {
        didSet {
            applySettings()
            if oldValue.buttonLayout != settings.buttonLayout { GCController.controllers().forEach(configure); refreshNames() }
        }
    }

    private var held: NavAction?
    private var repeatTimer: Timer?
    private var stickDirection: [ObjectIdentifier: NavAction] = [:]
    private var homeDown: [ObjectIdentifier: Date] = [:]
    private var minusDown = Set<ObjectIdentifier>(), plusDown = Set<ObjectIdentifier>()
    private var keyMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    /// AsterNUP is the active app. While a game is in front the launcher only listens for HOME.
    private var foreground = true
    private static weak var current: InputRouter?

    init() {
        InputRouter.current = self
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let self, let c = n.object as? GCController { self.configure(c); if !self.foreground { self.quiet(c) } }
            self?.refreshNames()
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.stopRepeat(); self?.refreshNames()
        }
        // While a game plays, AsterNUP drops every controller handler except HOME and − / +, and raw HID delivers only HOME.
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setForeground(false) }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setForeground(true) }
        GCController.controllers().forEach(configure)
        GCController.startWirelessControllerDiscovery {}
        refreshNames()
        installKeyboard()
        installHotKeyHandler()
        hid.onAction = { [weak self] a in if self?.settings.hidFallback == true { self?.dispatch(a) } }
        hid.onHomeTap = { [weak self] in if self?.settings.controllerHome == true && self?.settings.hidFallback == true { self?.onHome?() } }
        hid.onDevicesChanged = { [weak self] in DispatchQueue.main.async { self?.refreshNames() } }
    }

    private func setForeground(_ fg: Bool) {
        guard fg != foreground else { return }
        foreground = fg
        hid.setBackground(!fg)
        if fg {
            GCController.controllers().forEach(configure)
        } else {
            stopRepeat(); stickDirection.removeAll()
            GCController.controllers().forEach(quiet)
        }
    }

    /// Remove the handlers that fire on every stick and d-pad report; HOME and − / + stay.
    private func quiet(_ c: GCController) {
        if let g = c.extendedGamepad {
            g.dpad.valueChangedHandler = nil
            g.leftThumbstick.valueChangedHandler = nil
            for b in [g.buttonA, g.buttonB, g.buttonX, g.buttonY, g.leftShoulder, g.rightShoulder] { b.pressedChangedHandler = nil }
        } else if let m = c.microGamepad {
            m.dpad.valueChangedHandler = nil
            m.buttonA.pressedChangedHandler = nil
            m.buttonX.pressedChangedHandler = nil
        }
    }

    private func refreshNames() {
        var list: [ControllerInfo] = GCController.controllers().compactMap { c in
            let profile = c.extendedGamepad != nil ? "Extended gamepad" : c.microGamepad != nil ? "Micro gamepad (single Joy-Con / remote)" : nil
            guard let profile else { return nil }
            return ControllerInfo(name: c.vendorName ?? "Controller", family: Self.family(of: c), profile: profile, source: "GameController",
                                  faceMapping: c.extendedGamepad.map { faceDescription($0) } ?? "A confirms, X goes back")
        }
        for d in hid.devices.values where !d.claimedByGameController {
            list.append(ControllerInfo(name: d.name, family: d.vendorID == HIDGamepads.nintendoVendor ? "Nintendo" : "Other",
                                       profile: "Raw HID gamepad (\(d.transport))", source: settings.hidFallback ? "HID" : "HID (off)",
                                       faceMapping: d.vendorID == HIDGamepads.nintendoVendor ? "A confirms, B goes back (Nintendo order)" : "Button 1 confirms, 2 goes back"))
        }
        controllers = list
        controllerNames = list.map(\.name)
    }

    static func family(of c: GCController) -> String {
        let s = ((c.vendorName ?? "") + " " + c.productCategory).lowercased()
        if s.contains("joy-con") || s.contains("pro controller") || s.contains("nintendo") || s.contains("switch") || s.contains("snes") || s.contains("n64") || s.contains("famicom") { return "Nintendo" }
        if s.contains("dualsense") || s.contains("dualshock") { return "PlayStation" }
        if s.contains("xbox") { return "Xbox" }
        return "Other"
    }

    /// Which physical button confirms. Apple names extended-gamepad buttons by position (buttonA is the bottom one);
    /// each button's SF Symbol tells its printed label, so "by label" follows Nintendo's layout (A on the right confirms).
    private func faceActions(_ g: GCExtendedGamepad) -> [(GCControllerButtonInput, NavAction)] {
        let positional: [(GCControllerButtonInput, NavAction)] = [(g.buttonA, .confirm), (g.buttonB, .back), (g.buttonX, .x), (g.buttonY, .y)]
        guard settings.buttonLayout == .byLabel else { return positional }
        var out: [(GCControllerButtonInput, NavAction)] = []
        for b in [g.buttonA, g.buttonB, g.buttonX, g.buttonY] {
            let sym = (b.sfSymbolsName ?? "").lowercased()
            if sym.hasPrefix("a.") { out.append((b, .confirm)) }
            else if sym.hasPrefix("b.") { out.append((b, .back)) }
            else if sym.hasPrefix("x.") && !sym.hasPrefix("xmark") { out.append((b, .x)) }
            else if sym.hasPrefix("y.") { out.append((b, .y)) }
        }
        return Set(out.map { $0.1 }).count == 4 ? out : positional   // PlayStation symbols (✕ ○ □ △) fall back to position
    }

    private func faceDescription(_ g: GCExtendedGamepad) -> String {
        let f = faceActions(g)
        func name(_ b: GCControllerButtonInput) -> String {
            b === g.buttonA ? "bottom" : b === g.buttonB ? "right" : b === g.buttonX ? "left" : "top"
        }
        let c = f.first { $0.1 == .confirm }.map { name($0.0) } ?? "?"
        let k = f.first { $0.1 == .back }.map { name($0.0) } ?? "?"
        return "Confirm: \(c) button, Back: \(k) button"
    }

    // MARK: Controllers

    private func configure(_ c: GCController) {
        if c.extendedGamepad == nil, let m = c.microGamepad { configureMicro(m, c); return }
        guard let g = c.extendedGamepad else { return }
        let key = ObjectIdentifier(c)
        func press(_ b: GCControllerButtonInput?, _ a: NavAction) {
            b?.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { self?.dispatch(a) } }
        }
        for (b, a) in faceActions(g) { press(b, a) }
        press(g.leftShoulder, .shoulderL); press(g.rightShoulder, .shoulderR)
        g.buttonMenu.pressedChangedHandler = { [weak self] _, _, p in
            guard let self else { return }
            if p { self.plusDown.insert(key); if self.checkCombo(key) { return }; self.dispatch(.plus) } else { self.plusDown.remove(key) }
        }
        g.buttonOptions?.pressedChangedHandler = { [weak self] _, _, p in
            guard let self else { return }
            if p { self.minusDown.insert(key); if self.checkCombo(key) { return }; self.dispatch(.minus) } else { self.minusDown.remove(key) }
        }
        // Directions with key-repeat
        g.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.direction(from: x, y, threshold: 0.5, source: ObjectIdentifier(g.dpad))
        }
        g.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.direction(from: x, y, threshold: 0.55, source: ObjectIdentifier(g.leftThumbstick))
        }
        // HOME: ask macOS not to take it, act on a short press; a long hold stays the game's (nxnative's quit prompt).
        if let home = g.buttonHome {
            home.preferredSystemGestureState = .disabled
            home.pressedChangedHandler = { [weak self] _, _, pressed in
                guard let self, self.settings.controllerHome else { return }
                if pressed { self.homeDown[key] = Date() }
                else if let t = self.homeDown.removeValue(forKey: key), Date().timeIntervalSince(t) < 0.8 {
                    DispatchQueue.main.async { self.onHome?() }
                }
            }
        }
    }

    /// A single Joy-Con held sideways (or another micro gamepad): its stick/d-pad moves, the right face button confirms, the bottom one goes back.
    private func configureMicro(_ m: GCMicroGamepad, _ c: GCController) {
        m.allowsRotation = true
        m.reportsAbsoluteDpadValues = true
        m.buttonA.pressedChangedHandler = { [weak self] _, _, p in if p { self?.dispatch(.confirm) } }
        m.buttonX.pressedChangedHandler = { [weak self] _, _, p in if p { self?.dispatch(.back) } }
        m.buttonMenu.pressedChangedHandler = { [weak self] _, _, p in if p { self?.dispatch(.plus) } }
        m.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.direction(from: x, y, threshold: 0.55, source: ObjectIdentifier(m.dpad))
        }
        if let home = c.physicalInputProfile.buttons[GCInputButtonHome] {
            home.preferredSystemGestureState = .disabled
            let key = ObjectIdentifier(c)
            home.pressedChangedHandler = { [weak self] _, _, pressed in
                guard let self, self.settings.controllerHome else { return }
                if pressed { self.homeDown[key] = Date() }
                else if let t = self.homeDown.removeValue(forKey: key), Date().timeIntervalSince(t) < 0.8 { DispatchQueue.main.async { self.onHome?() } }
            }
        }
    }

    private func checkCombo(_ key: ObjectIdentifier) -> Bool {
        guard settings.minusPlusHome, minusDown.contains(key), plusDown.contains(key) else { return false }
        DispatchQueue.main.async { self.onHome?() }
        return true
    }

    private func direction(from x: Float, _ y: Float, threshold: Float, source: ObjectIdentifier) {
        guard foreground else { return }
        var d: NavAction?
        if abs(x) > abs(y) { if x > threshold { d = .right } else if x < -threshold { d = .left } }
        else { if y > threshold { d = .up } else if y < -threshold { d = .down } }
        let prev = stickDirection[source]
        guard d != prev else { return }
        stickDirection[source] = d
        if let d { startRepeat(d) } else if held == prev { stopRepeat() }
    }

    private func startRepeat(_ a: NavAction) {
        stopRepeat()
        held = a
        dispatch(a)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
                guard let self, let h = self.held else { return }
                self.dispatch(h)
            }
        }
    }

    private func stopRepeat() { held = nil; repeatTimer?.invalidate(); repeatTimer = nil }

    private func dispatch(_ a: NavAction) {
        DispatchQueue.main.async {
            guard NSApp.isActive else { return }   // inputs belong to the frontmost surface (the game, while it is in front)
            self.onAction?(a)
        }
    }

    // MARK: Keyboard (equivalents for every controller action)

    private func installKeyboard() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.modifierFlags.contains(.command) { return e }   // menu shortcuts
            let a: NavAction?
            switch Int(e.keyCode) {
            case kVK_UpArrow: a = .up
            case kVK_DownArrow: a = .down
            case kVK_LeftArrow: a = .left
            case kVK_RightArrow: a = .right
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: a = .confirm
            case kVK_Escape, kVK_Delete: a = .back
            case kVK_Tab: a = e.modifierFlags.contains(.shift) ? .shoulderL : .shoulderR
            case kVK_ANSI_X: a = .x
            case kVK_ANSI_Y: a = .y
            case kVK_ANSI_O, kVK_ANSI_Equal: a = .plus
            case kVK_ANSI_I, kVK_ANSI_Minus: a = .minus
            default: a = nil
            }
            guard let a else { return e }
            self.onAction?(a)
            return nil
        }
    }

    // MARK: Global HOME shortcut (works while a game is frontmost; no Accessibility permission needed)

    private func installHotKeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { InputRouter.current?.onHome?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func applySettings() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        let combo: (Int, Int)?
        switch settings.homeShortcut {
        case .ctrlOptH: combo = (kVK_ANSI_H, controlKey | optionKey)
        case .ctrlOptCmdH: combo = (kVK_ANSI_H, controlKey | optionKey | cmdKey)
        case .f13: combo = (kVK_F13, 0)
        case .off: combo = nil
        }
        guard let (code, mods) = combo else { return }
        let id = EventHotKeyID(signature: OSType(0x4153_4E50), id: 1)   // 'ASNP'
        RegisterEventHotKey(UInt32(code), UInt32(mods), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

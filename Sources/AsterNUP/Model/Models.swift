import Foundation

/// One tile in the library: a game AsterNUP built from a dump (managed) or an existing macOS game app.
struct GameEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case managed, external }

    var id: UUID = UUID()
    var kind: Kind
    var title: String
    var titleID: String?
    var platform: String?
    /// NCM package version that was built (e.g. 131072). Verified from the container record.
    var packageVersion: Int?
    /// Display version typed by the packer into the NUP. A label, never verified.
    var packageLabelVersion: String?
    /// Display version from the console control data (NACP) or the backend profile's registered build.
    var verifiedDisplayVersion: String?
    /// Build IDs read from the code modules themselves (first 16 bytes of each ModuleId).
    var buildIDs: [String: String] = [:]
    var profileMatch: String?
    var backendID: String?
    var backendCommit: String?
    /// The dump that was imported. AsterNUP only ever reads it.
    var sourcePath: String?
    var appPath: String?
    var bundleID: String?
    var artworkPath: String?
    var saveFolder: String?
    var logPath: String?
    var addedAt: Date = Date()
    var lastPlayed: Date?
    var lastBuild: BuildRecord?
    /// For external apps: launch arguments and environment the player configured.
    var launchArguments: [String] = []
    var launchEnvironment: [String: String] = [:]

    var appURL: URL? { appPath.map { URL(fileURLWithPath: $0) } }
    var isInstalled: Bool { appPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }
}

struct BuildRecord: Codable, Hashable {
    var command: [String]
    var backendCommit: String
    var toolchain: String
    var startedAt: Date
    var finishedAt: Date?
    var outcome: String
    var workDir: String
    var logDir: String
}

/// Launcher-wide preferences.
struct HomeSettings: Codable, Equatable {
    enum Appearance: String, Codable, CaseIterable { case system, light, dark }
    enum HomeShortcut: String, Codable, CaseIterable {
        case ctrlOptH = "⌃⌥H", ctrlOptCmdH = "⌃⌥⌘H", f13 = "F13", off = "Off"
    }
    /// How A/B/X/Y act: by the label printed on the button (Nintendo: A on the right confirms) or by position (bottom confirms).
    enum ButtonLayout: String, Codable, CaseIterable { case byLabel = "By label", byPosition = "By position" }
    var appearance: Appearance = .system
    var startFullscreen: Bool = true
    var homeShortcut: HomeShortcut = .ctrlOptH
    /// Short press on the controller's HOME button brings AsterNUP forward. Holding it is left to the game (nxnative's quit prompt).
    var controllerHome: Bool = true
    /// Fallback for controllers whose HOME button macOS keeps: press − and + together.
    var minusPlusHome: Bool = false
    var buttonLayout: ButtonLayout = .byLabel
    /// Read gamepads macOS pairs but GameController does not list, as raw HID.
    var hidFallback: Bool = true
    /// Before starting an nxnative game, point out what would cost it frames (apps holding memory, Low Power Mode, heat).
    var checkBeforePlaying: Bool = true
    var backupFolder: String = (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/AsterNUP Backups")).path

    init() {}
    /// Tolerant decoding: settings saved by an older AsterNUP keep their values and get defaults for new keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HomeSettings()
        appearance = (try? c.decode(Appearance.self, forKey: .appearance)) ?? d.appearance
        startFullscreen = (try? c.decode(Bool.self, forKey: .startFullscreen)) ?? d.startFullscreen
        homeShortcut = (try? c.decode(HomeShortcut.self, forKey: .homeShortcut)) ?? d.homeShortcut
        controllerHome = (try? c.decode(Bool.self, forKey: .controllerHome)) ?? d.controllerHome
        minusPlusHome = (try? c.decode(Bool.self, forKey: .minusPlusHome)) ?? d.minusPlusHome
        buttonLayout = (try? c.decode(ButtonLayout.self, forKey: .buttonLayout)) ?? d.buttonLayout
        hidFallback = (try? c.decode(Bool.self, forKey: .hidFallback)) ?? d.hidFallback
        checkBeforePlaying = (try? c.decode(Bool.self, forKey: .checkBeforePlaying)) ?? d.checkBeforePlaying
        backupFolder = (try? c.decode(String.self, forKey: .backupFolder)) ?? d.backupFolder
    }
}

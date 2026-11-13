import Foundation

// MARK: - The common interface every game backend implements

protocol GameBackend: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var pin: BackendPin { get }

    /// Checkout, pinned revision and toolchain checks.
    func status() async -> BackendStatus
    /// Fetch (or move) the backend checkout to the pinned revision.
    func preparePinnedCheckout(log: @escaping (String) -> Void) async throws
    /// Game profiles the pinned backend ships.
    func supportedProfiles() -> [GameProfile]
    /// Inspect a package or dump folder in place. Never writes to it.
    func inspect(_ input: URL, verifyAllHashes: Bool, package: String?, progress: @escaping (String, Double?) -> Void) async throws -> InspectionReport
    /// Start a build. The job stages its output and validates it; registering is the caller's job.
    func makeBuildJob(for request: BuildRequest) -> BuildJob
    /// Settings a built app offers, from its own launcher.json.
    func settings(forApp app: URL) -> LauncherSettings?
    func savedChoice(_ env: String, bundleID: String) -> String?
    func setSavedChoice(_ env: String, value: String?, bundleID: String)
    func saveFolder(titleID: String) -> URL
    func logFile(titleID: String) -> URL
    /// Environment AsterNUP adds when it starts a managed game.
    func launchEnvironment(for entry: GameEntry) -> [String: String]
}

struct BackendPin: Codable, Hashable {
    struct Requires: Codable, Hashable {
        var macos: String
        var xcode: String
        var metal_toolchain: String
        var python: String
        var brew: [String]
        var pip: [String]
    }
    var id: String
    var name: String
    var repository: String
    var commit: String
    var commit_date: String
    var requires: Requires
    var build_command: [String]
}

struct ToolCheck: Identifiable, Hashable {
    enum State: Hashable { case ok, warning, missing }
    var id: String { name }
    var name: String
    var state: State
    var detail: String
    var fix: String = ""
}

struct BackendStatus: Hashable {
    var checkoutPath: String
    var checkoutCommit: String?
    var pinnedCommit: String
    var checks: [ToolCheck]
    var canInspect: Bool
    var canBuild: Bool
    var summary: String {
        if canBuild { return "Ready to build games" }
        if canInspect { return "Can inspect dumps; building needs: " + checks.filter { $0.state == .missing }.map(\.name).joined(separator: ", ") }
        return "Backend not set up"
    }
}

struct GameProfile: Identifiable, Hashable {
    var id: String { titleID }
    var titleID: String
    var name: String
    var package: String
    var builds: [String]   // "v131072 (display)"
    var readme: URL?
}

// MARK: - Inspection report (decoded from asternup_inspect.py)

struct InspectionReport: Codable, Hashable {
    struct Issue: Codable, Hashable { var severity: String; var message: String; var action: String }
    struct Labels: Codable, Hashable {
        var display_version: String?; var name: String?; var publisher: String?; var source_dump: String?; var build_id: String?
    }
    struct Control: Codable, Hashable { var name: String?; var publisher: String?; var display_version: String?; var source: String? }
    struct Package: Codable, Hashable {
        var index: Int; var kind: String; var title_id: String?; var version: Int; var version_text: String
        var standalone_update: Bool; var has_exefs: Bool; var has_romfs: Bool; var bytes: Int64
        var labels: Labels?
    }
    struct Registered: Codable, Hashable { var version: String; var display: String?; var modules: [String: String] }
    struct Marker: Codable, Hashable { var path: String; var present: Bool? }
    struct Profile: Codable, Hashable {
        var found: Bool; var match: String
        var id: String?; var name: String?; var dir: String?; var package: String?; var readme: String?
        var registered: [Registered]?; var matched_version: String?; var display_version: String?
        var mismatches: [String]?; var romfs_marker: Marker?
    }

    var input: String
    var kind: String?
    var size: Int64
    var title_id: String?
    var platform: String?
    var labels: Labels
    var nacp: Control?
    var icon: String?
    var packages: [Package]
    var dlc: [String]
    var selected_version: Int?
    var layout: String?
    var playable: Bool
    var verdict: String
    var build_ids: [String: String]
    var build_ids_verified: Bool
    var profile: Profile?
    var integrity: String
    var issues: [Issue]
    var uuid: String?

    var errors: [Issue] { issues.filter { $0.severity == "error" } }
    var displayTitle: String {
        if let n = nacp?.name, !n.isEmpty { return n }
        if let n = profile?.name, !n.isEmpty { return n }
        if let n = labels.name, !n.isEmpty { return n }
        return URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
    }
    /// Display version AsterNUP can stand behind, and where it came from.
    var verifiedVersion: (String, String)? {
        if profile?.match == "exact", let d = profile?.display_version, d != "?" { return (d, "registered build \(profile?.matched_version ?? "")") }
        if let d = nacp?.display_version, !d.isEmpty { return (d, "console control data (\(nacp?.source ?? "NACP"))") }
        return nil
    }
}

// MARK: - Build

struct BuildRequest {
    var input: URL
    var report: InspectionReport
    var appName: String
    var signingIdentity: String?
    var teamID: String?
    var package: String?
    var existingEntry: GameEntry?
}

// MARK: - launcher.json (nxnative docs/launcher.schema.json, schema 1)

struct LauncherSettings: Decodable {
    struct Setting: Decodable, Identifiable {
        var id: String { env }
        var env: String
        var kind: String
        var section: String?
        var label: String
        var note: String?
        var `default`: String?
        var options: [[String]]?
        var min: Double?
        var max: Double?
        var step: Double?
        var on: String?
        var off: String?
        var level: String?
        var needs: String?
    }
    var schema: Int?
    var game: String?
    var settings: [Setting]
}

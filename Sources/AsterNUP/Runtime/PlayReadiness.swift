import AppKit
import Darwin

/// What on this Mac would cost an nxnative game frames, checked just before it starts.
///
/// nxnative games keep most of the Mac's memory (Ocarina of Time: 10.9–11.4 GB resident, ~9.4 GB wired on a 16 GB Mac,
/// per its game note), so memory other apps hold turns into swapping and stutter. Low Power Mode lowers the GPU's
/// clocks, and a Mac that is already hot throttles. AsterNUP can't change those settings; it can name them and quit
/// the apps the player picks.
struct PlayReadiness {
    struct HeavyApp: Identifiable {
        let app: NSRunningApplication
        let name: String
        /// The app's own footprint plus its helper processes' (browser tabs, Electron renderers).
        let bytes: UInt64
        var id: pid_t { app.processIdentifier }
    }

    /// Roughly what an nxnative game plus macOS itself need (game ~11 GB, system ~4 GB).
    static let gameAndSystemBytes: UInt64 = 15 << 30
    /// Apps smaller than this aren't worth listing.
    static let listThreshold: UInt64 = 200 << 20

    var physical: UInt64 = ProcessInfo.processInfo.physicalMemory
    var heavyApps: [HeavyApp] = []
    /// Footprint of every regular app other than AsterNUP, Finder and running games.
    var othersBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    var thermal = ProcessInfo.processInfo.thermalState

    /// Other apps hold more than this Mac can spare beside the game (at least 1.5 GB counts, even on large Macs' small margins).
    var memoryTight: Bool {
        let spare = physical > Self.gameAndSystemBytes ? physical - Self.gameAndSystemBytes : 0
        return othersBytes > max(spare, 3 << 29) && !heavyApps.isEmpty
    }
    var hot: Bool { thermal == .serious || thermal == .critical }
    var hasIssues: Bool { memoryTight || lowPowerMode || hot }

    /// - Parameter excluding: processes not to count or offer to quit (running games).
    static func check(excluding: Set<pid_t> = []) -> PlayReadiness {
        var r = PlayReadiness()
        r.swapUsedBytes = swapUsed()

        let me = NSRunningApplication.current.processIdentifier
        var apps: [pid_t: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && !a.isTerminated {
            let pid = a.processIdentifier
            if pid == me || excluding.contains(pid) || a.bundleIdentifier == "com.apple.finder" { continue }
            apps[pid] = a
        }

        // Attribute every process to the regular app it descends from, so a browser counts with its tabs.
        var parent: [pid_t: pid_t] = [:], footprint: [pid_t: UInt64] = [:]
        for pid in allPIDs() {
            var bsd = proc_bsdinfo()
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) == Int32(MemoryLayout<proc_bsdinfo>.size) {
                parent[pid] = pid_t(bsd.pbi_ppid)
            }
            if let f = physFootprint(pid) { footprint[pid] = f }
        }
        var total: [pid_t: UInt64] = [:]
        for (pid, f) in footprint {
            var p = pid, hops = 0
            while hops < 32, p > 1 {
                if apps[p] != nil { total[p, default: 0] += f; break }
                guard let up = parent[p], up != p else { break }
                p = up; hops += 1
            }
        }

        for (pid, a) in apps {
            let b = total[pid] ?? 0
            r.othersBytes += b
            if b >= listThreshold {
                let raw = a.localizedName ?? a.bundleURL?.deletingPathExtension().lastPathComponent ?? "App \(pid)"
                let name = String(String.UnicodeScalarView(raw.unicodeScalars.filter { $0.properties.generalCategory != .format }))   // e.g. WhatsApp's U+200E
                r.heavyApps.append(HeavyApp(app: a, name: name, bytes: b))
            }
        }
        r.heavyApps.sort { $0.bytes > $1.bytes }
        if r.heavyApps.count > 8 { r.heavyApps = Array(r.heavyApps.prefix(8)) }
        return r
    }

    private static func allPIDs() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        return got > 0 ? Array(pids.prefix(Int(got))).filter { $0 > 0 } : []
    }

    /// The figure Activity Monitor calls Memory. Nil for processes this user can't read.
    private static func physFootprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return ok == 0 ? info.ri_phys_footprint : nil
    }

    private static func swapUsed() -> UInt64 {
        var u = xsw_usage(), size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &u, &size, nil, 0) == 0 ? u.xsu_used : 0
    }

    static func gb(_ b: UInt64) -> String { String(format: "%.1f GB", Double(b) / 1_073_741_824) }
}

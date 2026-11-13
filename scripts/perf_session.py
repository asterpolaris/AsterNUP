#!/usr/bin/env python3
"""Measure a game session on this Mac and write a performance report (Markdown + JSON).

Starts the game app with nxnative's frame-timing table (DM_NVN_TSV, timing rows only), measures cold launch
(launch → first frame row), samples the game's memory and system swap every second, and after the session reads
frame times (@frame_ms, @presented_ms) and the game log's audio underrun lines.

Usage:
  scripts/perf_session.py "~/Applications/AsterNUP Games/The Legend of Zelda - Ocarina of Time.app" --minutes 10
  scripts/perf_session.py <app> --analyze-only <tsv>     (re-analyze an earlier run)
Play during the session (the script only watches). Quit the game, or wait for --minutes, to end it.
Cold launch means: first start after a reboot or after `sudo purge`; the script records whether caches were purged.
"""
import argparse, json, math, os, plistlib, re, subprocess, sys, time
from pathlib import Path

def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout.strip()

def pct(xs, p):
    if not xs: return None
    s = sorted(xs); return s[min(len(s) - 1, max(0, math.ceil(p / 100 * len(s)) - 1))]

def machine():
    disp = sh('system_profiler', 'SPDisplaysDataType')
    res = re.findall(r'Resolution: (.+)', disp); hz = re.findall(r'Refresh Rate: (.+)|UI Looks like: .*@ ([\d.]+Hz)', disp)
    return {'chip': sh('sysctl', '-n', 'machdep.cpu.brand_string'), 'memory_gb': int(sh('sysctl', '-n', 'hw.memsize')) // 2**30,
            'macos': f"{sh('sw_vers', '-productVersion')} ({sh('sw_vers', '-buildVersion')})", 'model': sh('sysctl', '-n', 'hw.model'),
            'displays': res, 'refresh': [h[0] or h[1] for h in hz], 'gpu_cores': (re.findall(r'Total Number of Cores: (\d+)', disp) or ['?'])[0]}

def swap_mb():
    m = re.search(r'used = ([\d.]+)M', sh('sysctl', 'vm.swapusage'))
    return float(m.group(1)) if m else None

def wired_gb():
    out = sh('vm_stat'); page = int(re.search(r'page size of (\d+)', out).group(1)) if 'page size' in out else 16384
    m = re.search(r'Pages wired down:\s+(\d+)', out)
    return int(m.group(1)) * page / 2**30 if m else 0.0

def game_pids(app):
    exe = str(Path(app) / 'Contents/MacOS')
    out = []
    for line in sh('ps', '-axo', 'pid=,rss=,command=').splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and parts[2].startswith(exe): out.append((int(parts[0]), int(parts[1])))
    return out

def analyze(tsv, budget_ms, skip_s=5.0):
    rows = {}
    with open(tsv, errors='replace') as fh:
        for ln in fh:
            c = ln.rstrip('\n').split('\t')
            if len(c) != 3 or not c[1].startswith('@'): continue
            try: rows.setdefault(int(c[0]), {})[c[1]] = float(c[2])
            except ValueError: pass
    sel = [r for _, r in sorted(rows.items()) if r.get('@t_s', 0) >= skip_s]
    ft = [r['@frame_ms'] for r in sel if r.get('@frame_ms', 0) > 0]
    shown = [r['@presented_ms'] for r in sel if r.get('@presented_ms', 0) > 0]
    span = (sel[-1]['@t_s'] - sel[0]['@t_s']) if len(sel) > 1 and '@t_s' in sel[-1] else None
    d = {'frames': len(sel), 'seconds': round(span, 1) if span else None, 'fps': round(len(sel) / span, 2) if span else None}
    for name, xs in (('frame', ft), ('presented', shown)):
        for p in (50, 95, 99): d[f'{name}_p{p}_ms'] = round(pct(xs, p), 2) if xs else None
        d[f'{name}_max_ms'] = round(max(xs), 2) if xs else None
    d['over_budget'] = sum(1 for x in ft if x > budget_ms)
    d['stalls_over_33ms'] = sum(1 for x in ft if x > 33.4)
    d['stalls_over_100ms'] = sum(1 for x in ft if x > 100)
    d['dropped_presents'] = sum(1 for r in sel if r.get('@presented_ms') == -1)
    # Game speed: with fps_target 60 nxnative steps game time by the host's frame step, so a missed vsync advances 2 steps.
    # Wall time vs frames×budget shows whether frames that missed still kept real-time speed (ratio ≈ 1 means correct speed).
    if span and ft: d['wall_vs_frame_sum'] = round(span * 1000 / sum(ft), 3)
    return d

def underruns(log):
    total, lines = 0, 0
    if log.is_file():
        for ln in log.read_text(errors='replace').splitlines():
            m = re.search(r'(\d+) underruns', ln)
            if m: total += int(m.group(1)); lines += 1
    return {'audio_underruns': total, 'audio_report_lines': lines, 'log': str(log)}

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('app'); ap.add_argument('--minutes', type=float, default=10); ap.add_argument('--budget-ms', type=float, default=16.7)
    ap.add_argument('--out', default=str(Path.home() / 'Library/Logs/AsterNUP/perf')); ap.add_argument('--analyze-only')
    ap.add_argument('--max-swap-gb', type=float, default=16, help='stop the game if swap passes this (the Ocarina of Time note guards at 16 GB)')
    ap.add_argument('--max-wired-gb', type=float, default=12.5, help='stop the game if wired memory passes this (the note guards at 12.5 GB on a 16 GB Mac)')
    ap.add_argument('--purged', action='store_true', help='you ran `sudo purge` (or rebooted) right before: record the launch as cold')
    a = ap.parse_args()
    app = Path(os.path.expanduser(a.app)).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    tid = info.get('DMTitleID', 'unknown')
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime('%Y%m%d-%H%M%S')
    tsv = Path(a.analyze_only) if a.analyze_only else out / f'{tid}-{stamp}.tsv'
    choices = {}
    for l in sh('defaults', 'read', info.get('CFBundleIdentifier', 'none')).splitlines():
        m = re.match(r'\s*"?launcher\.(\w+)"?\s*=\s*"?([^";]*)"?;', l)
        if m: choices[m.group(1)] = m.group(2)
    rep = {'app': str(app), 'title_id': tid, 'app_version': info.get('CFBundleShortVersionString'), 'machine': machine(), 'settings': choices}
    if not a.analyze_only:
        if game_pids(app): sys.exit('The game is already running: quit it first so launch time and memory are measured from a clean start.')
        env = dict(os.environ, DM_NVN_TSV=str(tsv), DM_NVN_TSV_CALLS='0', DM_LAUNCHER='0')
        t0 = time.time()
        proc = subprocess.Popen([str(app / 'Contents/MacOS/nxnative')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        stopped = None
        first_frame = None; peak_rss = 0; swap0 = swap_mb(); swap_peak = swap0 or 0; samples = []
        end = t0 + a.minutes * 60
        print(f'Measuring {app.name} for {a.minutes:g} min. Play now; quit the game to stop early.')
        while time.time() < end and proc.poll() is None:
            time.sleep(1)
            if first_frame is None and tsv.exists() and tsv.stat().st_size > 0: first_frame = time.time() - t0
            rss = sum(r for _, r in game_pids(app)) // 1024
            peak_rss = max(peak_rss, rss); s = swap_mb() or 0; swap_peak = max(swap_peak, s)
            w = wired_gb()
            samples.append((round(time.time() - t0, 1), rss, s))
            if s / 1024 > a.max_swap_gb or w > a.max_wired_gb:
                stopped = f'stopped by the safety guard: swap {s / 1024:.1f} GB (limit {a.max_swap_gb}), wired {w:.1f} GB (limit {a.max_wired_gb})'
                print('!! ' + stopped); proc.terminate(); break
        if proc.poll() is None:
            proc.terminate()
            try: proc.wait(20)
            except subprocess.TimeoutExpired: proc.kill()
        rep.update({'launch_to_first_frame_s': round(first_frame, 2) if first_frame else None, 'launch_was_cold': a.purged,
                    'peak_rss_mb': peak_rss, 'swap_start_mb': swap0, 'swap_peak_mb': swap_peak, 'exit_code': proc.returncode,
                    'session_s': round(time.time() - t0, 1), 'safety_stop': stopped})
        (out / f'{tid}-{stamp}-memory.tsv').write_text('t_s\trss_mb\tswap_mb\n' + ''.join(f'{t}\t{r}\t{s}\n' for t, r, s in samples))
    rep['frames'] = analyze(tsv, a.budget_ms) if tsv.exists() else {'error': f'no frame table at {tsv}'}
    rep['audio'] = underruns(Path.home() / f'Library/Logs/nxnative/{tid}.log')
    js = out / f'{tid}-{stamp}.json'; js.write_text(json.dumps(rep, indent=1))
    f = rep['frames']; m = rep['machine']
    md = [f"# Performance: {info.get('CFBundleName', app.stem)} ({tid})", '',
          f"- Mac: {m['model']}, {m['chip']}, {m['gpu_cores']} GPU cores, {m['memory_gb']} GB, macOS {m['macos']}",
          f"- Display: {', '.join(m['displays'])} @ {', '.join(m['refresh']) or '?'}",
          f"- Game build: app version {rep['app_version']}; settings: {rep['settings'] or 'tested defaults'}",
          f"- Launch → first frame: {rep.get('launch_to_first_frame_s')} s ({'cold' if rep.get('launch_was_cold') else 'warm or unknown cache state'})",
          f"- Frames: {f.get('frames')} over {f.get('seconds')} s, {f.get('fps')} fps",
          f"- Frame time ms: median {f.get('frame_p50_ms')}, p95 {f.get('frame_p95_ms')}, p99 {f.get('frame_p99_ms')}, max {f.get('frame_max_ms')}",
          f"- Over {a.budget_ms} ms: {f.get('over_budget')}; stalls >33 ms: {f.get('stalls_over_33ms')}; >100 ms: {f.get('stalls_over_100ms')}; dropped presents: {f.get('dropped_presents')}",
          f"- Game speed check (wall time / sum of frame times, ≈1.0 is correct): {f.get('wall_vs_frame_sum')}",
          f"- Peak memory (RSS): {rep.get('peak_rss_mb')} MB; swap {rep.get('swap_start_mb')} → peak {rep.get('swap_peak_mb')} MB",
          f"- Audio underruns (game log): {rep['audio']['audio_underruns']} in {rep['audio']['audio_report_lines']} reports",
          f"- Safety guard: {rep.get('safety_stop') or 'not triggered'}", '']
    (out / f'{tid}-{stamp}.md').write_text('\n'.join(md))
    print('\n'.join(md)); print(f'Report: {js}')

if __name__ == '__main__':
    main()

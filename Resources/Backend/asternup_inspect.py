#!/usr/bin/env python3
"""AsterNUP package inspector for the nxnative backend.

Reads a .nup container (NUP SPEC v1) or a dump folder (ExeFS/RomFS layout) IN PLACE, without writing to it,
and prints one JSON report on stdout: identity, packages, verified build IDs, layout, the pinned backend's
profile match, and issues with the next actionable step. It reuses the backend's own readers
(scripts/pack_nup.py, dm/games/game.py) so what it reports is what the build script will see.

Usage: asternup_inspect.py --backend <nxnative checkout> <input> [--icon-out DIR] [--verify] [--package vN]
Exit 0 with a report (errors are reported inside it), 2 for bad arguments, 1 for an unexpected failure.
"""
import argparse, hashlib, json, os, re, struct, sys, time
from pathlib import Path

LABEL_DISPLAY, LABEL_NAME, LABEL_PUBLISHER, LABEL_BUILD_ID, LABEL_SOURCE = 4, 5, 6, 7, 8
T_NACP, T_ICON = 2, 3
MODULE_NAMES = ('main', 'rtld', 'sdk') + tuple(f'subsdk{i}' for i in range(10))


def progress(msg, done=None, total=None):
    """Progress for the launcher, on stderr, one JSON object per line."""
    sys.stderr.write(json.dumps({'ev': 'progress', 'msg': msg, 'done': done, 'total': total}) + '\n')
    sys.stderr.flush()


def platform_of(tid):
    hi = tid >> 56
    return {0x01: 'Nintendo Switch', 0x04: 'Nintendo Switch 2'}.get(hi, f'unknown (title ID prefix {hi:02X})')


def nacp_fields(b):
    """Name and publisher (first non-empty language entry) and display version from an NACP."""
    if not b or len(b) < 0x3070: return None
    name = pub = ''
    for i in range(16):
        e = b[i * 0x300:(i + 1) * 0x300]
        n = e[:0x200].split(b'\0', 1)[0].decode('utf-8', 'replace').strip()
        if n:
            name = n
            pub = e[0x200:0x300].split(b'\0', 1)[0].decode('utf-8', 'replace').strip()
            break
    dv = b[0x3060:0x3070].split(b'\0', 1)[0].decode('utf-8', 'replace').strip()
    return {'name': name, 'publisher': pub, 'display_version': dv}


def nso_build_id(head):
    """First 16 bytes of the ModuleId (0x40..0x50) of an NSO0/NRO0 header, as nxnative keys builds."""
    if len(head) < 0x50 or head[:4] not in (b'NSO0', b'NRO0'): return None
    return head[0x40:0x50].hex()


def version_text(v):
    return f'{v >> 16}.{(v >> 8) & 0xFF}.{v & 0xFF}' if v else '0 (base)'


class Report:
    def __init__(self, path):
        self.d = {'schema': 1, 'input': str(path), 'kind': None, 'size': 0, 'title_id': None, 'platform': None,
                  'labels': {}, 'nacp': None, 'icon': None, 'packages': [], 'dlc': [], 'selected_version': None,
                  'layout': None, 'playable': False, 'build_ids': {}, 'build_ids_verified': False,
                  'profile': None, 'integrity': 'not-checked', 'issues': []}

    def issue(self, severity, message, action=''):
        self.d['issues'].append({'severity': severity, 'message': message, 'action': action})


# ---------------------------------------------------------------- NUP input
def inspect_nup(path, rep, args, pack_nup):
    rep.d['kind'] = 'nup'
    rep.d['size'] = path.stat().st_size
    try:
        n = pack_nup.Nup(path)   # validates superblock, TOC SHA-256, every record's bounds
    except pack_nup.Error as e:
        rep.issue('error', str(e), 'The file is damaged or incomplete. Copy it again from the source machine and compare its size, then import again.')
        return None
    rep.d['integrity'] = 'toc-verified'
    rep.d['format_version'] = 1
    rep.d['uuid'] = n.uuid.hex()
    pkgs = []
    for k in n.packages:
        meta = {}
        try: meta = k.meta()
        except pack_nup.Error as e: rep.issue('warning', str(e))
        lab = lambda t: meta[t].decode('utf-8', 'replace').strip() if t in meta else None
        entry = {'index': k.index, 'kind': pack_nup.KINDS[k.kind], 'title_id': f'{k.title_id:016X}', 'version': k.version,
                 'version_text': version_text(k.version), 'standalone_update': bool(k.flags & pack_nup.STANDALONE),
                 'has_exefs': k.exefs != pack_nup.NO_DIR, 'has_romfs': k.romfs != pack_nup.NO_DIR,
                 'bytes': n.tree_bytes(k.root),
                 'labels': {'display_version': lab(LABEL_DISPLAY), 'name': lab(LABEL_NAME), 'publisher': lab(LABEL_PUBLISHER),
                            'source_dump': lab(LABEL_SOURCE),
                            'build_id': meta[LABEL_BUILD_ID][:16].hex() if LABEL_BUILD_ID in meta else None},
                 'has_nacp': T_NACP in meta, 'has_icon': T_ICON in meta}
        if T_NACP in meta: entry['nacp'] = nacp_fields(meta[T_NACP])
        pkgs.append((k, entry, meta))
        rep.d['packages'].append(entry)

    try:
        app, base, vers, dlc = pack_nup.scan(n)
    except pack_nup.Error as e:
        rep.issue('error', str(e), 'Repack the NUP so it holds the base game (and its update), or updates marked standalone_update that carry complete exefs/ and romfs/.')
        return n
    rep.d['title_id'] = f'{app:016X}'
    rep.d['platform'] = platform_of(app)
    rep.d['dlc'] = [f'{t:016X}' for t in sorted(dlc)]
    sel = choose_version(rep, base is not None, sorted(vers), args.package)
    if sel is None: return n
    k = base if sel == 0 else vers[sel]
    rep.d['selected_version'] = sel
    rep.d['layout'] = ('base' if not vers else 'base+update') if base is not None else 'standalone-update'

    # Code modules of the selected package: read and checked against their SHA-256 (verified build IDs).
    if k.exefs == pack_nup.NO_DIR:
        if sel != 0 and base is not None and base.exefs != pack_nup.NO_DIR:
            rep.issue('warning', f'Update v{sel} carries no ExeFS; the base game\'s code would run with the update\'s data.', 'Use a NUP whose update includes its exefs/.')
        else:
            rep.issue('error', 'The selected package has no ExeFS (no game code).', 'Repack the dump with its exefs/ folder.')
            return n
    else:
        ids, ok = {}, True
        for name, isdir, i in n.children(k.exefs):
            nm = name.decode(errors='replace')
            if isdir or nm not in MODULE_NAMES: continue
            try:
                h = hashlib.sha256(); n.copy(i, _Sink(h))
            except pack_nup.Error as e:
                ok = False; rep.issue('error', str(e), 'The file is damaged. Copy it again and re-import.'); continue
            bid = nso_build_id(n.head(i, 0x60))
            if bid: ids[nm] = bid
        rep.d['build_ids'] = ids
        rep.d['build_ids_verified'] = ok and 'main' in ids
        lab = next((e['labels']['build_id'] for kk, e, _ in pkgs if kk is k), None)
        if lab and ids.get('main') and lab != ids['main']:
            rep.issue('warning', f'The packer\'s build ID label {lab} differs from the main module\'s actual build ID {ids["main"]}.', 'The actual module is used; the label is ignored.')

    # Labels (typed by the packer) vs control data (console NACP)
    sel_entry = next(e for kk, e, _ in pkgs if kk is k)
    rep.d['labels'] = {kk: v for kk, v in sel_entry['labels'].items() if v}
    nacp_src = next((m for kk, e, m in pkgs if kk is k and T_NACP in m), None) or (next((m for kk, e, m in pkgs if kk is base and T_NACP in m), None) if base else None)
    if nacp_src:
        rep.d['nacp'] = nacp_fields(nacp_src[T_NACP])
        if rep.d['nacp'] is not None:
            rep.d['nacp']['source'] = 'selected package' if T_NACP in next(m for kk, e, m in pkgs if kk is k) else 'base game (the update carries none)'
    icon_src = next((m for kk, e, m in pkgs if kk is k and T_ICON in m), None) or (next((m for kk, e, m in pkgs if kk is base and T_ICON in m), None) if base else None)
    if icon_src and args.icon_out:
        b = icon_src[T_ICON]
        ext = '.png' if b[:4] == b'\x89PNG' else '.jpg'
        out = Path(args.icon_out) / f'{app:016X}{ext}'
        out.parent.mkdir(parents=True, exist_ok=True); out.write_bytes(b)
        rep.d['icon'] = str(out)

    # RomFS presence for the selected version
    has_romfs = k.romfs != pack_nup.NO_DIR or (base is not None and base.romfs != pack_nup.NO_DIR)
    if not has_romfs:
        rep.issue('error', 'No RomFS (game data) for the selected version.', 'Repack the dump with its romfs/ folder.')
        return n
    rep.d['_romfs_lookup'] = (n, k.romfs if k.romfs != pack_nup.NO_DIR else base.romfs)

    if args.verify:
        verify_all(n, rep, pack_nup)
    return n


class _Sink:
    def __init__(self, h): self.h = h
    def write(self, b): self.h.update(b); return len(b)


def verify_all(n, rep, pack_nup):
    total = sum(f[1] for f in n.files); done = 0; t = time.time()
    for i, f in enumerate(n.files):
        try: n.copy(i, _Sink(hashlib.sha256()))
        except pack_nup.Error as e:
            rep.d['integrity'] = 'damaged'
            rep.issue('error', str(e), 'The file is damaged. Copy it again from the source machine and re-import.'); return
        done += f[1]
        if time.time() - t > 0.5: progress('Verifying file hashes', done, total); t = time.time()
    rep.d['integrity'] = 'all-files-verified'


def choose_version(rep, has_base, versions, want):
    if want:
        v = int(str(want).lstrip('v'))
        if v == 0 and has_base: return 0
        if v in versions: return v
        rep.issue('error', f'Package v{v} is not in this input (has: {", ".join(["v0"] * has_base + [f"v{x}" for x in versions])}).', 'Choose one of the listed versions.')
        return None
    if versions: return versions[-1]
    if has_base: return 0
    rep.issue('error', 'No playable package.', 'Supply the base game.')
    return None


# ---------------------------------------------------------------- folder input
def inspect_folder(path, rep, args, pack_nup):
    rep.d['kind'] = 'folder'
    rep.d['integrity'] = 'not-applicable'
    rep.d['size'] = sum(f.stat().st_size for f in path.rglob('*') if f.is_file())

    def pkg_dir(d):
        e = next((d / x for x in ('exefs', 'ExeFS') if (d / x).is_dir()), None)
        r = next((d / x for x in ('romfs', 'RomFS') if (d / x).is_dir()), None)
        return e, r
    base = None
    if (path / 'base').is_dir(): base = pkg_dir(path / 'base')
    elif any((path / x).is_dir() for x in ('exefs', 'ExeFS')): base = pkg_dir(path)
    updates = {}
    if (path / 'updates').is_dir():
        for u in (path / 'updates').iterdir():
            if u.is_dir() and u.name.isdigit(): updates[int(u.name)] = pkg_dir(u)
    dlc = sorted(d.name.upper() for d in (path / 'dlc').iterdir() if d.is_dir()) if (path / 'dlc').is_dir() else []
    if base is None and not updates:
        rep.issue('error', 'This folder has no exefs/ (or base/, updates/<version>/) folder.',
                  'Choose the folder `nup extract` wrote (exefs/ + romfs/), or a folder with base/exefs, base/romfs and optional updates/<version>/.')
        return
    for v, (e, r) in [(0, base)] * (base is not None) + sorted(updates.items()):
        rep.d['packages'].append({'index': len(rep.d['packages']), 'kind': 'base' if v == 0 else 'update', 'version': v, 'version_text': version_text(v),
                                  'has_exefs': e is not None, 'has_romfs': r is not None, 'standalone_update': False,
                                  'bytes': sum(f.stat().st_size for d in (e, r) if d for f in d.rglob('*') if f.is_file()), 'labels': {}})
    rep.d['dlc'] = dlc
    sel = choose_version(rep, base is not None, sorted(updates), args.package)
    if sel is None: return
    e, r = base if sel == 0 else updates[sel]
    if e is None and sel and base: e = base[0]
    if r is None and sel and base: r = base[1]
    rep.d['selected_version'] = sel
    rep.d['layout'] = ('base' if not updates else 'base+update') if base else 'standalone-update'
    if e is None or not (e / 'main').is_file() or not (e / 'main.npdm').is_file():
        rep.issue('error', 'No exefs/main and exefs/main.npdm for the selected version.', 'Re-dump the game including its ExeFS.')
        return
    try: app = pack_nup.program_id((e / 'main.npdm').read_bytes(), str(e / 'main.npdm'))
    except pack_nup.Error as x:
        rep.issue('error', str(x), 'Re-dump exefs/main.npdm.'); return
    if base is None and app & 0xFFF == 0x800: app &= ~0xFFF
    rep.d['title_id'] = f'{app:016X}'
    rep.d['platform'] = platform_of(app)
    ids = {}
    for m in MODULE_NAMES:
        if (e / m).is_file():
            with open(e / m, 'rb') as f: bid = nso_build_id(f.read(0x60))
            if bid: ids[m] = bid
    rep.d['build_ids'] = ids
    rep.d['build_ids_verified'] = 'main' in ids   # read from the module file itself
    for c in (e.parent / 'control.nacp', path / 'control.nacp'):
        if c.is_file(): rep.d['nacp'] = nacp_fields(c.read_bytes()); break
    if r is None:
        rep.issue('error', 'No romfs/ folder for the selected version.', 'Re-dump the game including its RomFS.'); return
    rep.d['_romfs_lookup'] = r


def romfs_has(rep, rel):
    look = rep.d.get('_romfs_lookup')
    if look is None: return None
    if isinstance(look, Path): return (look / rel).is_file()
    n, d = look
    for part in rel.split('/'):
        hit = next(((isdir, i) for name, isdir, i in n.children(d) if name.decode(errors='replace') == part), None)
        if hit is None: return False
        isdir, d = hit
    return True


# ---------------------------------------------------------------- profile match
def match_profile(rep, game):
    tid = rep.d['title_id']
    if not tid: return
    g = game.by_title(int(tid, 16))
    main = rep.d['build_ids'].get('main')
    if g is None and main: g = game.by_build(main)
    if g is None:
        rep.d['profile'] = {'found': False, 'match': 'none'}
        rep.issue('warning', f'The pinned backend has no profile for {tid}. nxnative would write a survey and a provisional build that may not start.',
                  'Check the backend\'s tested games list, or update the backend pin to a revision that supports this title.')
        return
    builds = g.builds()
    reg = [{'version': v, 'display': b.get('display'), 'modules': {m: x for m, x in b.items() if m != 'display'}} for v, b in builds.items()]
    sel = f'v{rep.d["selected_version"]}' if rep.d['selected_version'] is not None else None
    ids = rep.d['build_ids']
    exact = next((r for r in reg if r['modules'] and all(ids.get(m) == x for m, x in r['modules'].items())), None)
    prof = {'found': True, 'id': g.id, 'name': g.get('name', ''), 'dir': str(g.dir), 'registered': reg,
            'package': g.get('package', ''), 'readme': str(g.dir / 'README.md') if (g.dir / 'README.md').is_file() else None}
    if exact:
        prof['match'] = 'exact'; prof['matched_version'] = exact['version']; prof['display_version'] = exact['display']
        if sel and exact['version'] != sel:
            rep.issue('warning', f'The code matches registered build {exact["version"]} but the package says {sel}.', 'The build IDs are authoritative; continue.')
    else:
        want = next((r for r in reg if r['version'] == sel), None)
        if want:
            prof['match'] = 'mismatch'
            prof['mismatches'] = [f'{m}: dump {ids.get(m, "missing")} vs registered {x}' for m, x in want['modules'].items() if ids.get(m) != x]
            rep.issue('error', f'Package {sel} is registered, but its code differs from the registered build: ' + '; '.join(prof['mismatches']),
                      'The dump may be modified or a different release. Re-dump the cartridge and its update, or use a backend revision that registers this build.')
        else:
            prof['match'] = 'unregistered'
            have = ', '.join(f'{r["version"]} ({r["display"]})' for r in reg) or 'none'
            rep.issue('error', f'Package {sel or "?"} (main {ids.get("main", "?")}) is not a build the pinned backend registers. Registered: {have}.',
                      f'Supply package {g.get("package", reg[-1]["version"] if reg else "?")} (install the matching update on the console and dump base + update into one NUP), or update the backend pin.')
    marker = g.get('romfs_marker', '')
    if marker:
        has = romfs_has(rep, marker)
        prof['romfs_marker'] = {'path': marker, 'present': has}
        if has is False:
            rep.issue('error', f'The game data lacks {marker}, which this game needs. The RomFS is incomplete' +
                      (' (this standalone update holds only changed files).' if rep.d['layout'] == 'standalone-update' else '.'),
                      'Pack a NUP that contains the base game together with its update.')
    rep.d['profile'] = prof


def finish(rep):
    rep.d.pop('_romfs_lookup', None)
    errors = [i for i in rep.d['issues'] if i['severity'] == 'error']
    if rep.d['layout'] == 'standalone-update' and not errors:
        rep.issue('info', 'No base game in this input: the update is taken as the whole game (nxnative cannot prove an update is complete).',
                  'If the game stops on missing files, pack a NUP with the base game.')
    rep.d['playable'] = not errors and rep.d['selected_version'] is not None and bool(rep.d['build_ids'].get('main'))
    if rep.d['playable'] and rep.d.get('profile', {}) and rep.d['profile'].get('match') == 'exact':
        rep.d['verdict'] = 'supported'
    elif rep.d['playable']:
        rep.d['verdict'] = 'provisional'
    else:
        rep.d['verdict'] = 'blocked'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('input'); ap.add_argument('--backend', required=True)
    ap.add_argument('--icon-out'); ap.add_argument('--verify', action='store_true'); ap.add_argument('--package')
    args = ap.parse_args()
    be = Path(args.backend).resolve()
    sys.path[:0] = [str(be / 'scripts'), str(be / 'dm/games'), str(be / 'dm/tools')]
    import pack_nup, game
    p = Path(args.input).expanduser().resolve()
    rep = Report(p)
    n = None
    if not p.exists():
        rep.issue('error', f'{p} does not exist.', 'Choose the file again.')
    elif p.is_dir():
        nups = sorted(p.glob('*.nup'))
        if len(nups) == 1: p = nups[0]; rep.d['input'] = str(p)
    try:
        if p.is_file():
            if not pack_nup.is_nup(p):
                rep.d['kind'] = 'unknown'; rep.d['size'] = p.stat().st_size
                rep.issue('error', f'{p.name} is not a NUP container (no NUP magic).',
                          'Select the .nup file produced by your dumper, or a folder with exefs/ and romfs/. NSP/XCI files need prod.keys and are not part of this flow.')
            else:
                n = inspect_nup(p, rep, args, pack_nup)
        elif p.is_dir():
            inspect_folder(p, rep, args, pack_nup)
        if rep.d['title_id'] and not any(i['severity'] == 'error' and 'TOC' in i['message'] for i in rep.d['issues']):
            match_profile(rep, game)
    finally:
        finish(rep)
        if n: n.close()
    json.dump(rep.d, sys.stdout, indent=1)
    sys.stdout.write('\n')


if __name__ == '__main__':
    main()

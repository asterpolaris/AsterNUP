#!/usr/bin/env python3
"""Writes SYNTHETIC NUP containers (NUP SPEC v1) for testing AsterNUP's import flow without a real dump.

The files hold fake NSO headers (only the ModuleId bytes are set) and placeholder RomFS files: no game code
or data. Usage: make_fixture_nup.py <out dir>
Writes: good.nup (base + update v131072 with Ocarina of Time's registered build IDs), mismatch.nup,
standalone_incomplete.nup, truncated.nup, notnup.nup, and folder_good/ (exefs/ + romfs/).
"""
import hashlib, os, struct, sys, uuid
from pathlib import Path

SUPER = struct.Struct('<4sHHQQ32sQQII16s32s')
TOC = struct.Struct('<4sIQQQQQ')
PKG = struct.Struct('<QIIIIBBHIQI20x')
DIR = struct.Struct('<IIIIQ')
FILE = struct.Struct('<IIQQQ32sBBH12x')
TLV = struct.Struct('<HHI')
NO_DIR = 0xFFFFFFFF
TID = 0x0400486024DEC000
ZELDA = {'main': 'e0f3ccfaf50065ae4ea01eb5aeb13b1a', 'subsdk0': 'b0110087a7b339ef74588d3bd0b4dd5d', 'sdk': '1643a838814f9c10c696f930ed681e7f'}


def nso(bid_hex):
    b = bytearray(0x100); b[:4] = b'NSO0'; b[0x40:0x50] = bytes.fromhex(bid_hex); return bytes(b)


def npdm(pid):
    b = bytearray(0x200); b[:4] = b'META'; struct.pack_into('<II', b, 0x70, 0x100, 0x40)
    b[0x100:0x104] = b'ACI0'; struct.pack_into('<Q', b, 0x110, pid); return bytes(b)


def nacp(name, pub, dv):
    b = bytearray(0x4000); b[0:len(name)] = name.encode(); b[0x200:0x200 + len(pub)] = pub.encode()
    b[0x3060:0x3060 + len(dv)] = dv.encode(); return bytes(b)


def write_nup(path, packages):
    """packages: [(title_id, version, kind, flags, tree {name: bytes | dict}, meta {type: bytes})]"""
    pool = bytearray(); dirs = []; files = []; slots = []; blobs = []

    def s(name):
        o = len(pool); pool.extend(name.encode()); return o, len(name.encode())

    def add_dir(name, tree):   # depth-first; returns dir index
        idx = len(dirs); dirs.append(None)
        kids = []
        for k in sorted(tree, key=lambda x: x.encode()):
            v = tree[k]
            if isinstance(v, dict): kids.append(('d', add_dir(k, v)))
            else:
                fi = len(files); files.append((s(k), v)); kids.append(('f', fi))
        dirs[idx] = (s(name), kids)
        return idx

    recs = []
    for tid, ver, kind, flags, tree, meta in packages:
        root = add_dir('', tree)
        dname = lambda i: bytes(pool[dirs[i][0][0]:dirs[i][0][0] + dirs[i][0][1]])
        sub = {dname(c): c for t, c in dirs[root][1] if t == 'd'}
        ex, ro = sub.get(b'exefs', NO_DIR), sub.get(b'romfs', NO_DIR)
        mb = b''.join(TLV.pack(t, 0, len(v)) + v for t, v in meta.items())
        recs.append([tid, root, ex, ro, ver, kind, flags, mb])
    ndirs, nfiles = len(dirs), len(files)
    dir_recs = []
    for (o, n), kids in dirs:
        first = len(slots)
        slots.extend(c if t == 'd' else ndirs + c for t, c in kids)
        dir_recs.append((o, n, first, len(kids)))
    toc_fixed = TOC.size + len(recs) * PKG.size + ndirs * DIR.size + nfiles * FILE.size + len(slots) * 4
    pool_off = toc_fixed
    while len(pool) % 4: pool.append(0)
    toc_size = pool_off + len(pool)
    hsize = SUPER.size
    meta_off = hsize + toc_size
    meta_off += (-meta_off) % 16
    metas = []; p = meta_off
    for r in recs:
        mb = r[7]; metas.append((p if mb else 0, len(mb))); p += len(mb); p += (-p) % 16
    blob = p; data = bytearray(); file_recs = []
    for (o, n), content in files:
        off = blob + len(data) if content else 0
        data.extend(content); data.extend(b'\0' * ((-len(data)) % 16))
        file_recs.append((o, n, len(content), off, len(content), hashlib.sha256(content).digest(), 0, 0, 0))
    fsize = blob + len(data)
    toc = bytearray(TOC.pack(b'TOC\x01', len(recs), ndirs, nfiles, pool_off, len(pool), 0))
    for r, (mo, ms) in zip(recs, metas): toc += PKG.pack(r[0], r[1], r[2], r[3], r[4], r[5], r[6], 0, 0, mo, ms)
    for d in dir_recs: toc += DIR.pack(*d, 0)
    for f in file_recs: toc += FILE.pack(*f)
    toc += struct.pack(f'<{len(slots)}I', *slots) + pool
    sup = SUPER.pack(b'NUP\x01', hsize, 0, hsize, len(toc), hashlib.sha256(toc).digest(), blob, fsize, len(recs), 0, uuid.uuid4().bytes, b'')
    out = bytearray(sup) + toc
    for r, (mo, ms) in zip(recs, metas):
        if ms: out.extend(b'\0' * (mo - len(out))); out.extend(r[7])
    out.extend(b'\0' * (blob - len(out))); out.extend(data)
    Path(path).write_bytes(out)


def exefs(ids, pid=TID):
    return {'main': nso(ids['main']), 'main.npdm': npdm(pid), **{m: nso(b) for m, b in ids.items() if m != 'main'}}


def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    romfs_full = {'Pack': {'ZsDic.pack.zs': b'SYNTHETIC-PLACEHOLDER'}, 'README.txt': b'synthetic fixture, no game data'}
    base_ids = {'main': '00' * 16, 'sdk': '1643a838814f9c10c696f930ed681e7f'}
    labels = lambda dv: {4: dv.encode(), 5: b'Fixture Game', 6: b'Fixture Packer'}
    base = (TID, 0, 0, 0, {'exefs': exefs(base_ids), 'romfs': romfs_full}, {3: b'\xff\xd8\xff\xe0FAKEJPEG', **labels('1.0.0'), 2: nacp('Fixture Game', 'Fixture Pub', '1.0.0')})
    upd = (TID, 131072, 1, 0, {'exefs': exefs(ZELDA), 'romfs': romfs_full}, labels('1.1.1'))
    write_nup(out / 'good.nup', [base, upd])
    bad = dict(ZELDA, main='ff' * 16)
    write_nup(out / 'mismatch.nup', [base, (TID, 131072, 1, 0, {'exefs': exefs(bad), 'romfs': romfs_full}, labels('1.1.1'))])
    write_nup(out / 'standalone_incomplete.nup', [(TID, 131072, 1, 1, {'exefs': exefs(ZELDA), 'romfs': {'Changed.bin': b'x'}}, labels('1.1.1'))])
    g = (out / 'good.nup').read_bytes(); (out / 'truncated.nup').write_bytes(g[:len(g) - 64])
    (out / 'notnup.nup').write_bytes(b'PFS0' + b'\0' * 1000)
    fd = out / 'folder_good'
    for rel, b in [('exefs/' + k, v) for k, v in exefs(ZELDA).items()] + [('romfs/Pack/ZsDic.pack.zs', b'SYNTHETIC')]:
        (fd / rel).parent.mkdir(parents=True, exist_ok=True); (fd / rel).write_bytes(b)
    print(out)


if __name__ == '__main__':
    main()

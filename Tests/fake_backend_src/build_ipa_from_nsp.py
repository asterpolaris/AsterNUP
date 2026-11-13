#!/usr/bin/env python3
"""FAKE nxnative build script for AsterNUP's UI tests. Speaks the --progress json protocol of docs/frontends.md.
FAKE_BUILD_MODE=ok (default) copies Stand-in Game.app to -o with the dump's title ID; fail stops with a [RED] say; slow runs until SIGTERM."""
import argparse, json, os, shutil, signal, subprocess, sys, time, plistlib
from pathlib import Path
ap = argparse.ArgumentParser()
ap.add_argument('nsp_dir'); ap.add_argument('--platform'); ap.add_argument('--progress'); ap.add_argument('--work-dir'); ap.add_argument('-o', '--out')
ap.add_argument('--app-name'); ap.add_argument('--package'); ap.add_argument('--fallback-icon'); ap.add_argument('--mac-sign'); ap.add_argument('--team-id')
ap.add_argument('--seen-shaders', action=argparse.BooleanOptionalAction)
a = ap.parse_args()
def ev(**k): k['t'] = time.time(); print(json.dumps(k), flush=True)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
mode = os.environ.get('FAKE_BUILD_MODE', 'ok')
Path(a.work_dir, 'logs').mkdir(parents=True, exist_ok=True)
ev(ev='stage', k=1, n=3, name='Extract', step='Reading the NUP')
for i in range(5): ev(ev='progress', k=1, name='Extract', step='RomFS image', done=i * 20, total=100, unit='', est=False, note='', frac=i / 5, eta=1, elapsed=i * 0.2); time.sleep(0.2)
ev(ev='stage_end', k=1, name='Extract', ok=True, summary='fake extract', elapsed=1)
ev(ev='game', title_id='0400486024DEC000', name=a.app_name, version='1.0', bundle_id='org.nxnative.0400486024dec000', out=a.out, icon=None)
ev(ev='stage', k=2, n=3, name='Shaders', step='Translating')
if mode == 'fail':
    ev(ev='say', msg='[RED] fake failure: shader translation stopped (test)'); sys.exit(1)
loops = 10_000 if mode == 'slow' else 5
for i in range(loops): ev(ev='progress', k=2, name='Shaders', step='Translating', done=i, total=loops, unit='files', est=False, note='', frac=min(0.99, i / loops), eta=loops - i, elapsed=i); time.sleep(0.2)
ev(ev='stage_end', k=2, name='Shaders', ok=True, summary='fake shaders', elapsed=1)
ev(ev='stage', k=3, n=3, name='Pack', step='Mac app')
src = Path(__file__).resolve().parents[3] / 'Stand-in Game.app'
shutil.copytree(src, a.out, symlinks=True)
info = Path(a.out, 'Contents/Info.plist'); d = plistlib.loads(info.read_bytes())
d['DMTitleID'] = '0400486024DEC000'; d['CFBundleIdentifier'] = 'org.nxnative.0400486024dec000'; d['CFBundleName'] = a.app_name
info.write_bytes(plistlib.dumps(d)); subprocess.run(['codesign', '--force', '--sign', '-', a.out], capture_output=True)
ev(ev='stage_end', k=3, name='Pack', ok=True, summary=a.out, elapsed=1)

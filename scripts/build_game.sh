#!/bin/zsh
# Command-line equivalent of AsterNUP's Import → Build: inspects the input in place, then runs the documented nxnative
# command (python3 scripts/build_ipa_from_nsp.py <input> --platform mac-app) with the full shader set, and records
# the exact command, backend commit and toolchain next to the app.
# Usage: scripts/build_game.sh /path/to/game.nup [extra nxnative options…]
set -euo pipefail
cd "${0:A:h}/.."
IN="${1:?usage: build_game.sh <game.nup | dump folder> [options]}"; shift
BE="${ASTERNUP_BACKEND:-$HOME/Library/Application Support/AsterNUP/Backend/nxnative}"
scripts/check_toolchain.sh
source scripts/lib/python.sh
PY=$(asternup_python)
[[ -x "$ASTERNUP_VENV/bin/python3" ]] && export PATH="$ASTERNUP_VENV/bin:$PATH"
REPORT=$(mktemp -t asternup-inspect)
arch -arm64 $PY -E -P Resources/Backend/asternup_inspect.py --backend "$BE" "$IN" > "$REPORT"
python3 - "$REPORT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"{d['verdict'].upper()}: {d['title_id']} {d['platform']} package v{d['selected_version']} layout={d['layout']} main={d['build_ids'].get('main')} profile={ (d['profile'] or {}).get('match') }")
for i in d['issues']: print(f"  {i['severity']}: {i['message']}\n    next: {i['action']}")
sys.exit(0 if d['playable'] else 1)
PY
TID=$(python3 -c "import json,sys;print(json.load(open('$REPORT'))['title_id'])")
OUTDIR="$HOME/Applications/AsterNUP Games"; mkdir -p "$OUTDIR"
WORK="$HOME/Library/Application Support/AsterNUP/Builds/$TID"; mkdir -p "$WORK"
CMD=(arch -arm64 $PY "$BE/scripts/build_ipa_from_nsp.py" "$IN" --platform mac-app --no-seen-shaders --work-dir "$WORK" "$@")
print -r -- "+ ${(q)CMD[@]}"
( cd "$BE" && "${CMD[@]}" )
{
  echo "date: $(date -u +%FT%TZ)"; echo "command: ${(q)CMD[@]}"; echo "backend: $(git -C "$BE" rev-parse HEAD)"
  echo "xcode: $(xcrun xcodebuild -version | tr '\n' ' ')"; echo "metal: $(xcrun metal --version 2>&1 | head -1)"
  echo "macos: $(sw_vers -productVersion) $(sw_vers -buildVersion)"; echo "mac: $(sysctl -n machdep.cpu.brand_string)"
} > "$WORK/asternup-build-record.txt"
echo "Build record: $WORK/asternup-build-record.txt (the app is next to the input unless you passed -o)"

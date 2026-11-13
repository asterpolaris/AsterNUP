#!/bin/zsh
# Checks what the pinned nxnative needs to build games (the same checks as AsterNUP's Backend panel).
set -uo pipefail
cd "${0:A:h}/.."
PINS=Resources/Backend/pins.json
XCODE=$(python3 -c "import json;print(json.load(open('$PINS'))['backends'][0]['requires']['xcode'])")
COMMIT=$(python3 -c "import json;print(json.load(open('$PINS'))['backends'][0]['commit'])")
BE="${ASTERNUP_BACKEND:-$HOME/Library/Application Support/AsterNUP/Backend/nxnative}"
ok=1
say() { printf "%-22s %s\n" "$1" "$2"; }
say "Mac" "$(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
head=$(git -C "$BE" rev-parse HEAD 2>/dev/null || echo none)
[[ "$head" == "$COMMIT" ]] && say "nxnative" "OK $head" || { say "nxnative" "MISSING/OTHER ($head; pin $COMMIT) → scripts/fetch_backend.sh"; ok=0; }
source "${0:A:h}/lib/python.sh"
if PY=$(asternup_python); then say "Python" "OK $(arch -arm64 $PY --version) $PY"; else say "Python" "MISSING arm64 3.12+ → brew install python@3.14, then scripts/install.sh"; ok=0; fi
[[ -n ${PY:-} ]] && { asternup_python_modules_ok "$PY" && say "Python modules" "OK" || { say "Python modules" "MISSING → scripts/install.sh --no-open  (installs into $ASTERNUP_VENV)"; ok=0; }; }
xv=$(xcrun xcodebuild -version 2>/dev/null | head -1)
[[ "$xv" == "Xcode $XCODE" ]] && say "Xcode" "OK $xv ($(xcode-select -p))" || { say "Xcode" "NEED Xcode $XCODE (have: ${xv:-none}; xcode-select: $(xcode-select -p)) → install, then sudo xcode-select -s /Applications/Xcode.app"; ok=0; }
xcrun -f metal >/dev/null 2>&1 && say "Metal toolchain" "OK $(xcrun metal --version 2>&1 | head -1)" || { say "Metal toolchain" "MISSING → xcodebuild -downloadComponent MetalToolchain"; ok=0; }
for t in xcodegen zstd glslangValidator; do command -v $t >/dev/null || { say "brew" "MISSING $t → brew install xcodegen zstd glslang"; ok=0; }; done
(( ok )) && echo "READY to build games" || { echo "NOT READY (see above)"; exit 1; }

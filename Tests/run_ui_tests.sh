#!/bin/zsh
# Repeatable AsterNUP checks without a real dump, Xcode or a controller. Uses an isolated data folder
# (your real library is untouched), synthetic NUP fixtures, stand-in game apps and a fake build script.
# Usage: Tests/run_ui_tests.sh        Requires: the pinned backend (scripts/fetch_backend.sh) and an arm64 Python 3.12+.
set -euo pipefail
cd "${0:A:h}/.."
OUT="build/ui-tests"; rm -rf "$OUT"; mkdir -p "$OUT"
OUT="${OUT:A}"; DATA="$OUT/data"; FX="$OUT/fixtures"
BE="${ASTERNUP_BACKEND_REAL:-$HOME/Library/Application Support/AsterNUP/Backend/nxnative}"
PY=""; for c in /opt/homebrew/bin/python3 /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /usr/local/bin/python3; do [[ -x $c ]] && { PY=$c; break; }; done
scripts/make_app.sh >/dev/null
Tests/build_standin.sh build "Stand-in Game" 0100000000ABC000 >/dev/null
Tests/build_standin.sh build "Stand-in Kart" 0100000000DEF000 >/dev/null
Tests/make_fake_backend.sh "$BE" >/dev/null
$PY Tests/make_fixture_nup.py "$FX" >/dev/null
APP=build/AsterNUP.app/Contents/MacOS/AsterNUP
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
j() { $PY -c "import json,sys;d=json.load(open('$1'));print(eval(sys.argv[1]))" "$2"; }

# 1. Inspector verdicts on the fixtures (the real pinned backend's readers and profiles)
for f in good mismatch standalone_incomplete truncated notnup folder_good; do
  arg="$FX/$f.nup"; [[ $f == folder_good ]] && arg="$FX/folder_good"
  arch -arm64 $PY -E -P Resources/Backend/asternup_inspect.py --backend "$BE" "$arg" > "$OUT/inspect-$f.json"
done
check "good.nup is a supported build (exact profile match)" '[[ $(j $OUT/inspect-good.json "d[\"verdict\"]+\"/\"+d[\"profile\"][\"match\"]") == supported/exact ]]'
check "package label is reported separately from verified data" '[[ $(j $OUT/inspect-good.json "d[\"labels\"][\"display_version\"]") == 1.1.1 ]]'
check "mismatched build IDs are blocked with the exact mismatch" '[[ $(j $OUT/inspect-mismatch.json "d[\"profile\"][\"match\"]") == mismatch ]]'
check "incomplete standalone update is blocked (missing RomFS marker)" '[[ $(j $OUT/inspect-standalone_incomplete.json "d[\"verdict\"]+\"/\"+d[\"layout\"]") == blocked/standalone-update ]]'
check "truncated file is reported as damaged" '[[ $(j $OUT/inspect-truncated.json "d[\"verdict\"]") == blocked ]]'
check "non-NUP file is rejected" '[[ $(j $OUT/inspect-notnup.json "d[\"kind\"]") == unknown ]]'
check "ExeFS/RomFS folder is accepted" '[[ $(j $OUT/inspect-folder_good.json "d[\"verdict\"]") == supported ]]'

E=(env ASTERNUP_DATA_DIR="$DATA" ASTERNUP_BACKEND="$PWD/build/fake_backend/nxnative" ASTERNUP_TEST_FAKE_TOOLCHAIN=1 ASTERNUP_TEST_PLAY_CHECK=clear)
run() { "${E[@]}" "$@" "$APP" --windowed --ui-test "$OUT/script.txt"; }

# 2. Import → build (fake backend) → validate → install → tile
cat > "$OUT/script.txt" <<S
wait 3
import $FX/good.nup
wait 5
press confirm
wait 1
press confirm
wait 9
press back
state $OUT/s-build.json
snap $OUT/home-installed.png
quit
S
run env FAKE_BUILD_MODE=ok
check "build installs the app and registers the tile" '[[ -d "$DATA/Games/Fixture Game.app" && $(j $OUT/s-build.json "len(d[\"entries\"])") == 1 ]]'
H1=$(shasum "$DATA/Games/Fixture Game.app/Contents/Info.plist")

# 3. Failed and cancelled rebuilds keep the installed app
sed -i '' 's/wait 9/wait 5/' "$OUT/script.txt"; run env FAKE_BUILD_MODE=fail
cat > "$OUT/script.txt" <<S
wait 3
import $FX/good.nup
wait 5
press confirm
wait 1
press confirm
wait 3
press confirm
wait 1
press right
press confirm
wait 4
state $OUT/s-cancel.json
quit
S
run env FAKE_BUILD_MODE=slow
check "cancel reports 'Build cancelled'" '[[ "$(j $OUT/s-cancel.json "d[\"banner\"]")" == "Build cancelled" ]]'
check "installed app unchanged after failed and cancelled rebuilds" '[[ "$H1" == "$(shasum "$DATA/Games/Fixture Game.app/Contents/Info.plist")" ]]'
check "no build process left running" '! pgrep -f fake_backend >/dev/null'

# 4. Register two stand-ins, play, HOME, resume (same pid), close (confirmation, default Cancel)
cat > "$OUT/script.txt" <<S
wait 2
register $PWD/build/Stand-in Game.app
register $PWD/build/Stand-in Kart.app
press left
press confirm
wait 4
state $OUT/s-play.json
press home
wait 2
state $OUT/s-home.json
press confirm
wait 2
state $OUT/s-resume.json
press home
wait 1
press x
wait 1
state $OUT/s-dialog.json
press confirm
wait 1
state $OUT/s-cancelled-close.json
press x
press right
press confirm
wait 4
state $OUT/s-closed.json
quit
S
run
pid() { j $1 "[e[\"pid\"] for e in d[\"entries\"] if e[\"title\"]==\"Stand-in Game\"][0]"; }
check "game launched and is tracked" '[[ $(pid $OUT/s-play.json) -gt 0 ]]'
check "HOME brings AsterNUP forward while the game keeps running" '[[ $(j $OUT/s-home.json "d[\"appActive\"]") == True && $(pid $OUT/s-home.json) == $(pid $OUT/s-play.json) ]]'
check "resume reactivates the same instance" '[[ $(pid $OUT/s-resume.json) == $(pid $OUT/s-play.json) && $(j $OUT/s-resume.json "d[\"appActive\"]") == False ]]'
check "close asks for confirmation; default Cancel keeps the game" '[[ $(j $OUT/s-dialog.json "\",\".join(d[\"overlays\"])") == list && $(pid $OUT/s-cancelled-close.json) == $(pid $OUT/s-play.json) ]]'
check "confirmed close quits the game and clears Playing" '[[ $(pid $OUT/s-closed.json) == 0 ]]'

# 4b. A second nxnative game asks first (memory), defaulting to Cancel; an abnormal exit is reported from the game log
LOGDIR="$HOME/Library/Logs/nxnative"; FAKELOG="$LOGDIR/0100000000ABC000.log"; mkdir -p "$LOGDIR"
cat > "$OUT/script.txt" <<S
wait 2
press right
press confirm
wait 4
press home
wait 2
press right
press confirm
wait 1
state $OUT/s-second.json
press confirm
wait 2
state $OUT/s-second-cancel.json
press left
press x
press right
press confirm
wait 5
state $OUT/s-crash.json
quit
S
printf "[RED] GPU access revoked: test line written by Tests/run_ui_tests.sh\n" > "$FAKELOG"
( sleep 6; touch "$FAKELOG" ) &
run
rm -f "$FAKELOG"
check "starting a second nxnative game asks first" '[[ $(j $OUT/s-second.json "d[\"overlays\"][0] if d[\"overlays\"] else \"none\"") == list && $(j $OUT/s-second.json "d[\"rowIndex\"]") == 2 ]]'
check "default Cancel leaves the second game stopped" '[[ $(j $OUT/s-second-cancel.json "[e[\"running\"] for e in d[\"entries\"] if e[\"title\"]==\"Stand-in Kart\"][0]") == False ]]'
check "an abnormal exit in the game log is reported" '[[ "$(j $OUT/s-crash.json "d[\"banner\"]")" == "Stand-in Game stopped: macOS revoked its GPU access after a GPU hang" ]]'

# 4c. The pre-launch check stops on what would cost frames (Low Power Mode here); Cancel starts nothing, Play now starts the game
cat > "$OUT/script.txt" <<S
wait 2
press right
press confirm
wait 1
state $OUT/s-check.json
snap $OUT/play-check.png
press back
wait 1
state $OUT/s-check-cancel.json
press confirm
wait 1
press down
press confirm
wait 4
state $OUT/s-check-play.json
press home
wait 2
press x
press right
press confirm
wait 4
quit
S
run env ASTERNUP_TEST_PLAY_CHECK=lowpower
check "pre-launch check is shown when something would cost frames" '[[ $(j $OUT/s-check.json "\",\".join(d[\"overlays\"])") == list && $(pid $OUT/s-check.json) == 0 ]]'
check "backing out of the check starts nothing" '[[ $(j $OUT/s-check-cancel.json "len(d[\"overlays\"])") == 0 && $(pid $OUT/s-check-cancel.json) == 0 ]]'
check "Play now starts the game" '[[ $(pid $OUT/s-check-play.json) -gt 0 ]]'
check "the check measured this Mac (logged)" 'tail -50 "$HOME/Library/Logs/AsterNUP/AsterNUP.log" | grep -q "play check: others"'

# 5. Controllers panel opens from the dock and lists the controller sections
cat > "$OUT/script.txt" <<S
wait 2
press down
press right
press right
press confirm
wait 1
state $OUT/s-ctrl.json
snap $OUT/controllers.png
quit
S
run
check "Controllers panel opens from the dock" '[[ $(j $OUT/s-ctrl.json "\",\".join(d[\"overlays\"])") == sectioned ]]'

# 6. Persistence across restarts, independent save locations and settings domains
printf "wait 2\nstate $OUT/s-restart.json\nquit\n" > "$OUT/script.txt"; run
check "library persists after restart (3 entries)" '[[ $(j $OUT/s-restart.json "len(d[\"entries\"])") == 3 ]]'
check "save folders are per title" '[[ $($PY -c "import json;L=json.load(open(\"$DATA/library.json\"));print(len({e.get(\"saveFolder\") for e in L}))") == 3 ]]'
echo; (( fail )) && { echo "SOME CHECKS FAILED (artifacts in $OUT)"; exit 1; } || echo "ALL CHECKS PASSED (artifacts in $OUT)"

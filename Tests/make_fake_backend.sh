#!/bin/zsh
# A fake nxnative checkout for UI tests: the real pinned readers (pack_nup.py, dm/games) + a fake build script.
set -euo pipefail
cd "${0:A:h}/.."
REAL="${1:-$HOME/Library/Application Support/AsterNUP/Backend/nxnative}"
FAKE="build/fake_backend/nxnative"
rm -rf "$FAKE"; mkdir -p "$FAKE/scripts" "$FAKE/dm"
ln -s "$REAL/scripts/pack_nup.py" "$FAKE/scripts/pack_nup.py"
ln -s "$REAL/dm/games" "$FAKE/dm/games"; ln -s "$REAL/dm/tools" "$FAKE/dm/tools"
cp Tests/fake_backend_src/build_ipa_from_nsp.py "$FAKE/scripts/"
git -C "$FAKE" init -q && git -C "$FAKE" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fake
echo "$FAKE"

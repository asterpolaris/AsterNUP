#!/bin/zsh
# Fetches nxnative at the revision pinned in Resources/Backend/pins.json (what AsterNUP's "Set up backend" does).
# Usage: scripts/fetch_backend.sh [checkout dir]   (default: ~/Library/Application Support/AsterNUP/Backend/nxnative)
set -euo pipefail
cd "${0:A:h}/.."
PINS=Resources/Backend/pins.json
REPO=$(python3 -c "import json;print(json.load(open('$PINS'))['backends'][0]['repository'])")
COMMIT=$(python3 -c "import json;print(json.load(open('$PINS'))['backends'][0]['commit'])")
DEST="${1:-$HOME/Library/Application Support/AsterNUP/Backend/nxnative}"
if [[ ! -d "$DEST/.git" ]]; then
  mkdir -p "${DEST:h}"; git clone --quiet "$REPO" "$DEST"
else
  [[ -z "$(git -C "$DEST" status --porcelain --untracked-files=no)" ]] || { echo "local changes in $DEST; not touching it" >&2; exit 1; }
  git -C "$DEST" fetch --quiet origin
fi
git -C "$DEST" checkout --quiet --detach "$COMMIT"
echo "nxnative $(git -C "$DEST" rev-parse HEAD) at $DEST"

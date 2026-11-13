#!/bin/zsh
# Removes AsterNUP from this Mac.
#
#   scripts/uninstall.sh          remove AsterNUP.app
#   scripts/uninstall.sh --all    also remove AsterNUP's own data: library, artwork, build folders, the backend checkout,
#                                 its Python environment, the one-line installer's source copy, logs and preferences
#   --yes                         don't ask before removing
#
# Never removed: your dumps, the games AsterNUP built (~/Applications/AsterNUP Games), their saves and settings
# (~/Library/Application Support/nxnative, each game's preferences) and your save backups (~/Documents/AsterNUP Backups).
set -euo pipefail
ALL=0; YES=0
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done

targets=()
for d in "${ASTERNUP_INSTALL_DIR:-$HOME/Applications}" /Applications; do
  app="$d/AsterNUP.app"
  [[ -d "$app" && "$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)" == com.asterpolaris.AsterNUP ]] && targets+=("$app")
done
if (( ALL )); then
  for p in "$HOME/Library/Application Support/AsterNUP" "$HOME/Library/Logs/AsterNUP" \
           "$HOME/Library/Preferences/com.asterpolaris.AsterNUP.plist" "$HOME/Library/Caches/com.asterpolaris.AsterNUP" \
           "$HOME/Library/Saved Application State/com.asterpolaris.AsterNUP.savedState"; do
    [[ -e "$p" ]] && targets+=("$p")
  done
fi
if (( ! ${#targets} )); then echo "Nothing to remove."; exit 0; fi

echo "This removes:"
for t in "${targets[@]}"; do echo "  $t ($(du -sh "$t" 2>/dev/null | cut -f1))"; done
echo "It keeps your dumps, built games, their saves and settings, and save backups."
if (( ! YES )); then
  read -q "?Remove these? [y/N] " || { echo; echo "Nothing removed."; exit 1; }
  echo
fi

osascript -e 'tell application id "com.asterpolaris.AsterNUP" to quit' >/dev/null 2>&1 || true
(( ALL )) && defaults delete com.asterpolaris.AsterNUP >/dev/null 2>&1 || true
for t in "${targets[@]}"; do rm -rf "$t"; done
echo "AsterNUP removed."
(( ALL )) || echo "Its data is still in ~/Library/Application Support/AsterNUP (run with --all to remove it too)."

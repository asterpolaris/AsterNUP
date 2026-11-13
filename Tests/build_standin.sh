#!/bin/zsh
# Builds "Stand-in Game.app" (Tests/StandInGame) into the given folder (default: build/).
set -euo pipefail
cd "${0:A:h}/.."
OUT="${1:-build}"; NAME="${2:-Stand-in Game}"; TID="${3:-0100000000ABC000}"
APP="$OUT/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/dm"
swiftc -O -target arm64-apple-macos14 -o "$APP/Contents/MacOS/nxnative" Tests/StandInGame/main.swift
LTID=$(echo "$TID" | tr 'A-Z' 'a-z')
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>nxnative</string>
<key>CFBundleIdentifier</key><string>org.nxnative.standin.$LTID</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
<key>DMTitleID</key><string>$TID</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PL
cat > "$APP/Contents/Resources/dm/launcher.json" <<'JS'
{"schema": 1, "game": "STANDIN", "settings": [
 {"env": "DM_FPS_TARGET", "kind": "choice", "section": "Game", "label": "Frame rate", "note": "Stand-in setting", "default": "60", "options": [["30", "30 fps"], ["60", "60 fps"]], "level": "basic"},
 {"env": "DM_RENDER_SCALE", "kind": "range", "section": "Game", "label": "Render scale", "note": "Stand-in setting", "default": "1.0", "min": 0.5, "max": 1.0, "step": 0.05},
 {"env": "DM_RUMBLE", "kind": "toggle", "section": "Controls", "label": "Rumble", "default": "on", "on": "on", "off": "off"},
 {"env": "DM_RUMBLE_STRENGTH", "kind": "range", "section": "Controls", "label": "Rumble strength", "default": "1.0", "min": 0.1, "max": 1.0, "step": 0.1, "needs": "DM_RUMBLE=on"}
]}
JS
codesign --force --sign - "$APP" >/dev/null
echo "$APP"

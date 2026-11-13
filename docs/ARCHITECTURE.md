# Architecture

```
Sources/AsterNUP/
  App/        AsterNUPApp (AppKit NSApplication, window, menus), AppModel (coordinator: focus, overlays,
              import/build/play flows), UITestHarness (--ui-test scripts)
  Model/      GameEntry, BuildRecord, HomeSettings; LibraryStore (library.json, atomic writes)
  Backend/    GameBackend protocol (the common interface), NXNativeBackend (nxnative adapter),
              BuildJob (build → stage → validate → swap), Support (paths, processes, hashing)
  Runtime/    SessionManager: actual running game apps (NSRunningApplication), resume, graceful quit
  Input/      InputRouter (GameController, keyboard, global HOME hotkey), HIDGamepads (raw HID fallback)
  Saves/      SaveBackup: verified ZIP backups
  UI/         HomeView (cover row, dock, hints, banners), OverlayViews, Panels (controller-driven surfaces), Theme
Resources/Backend/  asternup_inspect.py (package inspector), pins.json (backend pin + requirements)
Resources/App/      Info.plist, entitlements, icon
```

## Backend interface

`GameBackend` covers what any backend has to provide: status/toolchain checks, a pinned checkout, the profiles it
supports, in-place inspection, build jobs, per-app settings (schema + saved choices), save folder, log file and launch
environment. `NXNativeBackend` implements it on nxnative's documented front-end contract (`docs/frontends.md` in the
checkout): `--progress json` events and exit codes, `launcher.json`, saved choices in the app's preferences domain,
`DM_LAUNCHER=0` when the front end draws the settings, and the save/log paths. A second backend would be another
`GameBackend` type; library entries record `backendID` and `backendCommit`.

## Focus and input

One `NavAction` vocabulary (up/down/left/right/confirm/back/x/y/plus/minus/shoulders/home) from every source.
`AppModel.handle` gives it to the top overlay (`NavSurface`), else to the Home screen (row ↔ dock). Overlays are a stack;
popping one restores the previous focus. Game exit or HOME puts the focus back on that game's tile.

## Data on disk

| What | Where |
|---|---|
| Library, Home settings | `~/Library/Application Support/AsterNUP/library.json`, `home-settings.json` |
| Tile artwork | `~/Library/Application Support/AsterNUP/Artwork/` |
| Backend checkout | `~/Library/Application Support/AsterNUP/Backend/nxnative` (`ASTERNUP_BACKEND` / `BackendPath` default overrides) |
| Build folders (extracted data, shader cache, logs) | `~/Library/Application Support/AsterNUP/Builds/<title ID>/` |
| Installed game apps | `~/Applications/AsterNUP Games/` |
| Game saves / settings / logs (nxnative's) | `~/Library/Application Support/nxnative/<title ID>/save`, the app's preferences domain, `~/Library/Logs/nxnative/<title ID>.log` |
| AsterNUP logs, perf reports | `~/Library/Logs/AsterNUP/` |
| Save backups | `~/Documents/AsterNUP Backups/` (configurable) |

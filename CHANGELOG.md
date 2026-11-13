# Changelog

All notable changes to AsterNUP are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## Unreleased

### Changed

- A more native macOS look. AsterNUP now uses your accent color, system materials and vibrancy, SF Symbols and
  continuous corners. The focused tile lifts like on Apple TV, with a thin accent-colored ring instead of a thick cyan
  frame, and the Home screen picks up a soft wash of the focused game's colors.
- Options, Home settings, Backend & toolchain and Controllers panels look like System Settings: a sidebar with
  colored icons, grouped rows, and real switches, pop-up buttons and steppers. Menus, dialogs and buttons follow macOS
  (the focused button is filled like a default button).
- Notification-style banners, and a new app icon drawn on Apple's icon grid.
- Standard Mac menus: Settings… (⌘,) in the AsterNUP menu, Edit (copy from panels), Window, and Help with links to
  the guides, acknowledgements and issue forms. About AsterNUP shows credits.
- The installer sets up the backend's tools and Python environment by default; `--deps` is no longer needed.

### Added

- One-line installer: `curl -fsSL https://raw.githubusercontent.com/asterpolaris/AsterNUP/main/scripts/install.sh | zsh`.
  It installs the Homebrew tools and the backend's Python environment by default (`--no-deps` skips them). Run it
  again to update.
- `scripts/uninstall.sh` to remove AsterNUP (`--all` also removes its library, artwork, build folders and backend;
  game saves and save backups are always kept).
- A `Makefile` (`make` lists the targets: `app`, `run`, `install`, `uninstall`, `dmg`, `test`, `icon`, `clean`, …).
- GitHub Actions: a build check on every push and pull request, and a draft release with the disk image for each
  version tag.
- Getting started and troubleshooting guides, acknowledgements, contributing guide, security policy and issue forms.

### Removed

- The internal validation report (`docs/REPORT.md`).
- `THIRD_PARTY_NOTICES.md`, now part of `ACKNOWLEDGEMENTS.md`.

## 0.1.0 — 2026-11-12

First release.

- Controller-first game library and launcher for Apple silicon Macs: a row of games, a dock of actions, button hints,
  banners, Light and Dark Mode, full screen.
- Import a `.nup` dump or an ExeFS/RomFS folder in place, never modified. The report shows title ID, platform, layout,
  package and verified versions, build IDs read from the code, the backend profile match, integrity, and each issue
  with its next step.
- Build and install with the pinned nxnative backend: disk check, real progress and ETA, cancel, staging, validation
  (arm64, title ID, signature) and a safe swap that keeps the previous app until the new one is in place.
- Add existing game apps, with full integration for nxnative-built apps.
- Sessions: start, HOME back to AsterNUP while the game keeps running, resume the same instance, confirmed close.
  Starting a second nxnative game asks first.
- Per-game settings drawn from each built app's `launcher.json`, saved to the game's own preferences.
- Save data: reveal the save folder, and verified ZIP backups.
- Controllers: Nintendo Switch Pro Controller, Joy-Con, Xbox, PlayStation and MFi controllers, raw HID for gamepads
  macOS pairs but doesn't list, A/B by label or by position, and Switch 2 controllers inside nxnative games.
  Keyboard HOME shortcut (⌃⌥H by default).
- Pre-launch check for memory-hungry apps, Low Power Mode and thermal state; opts out of macOS Game Mode.
- `scripts/install.sh`, `scripts/make_app.sh`, `scripts/make_dmg.sh`, `scripts/build_game.sh`,
  `scripts/check_toolchain.sh`, `scripts/fetch_backend.sh` and `scripts/perf_session.py`.

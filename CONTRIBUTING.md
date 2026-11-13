# Contributing to AsterNUP

Thanks for helping. Bug reports, controller test results, fixes and docs are all welcome.

## Before you start

- **Game compatibility and emulation bugs belong upstream.** If a game builds but renders wrong, crashes, stutters
  or sounds wrong, that's [nxnative](https://github.com/seedds/nxnative/issues). AsterNUP issues are about the
  launcher: importing, the report, the build flow, the library, sessions, HOME, settings, saves, controllers on the
  Home screen, and installing.
- **Never commit or attach game content.** No dumps (`.nup`, `.nsp`, `.nsz`, `.xci`), keys, extracted ExeFS/RomFS
  content, generated game apps, shader caches or saves, in commits, issues, pull requests or screenshots of
  copyrighted artwork. `.gitignore` covers the usual paths; please check `git status` before committing anyway.

## Build from source

You need an Apple silicon Mac with macOS 14 or later and Swift 5.10 or later (Xcode, or just the Command Line Tools).

```bash
git clone https://github.com/asterpolaris/AsterNUP.git
cd AsterNUP
make app          # builds build/AsterNUP.app (same as scripts/make_app.sh)
make install      # builds and installs to ~/Applications, sets up the backend, opens AsterNUP
```

Or open `AsterNUP.xcodeproj` and run the shared **AsterNUP** scheme (it passes `--windowed`). The Xcode project is
generated from `project.yml`: after editing that file, run `xcodegen generate` and commit both. `Package.swift` builds
the same sources from the command line.

Signing, the backend's Python environment and moving the backend pin are covered in
[docs/BUILDING.md](docs/BUILDING.md).

## Run the tests

```bash
scripts/fetch_backend.sh   # once: the pinned nxnative checkout the inspector tests read
make test                  # same as Tests/run_ui_tests.sh
```

The tests need the pinned backend and an arm64 Python 3.12 or later. They don't need a dump, Xcode or a controller:
they use synthetic NUP fixtures, stand-in game apps, a fake build script that speaks nxnative's progress protocol, and
an isolated data folder, so your real library is untouched. Every check should print `PASS`.

## Code layout

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit, the backend interface and where data lives.

## Style

- **Native macOS look.** Use system colors, the system accent color and materials through `UI/Theme.swift` rather
  than hard-coded colors, so AsterNUP follows Light and Dark Mode and the user's accent color. SF Symbols for icons,
  the system font, continuous corner radii.
- **Controller first.** Every action must be reachable with a controller *and* with the keyboard, and should work
  with the mouse too. New screens are `NavSurface`s that return hints for the bottom bar.
- **Say what's true.** Labels, reports and errors should say exactly what was checked and what the next step is.
  Don't present unverified data (like a packer's version label) as verified.
- **Never touch the user's dump or saves.** Dumps are read in place. Builds stage, validate, then swap.
- Keep changes focused, and match the surrounding code style.

## Pull requests

1. Fork, branch from `main`, make your change.
2. Run `make test` and try the change in the app (with a controller if it touches input).
3. Update the docs and `CHANGELOG.md` (under **Unreleased**) when behaviour changes.
4. Open the pull request with a short description of what changed and how you tested it.

By contributing, you agree your contribution is released under the [MIT License](LICENSE).

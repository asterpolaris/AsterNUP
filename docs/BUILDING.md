# Building AsterNUP and game apps

## Requirements

| For | Needs |
|---|---|
| AsterNUP itself | Apple silicon Mac, macOS 14+, Swift 5.10+ (Xcode, or the Command Line Tools alone via `scripts/make_app.sh`) |
| Inspecting dumps | The nxnative checkout at the pinned commit; arm64 Python 3.12+ with the zstd module (built into 3.14) |
| Building games (pinned nxnative `034e91a8a6`) | macOS 26.6+, **Xcode 27.2** selected with `xcode-select`, Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`), `brew install xcodegen zstd glslang python@3.14`, nxnative's Python modules in AsterNUP's own venv (the installer sets this up, or **Backend & toolchain → Set up Python environment**), disk space ≈ 2× the game + 10 GB |

`scripts/check_toolchain.sh` (or **Backend & toolchain** in the app) checks all of this and prints the fix for each missing piece.

## Build AsterNUP

### Xcode

1. Open `AsterNUP.xcodeproj`. The shared scheme **AsterNUP** builds an arm64 app; Run passes `--windowed`.
2. Signing: copy your values into `Config/Local.xcconfig` (git-ignored; it's included by `Config/Signing.xcconfig`):

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   CODE_SIGN_IDENTITY = Apple Development
   CODE_SIGN_STYLE = Automatic
   ```

   Without it the app is signed ad-hoc (`-`), which runs locally.
3. After editing `project.yml`, regenerate with `xcodegen generate`.

### Command line (no Xcode needed)

```bash
scripts/make_app.sh                                          # ad-hoc signed build/AsterNUP.app
ASTERNUP_SIGN_IDENTITY="Apple Development: Your Name (ABCDE12345)" scripts/make_app.sh
```

The script builds with SwiftPM (`Package.swift`, same sources), bundles `Resources/Backend` (inspector + pin), signs
with Hardened Runtime and verifies the signature and the arm64 slice.

AsterNUP is not sandboxed: it runs the backend's Python tools, writes each nxnative game's preferences domain (the
game's saved choices, as nxnative's front-end contract describes) and launches game apps.

## Signing generated game apps (separate from AsterNUP)

nxnative signs the game apps it packs. By default that's **ad-hoc**, which runs on the Mac that built it.
To sign with your certificate, set it once and AsterNUP passes it to every build as `--mac-sign` / `--team-id`:

```bash
defaults write com.asterpolaris.AsterNUP GameSigningIdentity "Apple Development: Your Name (ABCDE12345)"
defaults write com.asterpolaris.AsterNUP TeamID ABCDE12345
```

nxnative's packer leaves out the **Hardened Runtime** on game apps, because the host maps executable memory for the
game's rewritten code. Consequences:

- Local execution: works (ad-hoc or Apple Development). AsterNUP validates each staged app before installing it:
  executable present, every Mach-O in `Contents/MacOS` is arm64, `DMTitleID` matches the dump, and `codesign --verify --deep --strict`.
- **Notarization: not available** for these game apps as packed, since Apple requires the Hardened Runtime for
  notarization. They're for local play on your own Mac, not distribution. AsterNUP itself *can* be notarized (Developer
  ID + Hardened Runtime, which `make_app.sh` already enables): `xcrun notarytool submit AsterNUP.zip --keychain-profile <profile> --wait`.
  Notarization of AsterNUP has not been performed yet.

## The backend's Python environment

AsterNUP never installs into Homebrew's or the system's Python (Homebrew Python refuses it, PEP 668). It keeps a venv at
`~/Library/Application Support/AsterNUP/Backend/venv`, made from Python 3.14 when available (nxnative's primary version),
and runs the inspector and every build with it. Create or repair it with `scripts/install.sh --no-open` or
**Backend & toolchain → Set up Python environment**. Override the location with `ASTERNUP_VENV`.

## Fetching the backend without the app

```bash
scripts/fetch_backend.sh             # ~/Library/Application Support/AsterNUP/Backend/nxnative at the pinned commit
```

To move the pin: change `commit` in `Resources/Backend/pins.json`, review
`git log -p OLD..NEW -- docs/frontends.md docs/launcher.schema.json dm/games/settings.tsv` and
`git log OLD..NEW --grep='^Front-ends:'` in the checkout (nxnative's guidance for front ends), rebuild AsterNUP,
then **Set up backend** again. A checkout with local changes is never overwritten.

## Make targets

| Command | Does |
|---|---|
| `make app` | Builds `build/AsterNUP.app` (`scripts/make_app.sh`) |
| `make run` | Builds and opens AsterNUP in a window |
| `make install` | Builds and installs AsterNUP, sets up the backend and opens it (`scripts/install.sh`) |
| `make uninstall` | Removes AsterNUP.app (`scripts/uninstall.sh`; add `--all` to the script to remove its data too) |
| `make dmg` | Builds `build/AsterNUP-<version>.dmg` (`scripts/make_dmg.sh`) |
| `make test` | Runs the automated checks (`Tests/run_ui_tests.sh`) |
| `make icon` | Re-renders `Resources/App/AppIcon.icns` (`scripts/make_icon.swift`) |
| `make project` | Regenerates `AsterNUP.xcodeproj` from `project.yml` (needs XcodeGen) |
| `make backend` / `make check` | Fetches the pinned backend / checks the game-build toolchain |
| `make clean` | Removes `build/` and `.build/` |

Run `make` on its own to list them.

## Continuous integration and releases

`.github/workflows/build.yml` builds the app on every push to `main` and every pull request (an Apple silicon
`macos-26` runner). `.github/workflows/release.yml` runs when you push a version tag:

1. Set `MARKETING_VERSION` in `Config/Signing.xcconfig` and add the version's section to `CHANGELOG.md`.
2. `git tag v0.2.0 && git push origin v0.2.0`
3. The workflow builds `AsterNUP-0.2.0.dmg` and opens a **draft** release with it and the changelog section.
   Review it, then publish.

The workflow's app is ad-hoc signed and not notarized, so first launch on another Mac needs **Open Anyway** in
System Settings › Privacy & Security. To ship a notarized build, build and sign the DMG on a Mac with your Developer ID
(`ASTERNUP_SIGN_IDENTITY="Developer ID Application: …" scripts/make_dmg.sh`), notarize it as `make_dmg.sh` describes,
and attach it to the draft instead.

## Tests

```bash
make test                # or Tests/run_ui_tests.sh
```

No dump, Xcode or controller needed: synthetic NUP fixtures (fake headers only), stand-in game apps, a fake build
script speaking nxnative's `--progress json` protocol, and an isolated data folder (`ASTERNUP_DATA_DIR`), so your
real library is untouched. AsterNUP's `--ui-test <script>` harness drives its own actions and snapshots its own
window (no Screen Recording permission needed).

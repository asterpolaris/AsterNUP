# Adding games

Everything here happens inside the running launcher. Adding a game never requires rebuilding AsterNUP.

## Import a dump (`.nup` or ExeFS/RomFS folder)

1. **Add a game → Import a dump** (or the dock's first button, ⌘O, or drop the file on the window).
   The picker lists `.nup` files and dump folders it finds in Downloads, Desktop, Documents, `~/Games` and external
   drives, plus **Browse with Finder…**. Your dump is read **in place**: never modified, moved, renamed or unpacked by hand.
2. **Read the report.** AsterNUP runs `Resources/Backend/asternup_inspect.py` with the pinned nxnative's own NUP reader and
   profiles, and shows:
   - title ID, platform (Switch / Switch 2 by title ID), input type, size
   - **layout**: base only, base + update, or standalone update (no base). Whether the input is a complete playable build
   - **package version** (the container's NCM version record)
   - **verified version**: from the backend profile's registered build (when the code matches) or the console control data (NACP)
   - **package label**: the display version the packer typed into the NUP, shown in orange as *not verified*
   - **build IDs** read from the code modules themselves (`main`, `subsdk*`, `sdk`; SHA-256 checked as read)
   - **profile match**: `exact`, `mismatch` (with the exact module that differs), `unregistered` (with the registered builds), or no profile
   - integrity: table of contents + code verified; **Verify all hashes** checks every file
   - issues, each with the next step (damaged file, missing base, incomplete standalone update, wrong build, …)

   Verdicts: **Supported** (exact match), **Provisional** (playable input, no registered build: nxnative would try a
   provisional profile that may not start), **Blocked** (fix the listed issue first). Nothing reaches shader compilation
   until the report is clean.
3. **Build & install.** The confirmation shows disk needed/free, the backend commit and the output path. The build runs:

   ```
   python3 scripts/build_ipa_from_nsp.py <your dump> --platform mac-app --progress json --no-seen-shaders \
       --work-dir ~/Library/Application Support/AsterNUP/Builds/<title ID> -o <staging>/<Name>.app --app-name <Name> \
       --package v<N> [--fallback-icon …] [--mac-sign … --team-id …]
   ```

   That's the documented command shape plus front-end flags (`--progress json`, `--work-dir`, `-o`). `--no-seen-shaders`
   forces the **full shader set**. Progress shows real stages, steps, counts and ETA from nxnative's JSON events.
   **Cancel** (with confirmation) sends SIGTERM, as nxnative's contract asks.
4. **Staging and safety.** The app is written to a staging folder, validated (arm64, `DMTitleID`, signature), then swapped
   into `~/Applications/AsterNUP Games/`. The previous app is kept until the new one is in place. On cancel, failure or an
   interrupted rebuild, the dump, any previously working app and the saves (`~/Library/Application Support/nxnative/<title ID>/save`)
   are untouched. Errors show the backend's own `[RED]` reason plus the log paths
   (`…/Builds/<title ID>/logs/` and `~/Library/Logs/AsterNUP/build-*.log`).
5. The tile appears in the library with the game's icon and **Ver.** line. Rebuilding the same title (e.g. a new update)
   updates the same tile and keeps its settings and saves.

## Choose an existing game app

**Add a game → Choose an existing game app** lists apps in `~/Applications/AsterNUP Games`, `/Applications`,
`~/Applications` and `/Applications/Games` (games first), or **Browse with Finder…**. An nxnative-built app (its
`Info.plist` has `DMTitleID`) is registered with full integration: its settings, save folder and log. Any other app
gets launch, HOME/resume and close.

## Per-game options (+ on a tile)

- **Game settings**: drawn from the built app's own `Contents/Resources/dm/launcher.json` (frame rate, render scale,
  console/handheld mode, rumble, pipeline preparation, Switch 2 controllers, diagnostics… whatever that build offers).
  Choices are written to the game's own preferences domain (`launcher.<ENV>`), only when they differ from the tested
  default, so the game also uses them when started from Finder. **Reset to tested defaults** removes them.
- **Launch**: frame-time capture (`DM_NVN_TSV`) for performance reports.
- **Save data**: reveal the actual save folder; **Create ZIP backup** (only while the game is closed) writes
  `~/Documents/AsterNUP Backups/<Game>/<Game> save <date>.zip`, verified by extracting it and comparing every file's SHA-256.
- **Manage software**: build details (title ID, package/verified/label versions, build IDs, backend commit, paths),
  reveal app, game log, build logs, rebuild from dump, remove from library (keeps app, dump and saves).

Settings and saves are isolated per title: each nxnative game has its own bundle ID, preferences domain and save folder.

## The next game, step by step

1. Check it's supported by the pinned backend: **Backend & toolchain → Supported games** lists the backend's profiles
   and registered builds (e.g. Donkey Kong Bananza, Mario Kart World…).
2. Dump the game **with its update** into one `.nup` (base + update). If you only have a standalone update, the report
   says whether the profile's marker file is present; if it isn't, pack the base game too.
3. Copy the `.nup` to this Mac (anywhere: Downloads is fine).
4. **Add a game → Import a dump**, pick it, read the report. If it says *unregistered* or *mismatch*, the report names the
   registered builds: dump the matching update, or wait for/choose a backend revision that registers yours
   (move the pin as described in BUILDING.md).
5. **Build & install**, then start it from its tile.

## Command line equivalent

```bash
scripts/build_game.sh ~/Downloads/game.nup     # inspect, check toolchain, run the documented command, write a build record
```

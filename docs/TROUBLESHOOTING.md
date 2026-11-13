# Troubleshooting

Most problems show up in **Backend & toolchain** (in the dock), which checks everything AsterNUP and the backend need
and lists the fix for each missing piece. From the source folder, `scripts/check_toolchain.sh` runs the same checks.

## Installing

### AsterNUP can't be opened

If macOS says it can't verify the developer, AsterNUP was signed on another Mac without an Apple Developer ID. Open
**System Settings › Privacy & Security**, scroll down to the message about AsterNUP and choose **Open Anyway**. Or in
Terminal:

```bash
xattr -dr com.apple.quarantine ~/Applications/AsterNUP.app
```

(Use `/Applications/AsterNUP.app` if you installed it from the disk image.)

### The installer stops at "No Swift compiler"

It started the Command Line Tools installer. Finish that, then run the install command again.

### Homebrew isn't installed

Install it from [brew.sh](https://brew.sh) (it asks for your password), then run the install command again.

## Backend and toolchain

### "Backend needs setup" or "Building needs setup"

Open **Backend & toolchain** and choose **Set up backend**. It fetches nxnative at the pinned version. A backend
checkout with your own local changes is never overwritten.

### Python modules missing

Choose **Backend & toolchain › Set up Python environment**, or from the source folder run:

```bash
scripts/install.sh --no-open
```

The modules go into AsterNUP's own environment (`~/Library/Application Support/AsterNUP/Backend/venv`), never into
Homebrew's or the system's Python. If no suitable Python is found, run `brew install python@3.14` first.

### Wrong Xcode version

The pinned backend needs a specific Xcode (27.2 at the time of writing; **Backend & toolchain** shows the exact one).
Install it from [developer.apple.com/download](https://developer.apple.com/download/), then select it:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

If you keep several Xcode versions, point `xcode-select` at the right one.

### Metal toolchain missing

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Importing

### The report says "unregistered"

Your dump is a different version than the builds the backend has been tested with. The report lists the registered
versions. Dump the matching update, or wait for a backend version that registers yours.

### The report says "mismatch"

The package version matches, but the code doesn't. The report names each module that differs. This usually means a
modified dump or another release. Dump the game again.

### The report says "standalone update"

The dump only has the update, which holds just the changed files. Dump the base game and the update together into one
`.nup`.

### The report says "damaged"

The file is incomplete or corrupt, often from an interrupted copy. Copy it again, then choose **Verify all hashes**.

## Building

### Not enough disk space

The first build needs about twice the game's size plus 10 GB free. AsterNUP checks before it starts. Free up space on
the internal drive; the dump itself can stay on an external drive.

### The build failed

The build panel shows the backend's own reason. Choose **Open logs** for the details. Logs are in:

- `~/Library/Application Support/AsterNUP/Builds/<title ID>/logs/`
- `~/Library/Logs/AsterNUP/`

A failed or cancelled build never changes your dump, a game you'd already installed, or its saves.

## Playing

### HOME opens the Games app instead of AsterNUP

macOS can claim the HOME button. Change it in **System Settings › Game Controllers**, or turn on
**Home settings › Press − and + together for HOME**. The keyboard shortcut (⌃⌥H by default) always works.

### Switch 2 controllers don't move around the Home screen

Joy-Con 2 and Pro Controller 2 connect directly to the running game, not to macOS, so AsterNUP can't read them. Use
them in games, and press ⌃⌥H to come back to AsterNUP. See [Controllers](CONTROLLERS.md#switch-2-controllers-and-home).

### Low or uneven frame rate

See [Smoothest play](PERFORMANCE.md). In short: quit memory-hungry apps (AsterNUP's pre-launch check offers to), turn
off Low Power Mode, make sure macOS Game Mode is off, and try **30 fps** in the game's settings on smaller Macs.

### The game quit with "GPU access revoked"

The GPU stopped responding and macOS ended the game. AsterNUP shows the reason and the game's log path. Save often,
note where it happened, and report it to [nxnative](https://github.com/seedds/nxnative/issues): it's a backend issue.

## Where things are

See the table in [Architecture › Data on disk](ARCHITECTURE.md#data-on-disk) for the library, build folders,
installed games, saves, logs and backups.

## Reporting a bug

Open an issue on GitHub. Please include:

- AsterNUP's version (**AsterNUP › About AsterNUP**)
- your Mac's chip and memory, and the macOS version
- the nxnative commit from **Backend & toolchain**
- what you did, what you expected and what happened
- relevant log lines, pasted as text

If the problem is how a game runs (graphics, sound, crashes in game), report it to
[nxnative](https://github.com/seedds/nxnative/issues) instead.

Never attach dumps, keys, extracted game files, built game apps or saves.

# Getting started

This guide takes you from nothing to playing a game you own on your Mac. It takes about an hour, most of it
downloading Xcode and waiting for the first build.

## 1. Check your Mac

| To | You need |
|---|---|
| Run AsterNUP | A Mac with Apple silicon (M1 or later), macOS 14 or later |
| Build games | macOS 26.6 or later, **Xcode 27.2** and its Metal toolchain, [Homebrew](https://brew.sh), and free disk space of about twice the game's size plus 10 GB |
| Play smoothly | 16 GB of memory or more. See [Smoothest play](PERFORMANCE.md) |

Building games depends on the pinned nxnative backend. Its exact requirements are listed in **Backend & toolchain**
inside AsterNUP.

## 2. Install AsterNUP

Open Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/asterpolaris/AsterNUP/main/scripts/install.sh | zsh
```

The installer:

1. checks your Mac and starts the Command Line Tools installer if Swift is missing (finish it, then run the command again)
2. downloads AsterNUP's source to `~/Library/Application Support/AsterNUP/Source` and builds it
3. installs **AsterNUP** in `~/Applications`
4. installs the Homebrew tools the backend needs and sets up the backend's own Python environment
   (add `--no-deps` to skip this step)
5. fetches the nxnative backend at its pinned version
6. checks the game-build toolchain and tells you exactly what's missing
7. opens AsterNUP

To pass options through the one-liner, add them after `zsh -s --`, for example
`curl -fsSL …/install.sh | zsh -s -- --no-deps`.

**To update**, run the same command again.

Other ways to install:

- **Disk image.** Download `AsterNUP-<version>.dmg` from the project's GitHub Releases, open it and drag AsterNUP
  to Applications. Then open **Backend & toolchain** in AsterNUP and choose **Set up backend** and
  **Set up Python environment**.
- **From a clone.** `git clone https://github.com/asterpolaris/AsterNUP.git && cd AsterNUP && make install`.

If macOS says AsterNUP can't be opened, see [Troubleshooting](TROUBLESHOOTING.md#asternup-cant-be-opened).

## 3. Set up the game toolchain

AsterNUP can inspect dumps right away. To build games, install Apple's developer tools:

1. Download **Xcode 27.2** from [developer.apple.com/download](https://developer.apple.com/download/) (it needs your
   Apple Account) and move it to Applications.
2. In Terminal:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -downloadComponent MetalToolchain
   ```

3. Check everything: open **Backend & toolchain** in AsterNUP's dock, or run `scripts/check_toolchain.sh` from the
   source folder. Each missing piece is listed with its fix. When it says the Mac can build games, you're ready.

## 4. Dump your game

AsterNUP works only with games you own. It never downloads games, keys or updates.

- Dump the game **together with its update** into one `.nup` file (base game + update). A standalone update usually
  isn't enough on its own.
- Copy the `.nup` anywhere on your Mac. Downloads is fine. An ExeFS/RomFS dump folder works too.

## 5. Import and build

1. In AsterNUP choose **Import a dump** (the first button in the dock, or ⌘O), or drop the file on the window.
2. Pick your dump. AsterNUP reads it in place and never changes it.
3. **Read the report.** It tells you what the dump is and whether the backend supports it:
   - **Supported build**: the code matches a build the backend has been tested with. Go ahead.
   - **Provisional**: the dump is complete but this build isn't registered. It may not start.
   - **Can't build this input yet**: the report names the problem and the next step, such as dumping the matching
     update.
4. Choose **Build & install**. The confirmation shows the disk space needed and where the game goes.

The first build takes 30 to 60 minutes. You can choose **Run in background** and keep using AsterNUP; progress shows
at the top of the Home screen. If you cancel or the build fails, nothing you had is changed.

When it's done, the game appears in your library, installed in `~/Applications/AsterNUP Games`.

## 6. Play

| To | Controller | Keyboard |
|---|---|---|
| Start or resume a game | A on its tile | Return |
| Come back to AsterNUP while playing | HOME (short press), or − and + together | ⌃⌥H |
| Close a game | X on a Playing tile | X |
| Game options | + on a tile | O |

Pressing HOME leaves the game running: its tile shows **Playing**, and A resumes exactly where you were. A long press
of HOME (2 seconds) opens the game's own quit prompt.

**Options** on a tile has the game's own settings (frame rate, resolution, display mode and more, each with its
tested default), launch options, save data and build details.

More on controllers in [Controllers](CONTROLLERS.md), and on frame rate in [Smoothest play](PERFORMANCE.md).

## 7. Keep your saves safe

Saves live with the game in `~/Library/Application Support/nxnative/<title ID>/save`. To back them up, close the game,
then choose **Options › Save data › Create ZIP backup**. Backups go to `~/Documents/AsterNUP Backups` and are checked
file by file after they're written. Rebuilding or removing a game never touches its saves.

## 8. Update or uninstall

- **Update AsterNUP**: run the install command again.
- **Update a game** (for example after dumping a newer update): import the new dump and build it. It replaces the same
  tile and keeps its settings and saves.
- **Uninstall**: run the uninstaller from the source folder. If you used the one-line installer, that's:

  ```bash
  ~/Library/Application\ Support/AsterNUP/Source/scripts/uninstall.sh
  ```

  This removes the app. `scripts/uninstall.sh --all` also removes AsterNUP's library, artwork, build folders and the
  backend. Neither ever removes your game saves (`~/Library/Application Support/nxnative`) or your backups
  (`~/Documents/AsterNUP Backups`). Installed games in `~/Applications/AsterNUP Games` are yours to keep or delete.

## Next

- [Adding games](ADDING_GAMES.md): the full import, report and build flow, and adding your next game
- [Controllers](CONTROLLERS.md): Nintendo and other controllers, HOME
- [Smoothest play](PERFORMANCE.md): getting a steady frame rate
- [Troubleshooting](TROUBLESHOOTING.md): when something doesn't work

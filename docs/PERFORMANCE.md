# Smoothest play

What decides an nxnative game's frame rate on a Mac, what AsterNUP does about it, and what you can set.
Figures are from the pinned backend's notes (`dm/games/0400486024DEC000/README.md`, `docs/reference/frame-rate.md`).

## Why the frame rate drops

Ocarina of Time runs at 60 fps only while each frame's GPU work fits in one 60 Hz refresh (16.7 ms). When it doesn't,
nxnative's frame step holds the frame for two refreshes (30 fps) and the game's clock follows, so the game keeps real-time
speed but drops to 30 for a while, then tries 60 again. Measured at full resolution in Kokiri Forest:

| Mac | GPU per frame | Result |
|---|---|---|
| M5 Pro, 20-core GPU | ~10 ms | locked 60 in a window |
| M4 Pro, 20-core GPU | ~15 ms | 48 fps average: often held at 30 |
| Smaller GPUs (M4 10-core, M1/M2/M3 base) | not measured, expect roughly 2× the M4 Pro's | 30 fps most of the time |

This game's GPU cost hardly depends on resolution (683×384 cost 14.3 ms, 1536×864 cost 14.7 ms on an M4 Pro), so lowering
resolution barely helps. The other big costs are memory pressure (the game keeps about 11 GB) and a GPU running at low clocks.

## What AsterNUP does

- **Steps back while you play.** While a game is in front, AsterNUP only watches for HOME. Raw HID gamepads deliver only the
  HOME button to it (IOKit stops queueing stick, trigger and motion reports for the launcher), and the GameController
  stick, d-pad and face-button handlers are removed. Everything comes back when AsterNUP is in front again.
- **Checks the Mac before a game starts** (Home settings › Playing; on by default). It appears only when something would cost frames:
  - other apps holding more memory than the Mac can spare beside the game (16 GB Mac: more than 1.5 GB). It lists them,
    counting each app's helper processes (browser tabs, Electron renderers), and offers **Quit these apps and play** or
    quitting them one at a time. Apps are asked to quit as ⌘Q would, so they can still ask you to save.
  - **Low Power Mode** on (lower GPU clocks). AsterNUP opens Battery settings; it can't change the setting itself.
  - the Mac already **hot** (thermal state serious or critical).
- **Opts out of macOS Game Mode** (`LSSupportsGameMode` false), as nxnative's game apps do: Game Mode was measured holding
  the GPU at its lowest clock after 45 s to 3 minutes, halving the frame rate. macOS remembers apps it has already treated
  as games, so if AsterNUP or a game ever ran in Game Mode, turn it off once: in full screen press ⌘-Esc for the Game
  Overlay, then Settings › Game Mode. To check:
  ```bash
  /usr/bin/log show --last 10m --predicate 'process == "gamepolicyd"' --style compact | grep -E "Found game|Game mode|DPS"
  ```

## What you can set (Options › Game settings)

- **Frame rate: 30 fps** on a Mac that can't hold 60. Steady 30 looks smoother than switching between 60 and 30.
- **Display mode:** a window and fullscreen both reach 60 on the M5 Pro. On a ProMotion MacBook Pro, fullscreen switches the
  screen to fixed 60 Hz for the game (the backend's fix for a 40 fps bug); if you still see ~40 fps in fullscreen, use a window.
- **Dynamic resolution:** off by default. On the M4 Pro it reached 60 fps at a lower resolution, but in heavier scenes it
  drops to its floor (683×384) without helping. Try it on a Mac that sits at 30.
- **Upscaling: MetalFX** costs no measurable GPU time in this game and looks sharper in a large window or in fullscreen.
- Keep the game on the internal drive (games install to `~/Applications/AsterNUP Games`).

## Measuring

Turn on **Options › Launch › Frame-time capture**, or run a 10-minute session:

```bash
scripts/perf_session.py "$HOME/Applications/AsterNUP Games/<game>.app" --minutes 10
```

The report gives median/p95/p99 frame time, frames over 16.7 ms, stalls, swap and peak memory. **Performance HUD**
(Options › Game settings › Performance) shows Apple's Metal HUD in the game.

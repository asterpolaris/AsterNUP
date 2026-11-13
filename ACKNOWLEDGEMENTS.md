# Acknowledgements

AsterNUP is a front end. The hard part, turning a game you own into a native Mac app, is done by other people's
work. Thank you to everyone below.

## nxnative

[nxnative](https://github.com/seedds/nxnative) by **seedds** and its contributors is the backend that does the real
work: it reads your dump, rewrites the game's code for Apple silicon, translates its shaders to Metal and packs a native
Mac app. AsterNUP only drives it: it fetches nxnative at the commit pinned in `Resources/Backend/pins.json`, runs its
documented front-end commands (`build_ipa_from_nsp.py`, `pack_nup.py`, `dm/games/game.py`), reads its progress events,
profiles and `launcher.json`, and launches the apps it builds.

If a game builds, starts and plays well, that's nxnative. Game compatibility and emulation bugs belong in
[nxnative's issues](https://github.com/seedds/nxnative/issues).

nxnative includes third-party code of its own, such as Ryujinx's shader translator, SPIRV-Cross and glslang. Each keeps
its own license; see `dm/third_party/README.md` in the nxnative checkout
(`~/Library/Application Support/AsterNUP/Backend/nxnative`).

## Third-party notices

AsterNUP does not vendor third-party source code. It uses these projects at build time or runtime:

| Project | How AsterNUP uses it | License |
|---|---|---|
| [nxnative](https://github.com/seedds/nxnative) | Game backend, fetched at a pinned commit into `~/Library/Application Support/AsterNUP/Backend/nxnative` | MIT |
| [NUP container format](https://github.com/a55uka/nup) | The `.nup` dump format. `Tests/make_fixture_nup.py` writes synthetic containers following SPEC v1; the inspector reads real ones through nxnative's reader | See the project |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Generates `AsterNUP.xcodeproj` from `project.yml`; also one of nxnative's build tools. Not shipped | MIT |
| [Homebrew](https://brew.sh) | Installs the tools nxnative needs to build games: `xcodegen`, `zstd`, `glslang`, `python@3.14` | BSD-2-Clause |
| [Zstandard](https://github.com/facebook/zstd) | Installed by Homebrew for nxnative | See the project |
| [glslang](https://github.com/KhronosGroup/glslang) | Installed by Homebrew for nxnative | See the project |
| [python-lz4](https://github.com/python-lz4/python-lz4) | Installed into AsterNUP's backend Python environment | BSD-3-Clause |
| [Capstone](https://github.com/capstone-engine/capstone) | Installed into AsterNUP's backend Python environment | BSD-3-Clause |
| [fontTools](https://github.com/fonttools/fonttools) | Installed into AsterNUP's backend Python environment | MIT |
| [nsz](https://github.com/nicoboss/nsz) | Installed into AsterNUP's backend Python environment | See the project |
| zbic | Installed into AsterNUP's backend Python environment | See the project |
| [backports.zstd](https://pypi.org/project/backports.zstd/) | Installed into AsterNUP's backend Python environment on Python older than 3.14 | See the project |

The Python packages are installed from PyPI into AsterNUP's own virtual environment
(`~/Library/Application Support/AsterNUP/Backend/venv`), never into Homebrew's or the system's Python.

## Apple frameworks

AsterNUP is written in Swift with SwiftUI and AppKit. Controllers come through the GameController framework, with an
IOKit HID fallback for gamepads macOS pairs but doesn't list. The global HOME shortcut uses Carbon's hotkey API.

## Inspiration

These projects shaped how AsterNUP looks and behaves. AsterNUP isn't affiliated with any of them.

- [OpenEmu](https://openemu.org), for showing that a game library on the Mac can be controller-first and still feel
  like a Mac app.
- [Whisky](https://github.com/Whisky-App/Whisky), for showing that a complex toolchain can sit behind a friendly,
  native front end.
- The Apple TV focus engine, for the way a focused tile lifts, and how focus moves predictably with a remote or a
  controller.
- Console home screens in general, for the row of games, a dock of system actions, and HOME always bringing you back.

## Trademarks and content

Nintendo Switch, Joy-Con and related names are trademarks of Nintendo. Apple, Mac, macOS, Xcode and Metal are
trademarks of Apple Inc. AsterNUP is not affiliated with, endorsed or sponsored by Nintendo, Apple or any game
publisher.

This repository contains no game code, game data, keys or game artwork. AsterNUP never downloads games or keys: you
bring a dump of a game you own.

AsterNUP itself is released under the [MIT License](LICENSE).

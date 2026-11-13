# Controllers

AsterNUP's Home screen is driven by controllers first; keyboard and mouse do everything too. The **Controllers**
button in the dock shows what's connected and how its buttons are mapped.

## Nintendo controllers

| Controller | How it connects | In AsterNUP's Home | In nxnative games |
|---|---|---|---|
| **Nintendo Switch Pro Controller** | Bluetooth (hold Sync, pick it in System Settings › Bluetooth) or USB | Yes: GameController extended gamepad; A/B/X/Y follow the printed labels (A on the right confirms) | Yes (macOS game controller). Gyro on the Mac needs nxnative's HID work ([PR 296](https://github.com/seedds/nxnative/pull/296)) |
| **Joy-Con pair** | Pair both, then combine them in System Settings › Game Controllers | Yes: one extended gamepad | Yes |
| **Single Joy-Con** (sideways) | Bluetooth | Yes: micro gamepad: stick moves, right face button confirms, bottom goes back, + / − for options | Yes |
| **Switch Online controllers** (SNES, N64, …) and other Nintendo pads macOS pairs but doesn't list | Bluetooth / USB | Yes, if macOS exposes them as HID gamepads: read as raw HID (Nintendo button order: A confirms, B goes back, HOME) | nxnative reads unlisted HID gamepads too |
| **Joy-Con 2, Pro Controller 2** (Switch 2) | Nintendo's own Bluetooth LE protocol: **not** in macOS Bluetooth settings | **No** (see below) | Yes: turn on **Switch 2 controllers** (`DM_SW2`) in the game's Options → Game settings, or **Controllers → Switch 2 controllers → Turn on in every installed game**. Start the game, hold the controller's Sync button until its lights sweep (first time only); later any button wakes it |

### Switch 2 controllers and HOME

Joy-Con 2 and Pro Controller 2 are connected by the running nxnative game, which owns the Bluetooth link, so AsterNUP
can't read them. While playing with one, use the **keyboard HOME shortcut** (default ⌃⌥H) to come back to AsterNUP; the
game stays open and **Playing** shows on its tile. Holding the controller's HOME for 2 seconds still opens the game's
own quit prompt. Making Switch 2 controllers drive the Home screen too means porting nxnative's Bluetooth LE stack
(`dm/host/pad_switch2_apple.m`, MIT) into AsterNUP, and handing the controller over cleanly when a game starts. That's
not done yet; contributions are welcome.

## Button layout

**Controllers → Face buttons**:

- **By label** (default): the button printed **A** confirms and **B** goes back, the Nintendo way. AsterNUP reads each
  button's label from macOS (its SF Symbol), so it doesn't matter whether macOS maps Nintendo buttons by position or label.
- **By position**: the bottom button confirms (Xbox style).

PlayStation controllers always go by position (✕ confirms).

## HOME

- **Short press of HOME** while a game is in front brings AsterNUP forward; the game keeps running. Pressing HOME on the
  Home screen goes back to the game. A long hold (2 s) is left to the game: nxnative's quit prompt.
- AsterNUP asks macOS not to take the HOME button (`preferredSystemGestureState = .disabled`). If macOS still opens the
  Games app, change it in System Settings › Game Controllers, or turn on **Press − and + together for HOME**.
- **Keyboard shortcut**: ⌃⌥H by default (⌃⌥⌘H, F13 or off in Home settings). A global hotkey, so it works while a game
  is in front, with no Accessibility permission.

## Input routing

Navigation goes only to the frontmost surface: while a game is in front, AsterNUP ignores everything except HOME (it
watches controllers in the background for that one button). On the Home screen, the top dialog gets the input, and
closing it restores the focus you had. Coming back from a game puts the focus on that game's tile. Controllers can
connect or reconnect at any time.

## Tested so far, and help wanted

The keyboard paths, the scripted UI tests and the controller discovery code are tested. Physical controllers haven't
been tested widely yet: the Pro Controller, Joy-Con, Switch Online controllers, the label-based A/B mapping and the
HOME button in particular. If you have one, open **Controllers → Connected**, which shows each controller's family,
profile and which physical button confirms, and tell us what works and what doesn't in a GitHub issue.

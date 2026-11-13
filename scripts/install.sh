#!/bin/zsh
# AsterNUP installer for Apple silicon Macs. Builds AsterNUP from source, installs it, sets up everything the game
# backend (nxnative) needs, checks the game-build toolchain and opens the app. Run it again at any time to update.
#
# One line, from anywhere (clones the source into ~/Library/Application Support/AsterNUP/Source):
#   curl -fsSL https://raw.githubusercontent.com/asterpolaris/AsterNUP/main/scripts/install.sh | zsh
#   curl -fsSL https://raw.githubusercontent.com/asterpolaris/AsterNUP/main/scripts/install.sh | zsh -s -- --no-deps
# From a clone:
#   scripts/install.sh   (or: make install)
#
# Options:
#   --no-deps          skip Homebrew tools and the backend's Python environment (AsterNUP still installs and runs)
#   --import <path>    open AsterNUP straight into inspecting this dump (.nup or ExeFS/RomFS folder)
#   --no-open          don't open AsterNUP at the end
#   -h, --help         show this help
# Environment:
#   ASTERNUP_INSTALL_DIR    where AsterNUP.app goes (default: ~/Applications)
#   ASTERNUP_SIGN_IDENTITY  codesign identity for AsterNUP (default: ad-hoc, which runs on this Mac)
#   ASTERNUP_SOURCE         where the one-line install keeps the source (default: ~/Library/Application Support/AsterNUP/Source)
#   ASTERNUP_REF            branch or tag the one-line install checks out (default: main)
#
# Building AsterNUP needs only the Command Line Tools. Building *games* also needs Xcode and its Metal toolchain, which
# this script checks and explains but can't install for you (they need your Apple Account and admin password).
set -euo pipefail

ASTERNUP_REPO_URL="${ASTERNUP_REPO_URL:-https://github.com/asterpolaris/AsterNUP.git}"   # override to install from a fork

# --- One-line install: fetch the source, then run the copy of this script inside it --------------------------------
# (Everything below this block is only read once the source is on disk, so piping this file into zsh is safe.)
bootstrap() {
  local src="${ASTERNUP_SOURCE:-$HOME/Library/Application Support/AsterNUP/Source}" ref="${ASTERNUP_REF:-main}"
  print -P "%B==> Getting AsterNUP%b"
  [[ "$(uname -m)" == arm64 ]] || { print -P "%F{red}✗%f AsterNUP needs an Apple silicon Mac (this one is $(uname -m))." >&2; exit 1; }
  if ! xcode-select -p >/dev/null 2>&1 || ! /usr/bin/xcrun --find git >/dev/null 2>&1; then
    print -P "%F{yellow}!%f The Command Line Tools are needed (git, Swift). Starting Apple's installer:"
    print -P "  finish it, then run the same command again."
    xcode-select --install 2>/dev/null || true
    exit 1
  fi
  if [[ -d "$src/.git" ]]; then
    git -C "$src" fetch --quiet --tags origin
    git -C "$src" checkout --quiet "$ref"
    git -C "$src" merge --quiet --ff-only "origin/$ref" 2>/dev/null || true
  else
    mkdir -p "${src:h}"
    git clone --quiet --branch "$ref" "$ASTERNUP_REPO_URL" "$src"
  fi
  print -P "%F{green}✓%f Source: $src ($(git -C "$src" describe --tags --always 2>/dev/null))"
  if [[ -r /dev/tty ]] && { : < /dev/tty } 2>/dev/null; then
    exec /bin/zsh "$src/scripts/install.sh" "$@" < /dev/tty
  else
    exec /bin/zsh "$src/scripts/install.sh" "$@" < /dev/null
  fi
}
if [[ ! -f "$0" || ! -f "${0:A:h}/../Package.swift" ]]; then bootstrap "$@"; fi

# --- Install from a source checkout ----------------------------------------------------------------------------------
cd "${0:A:h}/.."
REPO="$PWD"

DEPS=1; OPEN=1; IMPORT=""
while (( $# )); do
  case "$1" in
    --deps) DEPS=1 ;;            # the default; kept for older instructions
    --no-deps) DEPS=0 ;;
    --no-open) OPEN=0 ;;
    --import) shift; IMPORT="${1:?--import needs a path}" ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

N=0; TOTAL=6
step() { N=$((N + 1)); print -P "\n%B[$N/$TOTAL] $1%b"; }
die() { print -P "%F{red}✗%f $1" >&2; exit 1; }
ok() { print -P "%F{green}✓%f $1"; }
warn() { print -P "%F{yellow}!%f $1"; }
NEEDS=()

step "Checking this Mac"
[[ "$(uname -m)" == arm64 ]] || die "AsterNUP needs an Apple silicon Mac (this one is $(uname -m))."
ok "$(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB memory, macOS $(sw_vers -productVersion)"
if ! xcrun --find swift >/dev/null 2>&1; then
  warn "No Swift compiler. Starting Apple's Command Line Tools installer: finish it, then run this again."
  xcode-select --install || true
  exit 1
fi
ok "$(xcrun swift --version 2>&1 | head -1 | sed 's/^.*Apple Swift/Swift/; s/ (.*//')"

step "Building and installing AsterNUP"
print "  (the first build takes a minute or two)"
scripts/make_app.sh build >/dev/null
DEST="${ASTERNUP_INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$DEST"
if pgrep -f "$DEST/AsterNUP.app/Contents/MacOS/AsterNUP" >/dev/null; then
  warn "AsterNUP is open; quitting it so it can be replaced."
  osascript -e 'tell application id "com.asterpolaris.AsterNUP" to quit' >/dev/null 2>&1 || true
  sleep 2
fi
rm -rf "$DEST/AsterNUP.app.new"
ditto build/AsterNUP.app "$DEST/AsterNUP.app.new"
rm -rf "$DEST/AsterNUP.app"
mv "$DEST/AsterNUP.app.new" "$DEST/AsterNUP.app"
xattr -dr com.apple.quarantine "$DEST/AsterNUP.app" 2>/dev/null || true
codesign --verify --strict "$DEST/AsterNUP.app" && ok "Installed $DEST/AsterNUP.app ($(defaults read "$DEST/AsterNUP.app/Contents/Info" CFBundleShortVersionString))"

step "Tools the game backend uses"
if (( DEPS )); then
  BREW=$(command -v brew || { [[ -x /opt/homebrew/bin/brew ]] && echo /opt/homebrew/bin/brew; } || true)
  if [[ -n "$BREW" ]]; then
    if "$BREW" install --quiet xcodegen zstd glslang python@3.14 >/dev/null; then ok "Homebrew: xcodegen, zstd, glslang, python@3.14"
    else warn "Homebrew couldn't install everything; see the messages above."; NEEDS+=("brew install xcodegen zstd glslang python@3.14"); fi
  else
    warn "Homebrew isn't installed. Get it from https://brew.sh, then run this again."
    NEEDS+=("Install Homebrew (https://brew.sh), then run the installer again")
  fi
else
  print "  skipped (--no-deps)"
fi

step "Python for the backend"
source scripts/lib/python.sh
if (( DEPS )); then
  if asternup_setup_venv; then ok "Python environment: $ASTERNUP_VENV"; else warn "Setting up the Python environment failed; see the messages above."; fi
fi
if PY=$(asternup_python); then
  ok "$(arch -arm64 $PY --version) ($PY)"
  if asternup_python_modules_ok "$PY"; then ok "Python modules present"
  else warn "Python modules missing"; NEEDS+=("Run the installer again without --no-deps (or Backend & Toolchain › Set up Python environment)"); fi
else
  warn "No arm64 Python 3.12 or later"
  NEEDS+=("brew install python@3.14, then run the installer again")
fi

step "Fetching the nxnative backend (pinned)"
if scripts/fetch_backend.sh | tail -1; then :; else
  warn "Couldn't fetch the backend. You can retry in AsterNUP: Backend & Toolchain › Set up backend."
fi

step "Checking the game-build toolchain"
if scripts/check_toolchain.sh | sed 's/^/  /'; then
  ok "This Mac can build games."
  TOOLCHAIN=1
else
  TOOLCHAIN=0
  NEEDS+=("Fix the toolchain items marked above to build games (Xcode and its Metal toolchain come from Apple)")
fi

if (( OPEN )); then
  if [[ -n "$IMPORT" ]]; then
    [[ -e "$IMPORT" ]] || die "$IMPORT does not exist"
    open -a "$DEST/AsterNUP.app" "${IMPORT:A}"   # works whether or not AsterNUP is already open
  else
    open "$DEST/AsterNUP.app"
  fi
fi

print -P "\n%B%F{green}AsterNUP is installed.%f%b"
if (( ${#NEEDS} )); then
  print -P "\nStill to do:"
  for n in "${NEEDS[@]}"; do print -P "  • $n"; done
  (( TOOLCHAIN )) || print -P "  AsterNUP opens and can inspect dumps now; building games needs the toolchain."
fi
print -P "\nNext: in AsterNUP choose %BAdd a game › Import a dump%b. Guide: docs/GETTING_STARTED.md"
print -P "Update any time by running the installer again. Remove AsterNUP with scripts/uninstall.sh."

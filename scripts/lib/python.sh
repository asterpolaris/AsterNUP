# Shared Python selection for AsterNUP's scripts (sourced, zsh).
# The backend runs from AsterNUP's own virtual environment, so nothing is installed into Homebrew's or the
# system's Python (Homebrew Python refuses system-wide pip installs, PEP 668).
ASTERNUP_VENV="${ASTERNUP_VENV:-$HOME/Library/Application Support/AsterNUP/Backend/venv}"
ASTERNUP_PIP_PACKAGES=(lz4 "capstone>=5,<6" fonttools nsz zbic)

# An arm64 Python 3.12+ to create the venv from. 3.14 first: nxnative's primary version (zstd built in).
asternup_base_python() {
  local c
  for c in /opt/homebrew/opt/python@3.14/bin/python3.14 /Library/Frameworks/Python.framework/Versions/3.14/bin/python3.14 \
           /opt/homebrew/opt/python@3.13/bin/python3.13 /opt/homebrew/opt/python@3.12/bin/python3.12 \
           /opt/homebrew/bin/python3 /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /usr/local/bin/python3; do
    [[ -x $c ]] && arch -arm64 $c -c 'import sys, platform; assert sys.version_info >= (3, 12) and platform.machine() == "arm64"' 2>/dev/null && { print -r -- $c; return 0; }
  done
  return 1
}

# The Python the backend uses: the venv's when it is set up, else a base Python.
asternup_python() {
  if [[ -x "$ASTERNUP_VENV/bin/python3" ]] && arch -arm64 "$ASTERNUP_VENV/bin/python3" -c 'import sys; assert sys.version_info >= (3, 12)' 2>/dev/null; then
    print -r -- "$ASTERNUP_VENV/bin/python3"; return 0
  fi
  asternup_base_python
}

asternup_python_modules_ok() {   # $1: python
  arch -arm64 "$1" -c 'import lz4, capstone, fontTools, nsz, sys
if sys.version_info >= (3, 14): import compression.zstd
else: import backports.zstd' 2>/dev/null
}

# Create the venv (if needed) and install the backend's modules into it.
asternup_setup_venv() {
  local base
  base=$(asternup_base_python) || { print -u2 "No arm64 Python 3.12+: brew install python@3.14"; return 1; }
  if [[ ! -x "$ASTERNUP_VENV/bin/python3" ]]; then
    mkdir -p "${ASTERNUP_VENV:h}"
    arch -arm64 "$base" -m venv "$ASTERNUP_VENV" || return 1
  fi
  local extra=()
  arch -arm64 "$ASTERNUP_VENV/bin/python3" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 14) else 1)' || extra=(backports.zstd)
  arch -arm64 "$ASTERNUP_VENV/bin/python3" -m pip install --quiet --disable-pip-version-check --upgrade pip >/dev/null 2>&1 || true
  arch -arm64 "$ASTERNUP_VENV/bin/python3" -m pip install --quiet --disable-pip-version-check "${ASTERNUP_PIP_PACKAGES[@]}" "${extra[@]}"
}

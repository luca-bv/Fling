#!/bin/sh
# Builds Fling from source and installs it into /Applications.
#   sh install.sh            # from a clone, or anywhere (it clones into ~/.local/share/Fling)
set -eu

REPO=${REPO:-https://github.com/luca-bv/Fling.git}
SRC=${SRC:-$HOME/.local/share/Fling}
DEST=${DEST:-/Applications}

[ "$(uname -s)" = Darwin ] || { echo "Fling is macOS only."; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || { echo "Fling needs macOS 14 or later."; exit 1; }
command -v swift >/dev/null 2>&1 || { echo "Needs the Swift toolchain: xcode-select --install"; exit 1; }

# Run from a clone if there is one next to this script; otherwise keep our own in $SRC.
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)
if [ -f "$here/Package.swift" ]; then
	SRC=$here
elif [ -d "$SRC/.git" ]; then
	git -C "$SRC" pull --ff-only
else
	git clone --depth 1 "$REPO" "$SRC"
fi

cd "$SRC"
# Same signing certificate every time, or macOS drops the Accessibility grant on each update. No-op if it exists.
make cert
make app VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1.0)"

pkill -x Fling 2>/dev/null || true
rm -rf "$DEST/Fling.app"
ditto build/Fling.app "$DEST/Fling.app"
open "$DEST/Fling.app"

cat <<TEXT

Installed $DEST/Fling.app from $SRC — it runs in the menu bar, with no Dock icon.
Allow it in System Settings > Privacy & Security > Accessibility when asked.
Quit Rectangle first if you run it; it uses the same shortcuts.

Update: run this script again.
Command line (optional):
  ln -sf $DEST/Fling.app/Contents/MacOS/flingctl /usr/local/bin/flingctl
TEXT

#!/usr/bin/env bash
#
# Install (or remove) the login-time autorun that rebuilds the patched KWin
# after an upgrade resets the OSD position. Runs as you — no root needed.
#
# On install this COPIES the runtime files (build.sh + tools/) into an on-system
# location and points the autostart entry at that copy, so the autorun never
# depends on where you happened to clone the repo (e.g. a removable or late-
# mounted partition). Re-running is idempotent: it refreshes the installed copy.
#
#   tools/install-autorun.sh           # install (copies files + adds autostart)
#   tools/install-autorun.sh --remove  # uninstall (removes autostart + copy)
#
set -euo pipefail

# Where the runtime files get installed (an on-system, always-available path).
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/osd-position-kde"

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # tools/
SRC_ROOT="$(cd "$HERE/.." && pwd)"                                      # repo root
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/osd-position-autorun.desktop"

if [ "${1:-}" = "--remove" ] || [ "${1:-}" = "-r" ]; then
  rm -f "$DEST"
  echo ">> Removed autorun: $DEST"
  # Remove the installed copy too, but never touch the repo we're running from
  # (in case someone runs --remove straight out of the source tree).
  if [ -d "$PREFIX" ] && [ "$PREFIX" != "$SRC_ROOT" ]; then
    rm -rf "$PREFIX"
    echo ">> Removed installed copy: $PREFIX"
  fi
  echo "   Your position file ~/.config/kwin-osd-position is left untouched."
  exit 0
fi

[ -f "$SRC_ROOT/build.sh" ]                       || { echo "Missing build.sh in $SRC_ROOT" >&2; exit 1; }
[ -f "$HERE/osd-position-autorun.sh" ]            || { echo "Missing runner: $HERE/osd-position-autorun.sh" >&2; exit 1; }
[ -f "$HERE/osd-position-autorun.desktop" ]       || { echo "Missing template: $HERE/osd-position-autorun.desktop" >&2; exit 1; }

# 1) Copy the runtime files to the on-system PREFIX, unless we're already there.
if [ "$SRC_ROOT" = "$PREFIX" ]; then
  echo ">> Already running from the install location ($PREFIX); skipping copy."
else
  echo ">> Installing runtime files to: $PREFIX"
  mkdir -p "$PREFIX/tools"
  cp -f "$SRC_ROOT/build.sh"                    "$PREFIX/build.sh"
  cp -f "$HERE/osd-position-autorun.sh"         "$PREFIX/tools/osd-position-autorun.sh"
  cp -f "$HERE/osd-position-autorun.desktop"    "$PREFIX/tools/osd-position-autorun.desktop"
  cp -f "$HERE/install-autorun.sh"              "$PREFIX/tools/install-autorun.sh"
  # Carry along docs/licence if present — handy when working from the copy.
  [ -f "$SRC_ROOT/README.md" ] && cp -f "$SRC_ROOT/README.md" "$PREFIX/README.md" || true
  [ -f "$SRC_ROOT/LICENSE" ]   && cp -f "$SRC_ROOT/LICENSE"   "$PREFIX/LICENSE"   || true
fi

chmod +x "$PREFIX/build.sh" "$PREFIX/tools/"*.sh

# 2) Write the autostart entry, pointing at the INSTALLED runner (not $HERE).
RUNNER="$PREFIX/tools/osd-position-autorun.sh"
mkdir -p "$(dirname "$DEST")"
sed "s|__EXEC__|/usr/bin/env bash $RUNNER|g" "$PREFIX/tools/osd-position-autorun.desktop" > "$DEST"

echo ">> Installed autorun: $DEST"
echo "   Runs from: $RUNNER"
echo "   At each login it checks whether a KWin upgrade removed the patch;"
echo "   if so it offers to rebuild (applies on the following login)."
echo "   Manage it in System Settings > Autostart, or remove with:"
echo "     $PREFIX/tools/install-autorun.sh --remove"

#!/usr/bin/env bash
#
# Login-time check: has a KWin upgrade wiped our OSD-position patch?
#
# Runs as your user, in your Plasma session, from ~/.config/autostart (installed
# by tools/install-autorun.sh). It needs no root and no passwordless sudo —
# modelled on KDE-Rounded-Corners' autorun approach.
#
# How it detects staleness: our patch bakes the literal path
# "/.config/kwin-osd-position" into libkwin as a QStringLiteral (UTF-16). If
# that marker is gone from the *installed* libkwin, the official package has
# replaced our patched build, so we offer to rebuild.
#
# NOTE: unlike a KWin *effect* (which can hot-reload via D-Bus), this patches
# core KWin, so a rebuild only takes effect on the NEXT login — you cannot
# hot-swap a running Wayland compositor. Your chosen position itself survives
# upgrades untouched: it lives in ~/.config/kwin-osd-position (read at runtime).
#
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
BUILD_SH="$HERE/build.sh"
MARKER="config/kwin-osd"        # stable fragment of the baked-in path literal

# Only act inside a KDE/Plasma session with the tools we need.
[ "${KDE_SESSION_VERSION:-}" = "6" ] || exit 0
command -v kdialog  >/dev/null 2>&1 || exit 0
command -v strings  >/dev/null 2>&1 || exit 0
[ -x "$BUILD_SH" ] || exit 0

# Locate the installed libkwin (the core lib that holds placeOnScreenDisplay).
KWIN_LIB="$(ldconfig -p 2>/dev/null | awk '/libkwin\.so\.6 /{print $NF; exit}')"
if [ -z "${KWIN_LIB:-}" ] || [ ! -e "$KWIN_LIB" ]; then
  for c in /usr/lib/libkwin.so.6 /usr/lib64/libkwin.so.6 /usr/lib/libkwin.so; do
    [ -e "$c" ] && KWIN_LIB="$c" && break
  done
fi
[ -n "${KWIN_LIB:-}" ] && [ -e "$KWIN_LIB" ] || exit 0   # can't find it -> stay quiet

# Patch still present? Nothing to do. (-el = scan for UTF-16LE strings.)
if strings -a -el "$KWIN_LIB" | grep -qa "$MARKER"; then
  exit 0
fi

# --- Patch is gone: a KWin upgrade reset the OSD position. Offer to rebuild. ---
kdialog --title "OSD position patch" --yesno \
"A KWin update replaced your patched build, so the volume/brightness OSD is back \
to KWin's default (high) position.

Rebuild the patched KWin now?

• Takes a few minutes (it compiles KWin).
• You'll be asked for your sudo password in a terminal.
• It applies on your NEXT login (a running compositor can't be hot-swapped).
• Your chosen position in ~/.config/kwin-osd-position is preserved automatically." \
  || exit 0

# Run the build in a real terminal so makepkg's sudo gets a tty for its prompt.
WRAP="cd $(printf %q "$HERE"); ./build.sh; echo; echo '== Build finished. Log out and back in to apply the OSD position. =='; read -rp 'Press Enter to close...'"

if command -v konsole >/dev/null 2>&1; then
  konsole --hold -e bash -lc "$WRAP" || true
elif command -v x-terminal-emulator >/dev/null 2>&1; then
  x-terminal-emulator -e bash -lc "$WRAP" || true
else
  kdialog --title "OSD position patch" --sorry \
"No terminal emulator found to run the build interactively.

Please rebuild manually:
    $BUILD_SH
then log out and back in."
fi

#!/usr/bin/env bash
#
# Build and install a patched KWin that places the on-screen display (OSD) —
# the volume/brightness/mic popup — at a chosen fraction of the active screen's
# height, while keeping KWin's native horizontal centering and active-screen
# following.
#
# The position is read from ~/.config/kwin-osd-position at runtime, on every
# popup, so it can be changed live without rebuilding. OSD_FRAC below is only
# the build-time default, used when that file is absent or unreadable.
#
# The script fetches the current Arch `kwin` PKGBUILD, lets makepkg download,
# extract, and prepare upstream, then patches placeOnScreenDisplay() in
# src/placement.cpp and builds/installs. Re-run after a `kwin` upgrade (the
# autorun in tools/ can detect a wiped patch and offer to rebuild). See
# README.md for the full rationale and the Window Rules alternative.
#
# Usage:
#   ./build.sh                 # default fraction 0.85 (85% down the screen)
#   OSD_FRAC=0.9 ./build.sh    # custom default (0.0 = top, 1.0 = bottom)
#
set -euo pipefail

OSD_FRAC="${OSD_FRAC:-0.85}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/build"
POS_FILE="\$HOME/.config/kwin-osd-position"   # only for display in messages

if [[ $EUID -eq 0 ]]; then
  echo "Do NOT run as root. makepkg installs with sudo when needed." >&2
  exit 1
fi
# Accept a plain decimal (e.g. 0.85, .9, 1, 0) ...
if ! [[ "$OSD_FRAC" =~ ^[0-9]*\.?[0-9]+$ ]]; then
  echo "OSD_FRAC must be a number between 0 and 1 (got '$OSD_FRAC')." >&2
  exit 1
fi
# ... and require it to be in [0, 1].
if ! awk -v f="$OSD_FRAC" 'BEGIN { exit !(f >= 0 && f <= 1) }'; then
  echo "OSD_FRAC must be between 0 and 1 (got '$OSD_FRAC')." >&2
  exit 1
fi

echo ">> Patched kwin build — default OSD height = ${OSD_FRAC} of screen (live-editable via ${POS_FILE})"

# Fresh build dir each run so we always patch a clean tree.
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"

echo ">> Fetching current Arch kwin PKGBUILD..."
curl -fsSL \
  "https://gitlab.archlinux.org/archlinux/packaging/packages/kwin/-/raw/main/PKGBUILD" \
  -o PKGBUILD

# 1) download + extract + run upstream prepare() (applies upstream's own patches)
#    sha256sums in the PKGBUILD still verify tarball integrity even with
#    --skippgpcheck, which only skips the maintainer GPG signature check.
echo ">> Downloading sources & running upstream prepare() ..."
makepkg --nobuild --skippgpcheck --nodeps

# 2) inject our placement code into the already-extracted, already-prepared source
SRC=$(echo "$BUILD"/src/kwin-*/src/placement.cpp)
if [[ ! -f "$SRC" ]]; then
  echo "Could not find placement.cpp (looked for $SRC)." >&2
  exit 1
fi

# 2a) Build the replacement C++ block. The build-time default fraction
#     (${OSD_FRAC}) is the only thing interpolated; everything else is literal.
#     Quoting note: the snippet uses ~/.config in comments (no '$') so the
#     unquoted heredoc only expands ${OSD_FRAC}.
SNIP="$BUILD/osd_snippet.cpp"
cat > "$SNIP" <<SNIPPET
    // --- OSD vertical placement (patched) ---------------------------------
    // Centre the OSD at a FRACTION of the active screen's height, so it lands
    // in the same relative spot on every monitor regardless of resolution.
    // The fraction is read at runtime, on every popup, so it can be changed
    // live without rebuilding kwin — the next OSD pickup uses the new value.
    //   File : ~/.config/kwin-osd-position   (one number, e.g. 0.85)
    //   Range: 0.0 (top) .. 1.0 (bottom); out-of-range values are clamped.
    //   Use a '.' decimal point. Missing/unreadable/non-numeric -> default below.
    double osdFrac = ${OSD_FRAC};
    {
        const QString osdPath = qEnvironmentVariable("HOME") + QStringLiteral("/.config/kwin-osd-position");
        QFile osdFile(osdPath);
        if (osdFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            bool osdOk = false;
            const double osdVal = QString::fromUtf8(osdFile.readLine()).trimmed().toDouble(&osdOk);
            if (osdOk) {
                osdFrac = osdVal;
            }
        }
    }
    osdFrac = std::clamp(osdFrac, 0.0, 1.0);

    int y = area.top() + qRound(osdFrac * area.height()) - qRound(size.height() / 2.0);
    // keep the OSD fully on the active screen even at extreme fractions
    y = std::max(area.top(), std::min(y, qRound(area.bottom() - size.height())));
    // --- end patch --------------------------------------------------------
SNIPPET

# 2b) Add the includes our snippet needs (QFile + std::clamp/min/max), once.
perl -0777 -i -pe \
  's{#include <QTextStream>\n}{#include <QTextStream>\n#include <QFile>\n#include <algorithm>\n}' \
  "$SRC"

# 2c) Replace the unique stock y-formula line with our block (leading
#     indentation consumed; the snippet supplies its own).
OSD_SNIP="$SNIP" perl -0777 -i -pe '
  BEGIN { local $/; open my $fh, "<", $ENV{OSD_SNIP} or die "no snippet: $!"; our $r = <$fh>; close $fh; chomp $r; }
  s{^[ \t]*const int y = area\.top\(\) \+ 2 \* area\.height\(\) / 3 - size\.height\(\) / 2;}{$r}m;
' "$SRC"

# Fail loudly if the upstream code changed shape and our patch didn't land:
# the snippet marker must be present AND the old formula must be gone.
if ! grep -q "kwin-osd-position" "$SRC" \
   || ! grep -q "#include <QFile>" "$SRC" \
   || grep -q "2 \* area.height() / 3" "$SRC"; then
  echo "!! Patch did not apply cleanly — placeOnScreenDisplay() source has changed." >&2
  echo "   Inspect: $SRC" >&2
  exit 1
fi
echo ">> Patched placeOnScreenDisplay() — reads ~/.config/kwin-osd-position (default ${OSD_FRAC})"

# 3) build the already-extracted tree (no re-extract, no re-prepare) and install
echo ">> Building (this takes a while) and installing..."
makepkg --noextract --syncdeps --install --noconfirm --skippgpcheck

# 4) Seed the position file with the default fraction if it doesn't exist, so
#    there's something to edit. Never overwrite an existing one: that would
#    clobber the position chosen earlier, which must survive rebuilds.
REAL_POS_FILE="$HOME/.config/kwin-osd-position"
if [[ -e "$REAL_POS_FILE" ]]; then
  echo ">> Position file already exists, keeping it: $REAL_POS_FILE ($(tr -d '\n' < "$REAL_POS_FILE" 2>/dev/null))"
else
  mkdir -p "$(dirname "$REAL_POS_FILE")"
  printf '%s\n' "$OSD_FRAC" > "$REAL_POS_FILE"
  echo ">> Created $REAL_POS_FILE with default ${OSD_FRAC}"
fi

cat <<EOF

>> Done. Patched kwin installed.
   Log out and back in (or reboot) once for the running compositor to load it.

   After that, change the OSD position WITHOUT rebuilding — just write a number
   (0.0 top .. 1.0 bottom) to the file; the next volume keypress picks it up:

     echo 0.85 > ~/.config/kwin-osd-position    # then nudge volume to see it

   Test the popup any time with:
     qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.showText "audio-volume-high" "osd position"
EOF

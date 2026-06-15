#!/usr/bin/env bash
#
# Install (or remove) the login-time autorun that rebuilds the patched KWin
# after an upgrade resets the OSD position. Runs as you — no root needed.
#
#   tools/install-autorun.sh           # install
#   tools/install-autorun.sh --remove  # uninstall
#
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # tools/
RUNNER="$HERE/osd-position-autorun.sh"
TEMPLATE="$HERE/osd-position-autorun.desktop"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/osd-position-autorun.desktop"

if [ "${1:-}" = "--remove" ] || [ "${1:-}" = "-r" ]; then
  rm -f "$DEST"
  echo ">> Removed autorun: $DEST"
  exit 0
fi

[ -f "$TEMPLATE" ] || { echo "Missing template: $TEMPLATE" >&2; exit 1; }
[ -f "$RUNNER" ]   || { echo "Missing runner: $RUNNER" >&2; exit 1; }
chmod +x "$RUNNER"

mkdir -p "$(dirname "$DEST")"
# Substitute the absolute Exec path into the template.
sed "s|__EXEC__|/usr/bin/env bash $RUNNER|g" "$TEMPLATE" > "$DEST"

echo ">> Installed autorun: $DEST"
echo "   At each login it checks whether a KWin upgrade removed the patch;"
echo "   if so it offers to rebuild (applies on the following login)."
echo "   Manage it in System Settings > Autostart, or remove with: $0 --remove"

# Move the KDE Plasma OSD — screen-aware, resolution-independent, live-editable

Lower (or raise) the Plasma **OSD** — the volume/brightness/mic popup — to a
height you choose, **without** losing the things KWin's default placement gives
you for free: it follows the **active screen** and stays **horizontally
centered**. The position is a *fraction* of the screen height (so it lands in
the same relative spot on every monitor regardless of resolution) and is read
from a file **at runtime, on every popup**, so you can move it live with no
rebuild and no logout.

```bash
./build.sh                          # patch + build + install kwin (default 0.85)
echo 0.85 > ~/.config/kwin-osd-position   # later: move it; next popup obeys
```

---

## Do you actually need this? (Read this first)

For a lot of people, **you don't** — KDE's built-in **Window Rules** are simpler
and require no patched compositor. This patch only earns its keep for a specific
kind of workflow. Decide with the table below.

| Your situation | Best tool |
| --- | --- |
| **Single monitor**, fixed resolution | **Window Rules** — pin the OSD to one absolute coordinate. Done. |
| **Static** multi-monitor (same monitors, same layout, always) | **Window Rules** — pick the screen/coords once; they never need to change. |
| You just want it *a bit* lower and never replug anything | **Window Rules** — easiest, no compiling, survives upgrades. |
| **Dynamic** workflow: laptop that docks/undocks, monitors hot-plugged, resolutions that change, OSD should appear on whatever screen is *active* | **This patch.** |
| You want one setting that lands in the *same relative spot* on a 1080p laptop panel **and** a 4K external | **This patch.** |
| You want to nudge the position often and instantly, without fighting a rules dialog | **This patch.** |

### Why Window Rules are easier — and where they break

KDE *can* pin the OSD with **System Settings → Window Management → Window Rules**
(match the `plasmashell` / OnScreenDisplay window, force a Position). For a
**single monitor or a never-changing setup this is the right answer**: no
patched package, nothing to rebuild after updates, a few clicks and you're done.

But a Window Rule can only set an **absolute** position, and that's exactly what
makes it wrong for dynamic setups:

- **It's a fixed pixel coordinate.** `x=1200, y=900` is centered on a 2560-wide
  screen but off to the left on a 3840-wide one, and near the bottom on 1080p
  but mid-screen on 4K. Replug a different monitor and it's in the wrong place.
- **It throws away screen-awareness.** The stock OSD appears on whichever screen
  is currently *active* (where your focus/cursor is). A Window Rule nails it to
  one screen/coordinate, so on a multi-head setup the popup stops following you.
- **It doesn't track resolution or layout changes** — dock/undock, hotplug, or a
  resolution switch and you're back in the rules dialog editing numbers.

So the rule of thumb: **static setup → Window Rules; dynamic setup → this patch.**
This patch keeps *centering* and *active-screen following*, and replaces only the
**vertical** formula with a resolution-independent, file-driven one.

---

## Why this needs a KWin patch at all

The OSD is positioned by **KWin**, not by plasmashell. It's a Wayland
`plasma-surface` with the *OnScreenDisplay* role, and KWin force-places it in
`KWin::Placement::placeOnScreenDisplay()` with this hardcoded formula:

```cpp
const int x = area.left() + (area.width()  - size.width())  / 2;   // centered
const int y = area.top()  + 2 * area.height() / 3 - size.height() / 2;  // 2/3 down
```

That position is **compiled into kwin**. Everything *short* of patching has been
tried and verified not to work (Plasma 6.6.5 / Wayland):

- **KWin scripts can't move it.** The OSD window reports `moveable=false`;
  geometry writes from a script are silently dropped.
- **Editing the QML does nothing.** `Osd.qml`
  (`/usr/lib/qt6/qml/org/kde/plasma/workspace/osd/Osd.qml`) only sets
  width/height, and is loaded from a resource baked into the binary
  (`prefer :/qt/qml/...`), so editing the on-disk copy has no effect.
- **Window Rules can pin it**, but only to an absolute coordinate — which is the
  static-vs-dynamic tradeoff covered above.

So the only way to **keep screen-awareness but move it** is to patch that one
line in KWin and rebuild. That's what this repo does — but instead of swapping in
another hardcoded constant, the patch makes the `y` formula:

- **resolution-independent** — the OSD centre is placed at a *fraction* of the
  active screen's height, not a fixed pixel count, so it lands in the same
  relative spot on every monitor. (A fixed `+300px` is ~28 % of a 1080p screen
  but only ~14 % of a 4K screen — that drift is exactly what this avoids.)
- **live-editable** — `placeOnScreenDisplay()` reads the fraction from a file at
  runtime, on every popup, so you change the position without rebuilding:

  ```cpp
  // ~/.config/kwin-osd-position : one number, 0.0 (top) .. 1.0 (bottom)
  const int y = area.top() + qRound(frac * area.height()) - size.height()/2;
  ```

Native horizontal centering and active-screen following are kept as-is.

---

## Requirements

- **Arch Linux** (or a derivative using the Arch `kwin` package). `build.sh`
  fetches the current Arch `kwin` PKGBUILD, so it tracks upstream version bumps
  with no edits. Other distros: see [Other distributions](#other-distributions).
- **Plasma 6 / KWin on Wayland.** Developed and tested on Plasma 6.6.5.
- Standard build tooling: `base-devel` (`makepkg`), `curl`, `perl`. The autorun
  helper additionally uses `kdialog`, `strings`, and a terminal (`konsole`).
- Run as your normal user — **not root**. `makepkg` installs with `sudo` only
  when it needs to.

### Other distributions

**This patch, as shipped, is Arch-specific** — `build.sh` is built around the
Arch `kwin` PKGBUILD and `makepkg`/`pacman`. The *technique* is not: it's a
one-line change to `placeOnScreenDisplay()` in KWin's `src/placement.cpp`, plus
a runtime read of a config file. On Fedora, openSUSE, Debian/Ubuntu, etc. the
same change applies cleanly — only the packaging/build wrapper differs (rpmbuild,
`debuild`, a manual CMake build of KWin, or your distro's source-package flow).

You're **free to fork and adapt this for your own distro or workflow** (it's MIT
licensed). The patch snippet and the verification logic in `build.sh` are the
reusable parts; swap out the fetch-and-build half. PRs adding other distros'
build paths are welcome.

---

## Build & install

```bash
./build.sh                  # default fraction: 0.85 (85% down the screen)
OSD_FRAC=0.9 ./build.sh     # custom default fraction (0.0 top .. 1.0 bottom)
```

`build.sh` fetches the **current** Arch `kwin` PKGBUILD each run, lets makepkg
download/extract/prepare upstream, patches `placement.cpp` in the extracted
tree, then builds and installs. Because it never hardcodes a version, it keeps
working across `kwin` releases with no edits. If upstream ever reshapes that
function so the patch can't land cleanly, the script **aborts loudly** rather
than installing a half-patched build.

On a successful install it also **creates `~/.config/kwin-osd-position`** seeded
with the default fraction, so there's a file to edit immediately. If the file
already exists it's left untouched — re-running after a `kwin` upgrade never
clobbers the position you chose.

After installing, **log out and back in** (or reboot) *once* so the running
compositor loads the new code. Then test the popup:

```bash
qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.showText \
  "audio-volume-high" "osd position"
```

---

## Moving the OSD afterwards (no rebuild)

`OSD_FRAC` at build time is only the **default**, used when the file is absent.
To change the position, write a number to the file — the **next** volume/
brightness popup picks it up. No rebuild, no logout:

```bash
echo 0.85 > ~/.config/kwin-osd-position   # then nudge volume to see it
```

- `0.0` = top of the active screen, `1.0` = bottom, `0.5` = middle.
- Values are **clamped to `[0.0, 1.0]`** and the OSD is always kept fully
  on-screen, so extreme values can't push it off the edge.
- Use a `.` decimal point. A missing, unreadable, or non-numeric file falls back
  to the build-time default — so you can never break the OSD by editing it.

---

## Staying patched across updates

A normal `pacman -Syu` will replace your patched `kwin` with the official one,
restoring the high OSD. **Your *position* is safe either way** — it lives in
`~/.config/kwin-osd-position`, which pacman never touches; an upgrade only
removes the file-*reading* code, not your chosen value. You just need to rebuild
so the reading code comes back.

### Login-time autorun (no root, no pacman hook)

Modelled on
[KDE-Rounded-Corners](https://github.com/matinlotfali/KDE-Rounded-Corners)'
approach. Install once:

```bash
./tools/install-autorun.sh        # adds a ~/.config/autostart entry
```

At each login it checks whether the installed `libkwin` still carries our patch
(it greps the baked-in `kwin-osd-position` path marker out of the library). If a
`kwin` upgrade wiped it, it pops a dialog offering to rebuild — running **as
you**, prompting for your sudo password in a terminal. No root pacman hook, no
passwordless sudo.

Remove with `./tools/install-autorun.sh --remove`, or manage it in
*System Settings → Autostart*.

### Why a rebuild still needs a re-login (Wayland)

This patches *core* KWin (`placement.cpp` in `libkwin`), not a loadable effect.
On Wayland, KWin **is** the display server, so it can't be hot-swapped in place:
`kwin_wayland --replace` merely *exits* the running compositor so its wrapper
restarts it — a disruptive restart, not a seamless hand-off, and not a supported
reload path. So the autorun rebuilds/installs now, and the new OSD position takes
effect on your **next login**. (On X11 you *could* `kwin_x11 --replace &` to
reload live — but this is built for Wayland.) Contrast KDE-Rounded-Corners, which
patches an *effect plugin* it can hot-reload via D-Bus in the same session.

---

## Removing / reverting

```bash
./tools/install-autorun.sh --remove   # remove the autostart entry
sudo pacman -S extra/kwin             # reinstall stock kwin
rm -f ~/.config/kwin-osd-position     # optional: drop the position file
```

Log out and back in once to load stock kwin.

---

## How the patch works (internals)

`build.sh` replaces the single stock `y`-formula line in
`src/placement.cpp::placeOnScreenDisplay()` with a block that:

1. starts from the build-time default fraction (`OSD_FRAC`);
2. reads `~/.config/kwin-osd-position` (via `$HOME`), and if it parses as a
   number, uses that instead — this happens **on every OSD popup**, which is what
   makes it live-editable;
3. clamps the fraction to `[0.0, 1.0]`;
4. centers the OSD at that fraction of the active screen's height, then clamps
   the final `y` so the window stays fully on-screen.

The required includes (`<QFile>`, `<algorithm>`) are injected alongside the
existing ones. The script verifies post-patch that its marker is present and the
old formula is gone, aborting otherwise. Horizontal centering and active-screen
selection are left as upstream wrote them.

---

## Repository layout

```
build.sh                              # fetch + patch + build + install kwin; seeds the position file
tools/
  install-autorun.sh                  # install/remove the login-time patch-check autorun
  osd-position-autorun.sh             # the autorun: detects an upgrade wiped the patch, offers rebuild
  osd-position-autorun.desktop        # autostart entry template (Exec path filled in on install)
```

The `build/` directory is created and wiped by `build.sh` on every run (it holds
the fetched kwin sources and built packages) and is git-ignored.

---

## Tested on

- Arch Linux, Plasma **6.6.5**, KWin on **Wayland**, x86-64.

Other versions should work — `build.sh` tracks the current Arch PKGBUILD and
fails loudly if upstream changes the patched function's shape.

---

## License

MIT — see [LICENSE](LICENSE). This repo contains only the build/patch tooling;
KWin itself is licensed by its own authors (GPL-2.0-or-later).

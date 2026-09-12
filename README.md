# firealpaca-wayland-fix

Fix **FireAlpaca pen pressure on KDE Plasma / GNOME / Wayland**.

## This is a vibe-coded

Since x11 wont be around too soon i decided to make it with the help of OpenCode and FireAlpaca is being my favorite app to use in windows (atleast) i decided to create this script,

## Why

FireAlpaca's Linux AppImage only bundles the **X11** Qt platform plugin. On a
Wayland session it is therefore forced through XWayland, where the Wayland
tablet protocol is **not** passed through — your drawing tablet (Wacom, Huion,
XP-Pen, Gaomon, ...) degrades to a plain mouse and **pen pressure stops
working** or it does weird shaped lines. On X11 pressure works fine, which is the classic
"it works on X11 but not Wayland" symptom.

This script gives the AppImage the **Qt Wayland platform plugin that matches
the Qt version already bundled inside FireAlpaca**, so it runs natively on
Wayland and pressure sensitivity works.

Verified with FireAlpaca 2.16.0 (bundles Qt 6.5.2) on SteamOS / KDE Plasma 6.

## How it works

1. Detects the FireAlpaca AppImage (or take it with `-a`).
2. Reads the Qt version bundled inside (from `libQt6Core.so.6`).
3. Downloads the matching `qt6-wayland` package from the
   [Arch package archive](https://archive.archlinux.org/packages/q/qt6-wayland)
   and extracts only the Wayland platform plugin + its client libraries.
4. Installs them to `~/.local/share/FireAlpaca-wayland/`.
5. Patches the `firealpaca.desktop` launch entry (backup saved) to start
   FireAlpaca with `QT_QPA_PLATFORM=wayland` and the plugin path.

No package installs, no root, no touching the AppImage itself.

## Usage

```bash
# auto-detect the AppImage in ~/AppImages, ~/Downloads
./patch-firealpaca.sh

# or specify it explicitly
./patch-firealpaca.sh -a /path/to/firealpaca.appimage
```

Then relaunch FireAlpaca from your application menu.

### Rollback

```bash
./patch-firealpaca.sh --uninstall
```

## Requirements

- FireAlpaca Linux AppImage
- `bash`, `curl`, `tar`, `zstd`
- Super handy if you have a second monitor... you know, for sanity-checking that
  pressure actually differs from a mouse.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Pen moves the cursor but always paints at max pressure | A session restart was missed — log out and back in with the tablet plugged in so KWin registers it as a tablet |
| Visible artifacts / glitches while drawing | The software rendering backend got selected because OpenGL/EGL isn't available — the script prefers the GPU-backed `wayland-egl` backend and falls back automatically. Check your graphics drivers (`glxinfo`, or try the X11 session) |
| AppImage not found | Pass it explicitly: `-a /path/to/firealpaca.appimage` |
| No qt6-wayland package for your Qt version | Newer or older FireAlpaca AppImage; the script tries older ABI-compatible Qt versions first |
| Still runs under XWayland | Check `xeyes`/`xwininfo`; make sure `QT_QPA_PLATFORM="wayland-egl;wayland;xcb"` is in the `Exec=` line |
| Pressure works in Krita but not FireAlpaca | That is exactly this bug — re-run the patch and relaunch FireAlpaca |

## License

Script: MIT (see `LICENSE`).

The script downloads Qt libraries from the Arch Linux package archive at
runtime; Qt is licensed under the [LGPLv3](https://www.gnu.org/licenses/lgpl-3.0.html)
(a copy is inside the `qt6-wayland` package it extracts). No Qt code is
redistributed by this repository.

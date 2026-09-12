#!/usr/bin/env bash
#
# firealpaca-wayland-fix
# Makes the FireAlpaca AppImage use the native Wayland Qt platform plugin so
# drawing tablets (Wacom, Huion, XP-Pen, ...) keep pen-pressure on Plasma/KDE
# Wayland instead of being reduced to a plain mouse on XWayland.
#
# Works on any Linux distro. Needs: bash, curl, tar, zstd. No root required.

set -euo pipefail

VERSION="1.0.0"
ARCHIVE_BASE="https://archive.archlinux.org/packages/q/qt6-wayland"
DEFAULT_INSTALL_DIR="$HOME/.local/share/FireAlpaca-wayland"

print_help() {
  cat <<'EOF'
firealpaca-wayland-fix - give FireAlpaca pen pressure on Wayland

Usage:
  ./patch-firealpaca.sh [options]

Options:
  -a, --appimage PATH   Path to the FireAlpaca AppImage (auto-detected if omitted)
  -d, --install-dir DIR Where to install the Qt Wayland plugin files
                        (default: ~/.local/share/FireAlpaca-wayland)
  -u, --uninstall       Restore the original desktop entry (installed files stay)
  -y, --yes             Re-run an already-patched desktop entry
  -h, --help            Show this help

What it does:
  1. Finds your FireAlpaca AppImage
  2. Detects the Qt version bundled inside it
  3. Downloads the matching qt6-wayland package (from the Arch package archive)
     and extracts just the Wayland platform plugin + libraries
  4. Installs those files to --install-dir
  5. Patches the FireAlpaca desktop entry to launch natively on Wayland
EOF
  exit 0
}

fatal() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[firealpaca-wayland-fix] $*"; }

APPIMAGE=""
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
UNINSTALL=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    -a|--appimage) APPIMAGE="$2"; shift 2;;
    -d|--install-dir) INSTALL_DIR="$2"; shift 2;;
    -u|--uninstall) UNINSTALL=1; shift;;
    -y|--yes) FORCE=1; shift;;
    -h|--help) print_help;;
    *) fatal "unknown option: $1 (try --help)";;
  esac
done

for tool in curl tar zstd; do
  command -v "$tool" >/dev/null 2>&1 || fatal "missing required tool: $tool"
done

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" = 1 ]; then
  DESKTOP="$HOME/.local/share/applications/firealpaca.desktop"
  if [ -f "$DESKTOP.bak.firealpaca-wayland" ]; then
    mv -f "$DESKTOP.bak.firealpaca-wayland" "$DESKTOP"
    log "Restored $DESKTOP"
  else
    log "No backup found at $DESKTOP.bak.firealpaca-wayland, nothing to restore."
  fi
  exit 0
fi

# ------------------------------------------------------------------ appimage
detect_appimage() {
  local candidates=(
    "$HOME/AppImages/firealpaca.appimage"
    "$HOME/Downloads/firealpaca.appimage"
    "$HOME/Downloads/FireAlpaca.appimage"
  )
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then echo "$c"; return 0; fi
  done
  find "$HOME" -maxdepth 4 -iname 'firealpaca*.appimage' -print -quit 2>/dev/null || true
}

if [ -z "$APPIMAGE" ]; then
  APPIMAGE="$(detect_appimage)"
fi
[ -z "$APPIMAGE" ] && fatal "Could not find the FireAlpaca AppImage. Pass it with -a/--appimage."
[ -f "$APPIMAGE" ] || fatal "AppImage not found: $APPIMAGE"
log "Using AppImage: $APPIMAGE"

# -------------------------------------------------------------- qt version
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "Extracting AppImage to inspect bundled Qt version (one-time)..."
( cd "$TMP" && "$APPIMAGE" --appimage-extract >/dev/null 2>&1 ) \
  || fatal "Failed to extract AppImage (is it a valid AppImage?)"

CORE_LIB="$(find "$TMP/squashfs-root" -name 'libQt6Core.so.6' -print -quit)"
[ -n "$CORE_LIB" ] || fatal "No Qt 6 detected inside the AppImage - is this FireAlpaca?"
QT_VER="$(strings "$CORE_LIB" | grep -m1 -E '^6\.[0-9]+\.[0-9]+$' || true)"
[ -n "$QT_VER" ] || fatal "Could not read Qt version from '$CORE_LIB'"
log "Bundled Qt version: $QT_VER"

# -------------------------------------------------------------- download
pkg_candidates() {
  # Exact version first, then same-minor descend, then previous minor.
  local major minor patch
  IFS=. read -r major minor patch <<< "$QT_VER"
  local p=$((minor - 1))
  [ "$p" -lt 0 ] && p=0
  echo "$QT_VER"
  for ((i=patch-1; i>=0; i--)); do echo "$major.$minor.$i"; done
  for ((i=patch; i>=0; i--)); do echo "$major.$p.$i"; done
}

PKG_FILE=""
for v in $(pkg_candidates | awk '!seen[$0]++'); do
  for rel in 1 2 3; do
    url="$ARCHIVE_BASE/qt6-wayland-$v-$rel-x86_64.pkg.tar.zst"
    if curl -sfIL --max-time 20 "$url" >/dev/null 2>&1; then
      PKG_FILE="$url"
      break 2
    fi
  done
done
[ -n "$PKG_FILE" ] || fatal "No qt6-wayland package found for Qt $QT_VER (and no older ABI-compatible version). Try a newer FireAlpaca AppImage."

PACK="${TMP}/qt6-wayland.pkg.tar.zst"
log "Downloading $PKG_FILE"
curl -sfL "$url" -o "$PACK" || fatal "Download failed."

# -------------------------------------------------------------- extract
WL_DIR="${TMP}/wl"
mkdir -p "$WL_DIR"
log "Extracting Wayland platform plugin..."
zstd -dc "$PACK" | tar x --wildcards -C "$WL_DIR" \
  'usr/lib/libQt6WaylandClient.so*' \
  'usr/lib/libQt6WaylandEglClientHwIntegration.so*' \
  'usr/lib/libQt6WlShellIntegration.so*' \
  'usr/lib/qt6/plugins/platforms/*wayland*' \
  'usr/lib/qt6/plugins/wayland-*/*' 2>/dev/null

[ -d "$WL_DIR/usr/lib/qt6/plugins/platforms" ] \
  || fatal "Wayland platform plugin missing from package (unexpected layout)."

# -------------------------------------------------------------- install
log "Installing Wayland plugin files to: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -rf "$WL_DIR/usr/lib/." "$INSTALL_DIR/"

PLUGIN_DIR="$INSTALL_DIR/qt6/plugins"
PLATFORM_FILE="$PLUGIN_DIR/platforms/libqwayland-generic.so"
[ -f "$PLATFORM_FILE" ] || fatal "Installed files look wrong: $PLATFORM_FILE missing."

# -------------------------------------------------------------- desktop
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
DESKTOP="$DESKTOP_DIR/firealpaca.desktop"

if [ ! -f "$DESKTOP" ]; then
  log "Creating desktop entry $DESKTOP"
  cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=FireAlpaca
Comment=FireAlpaca (natively patched for Wayland)
Icon=$(dirname "$APPIMAGE")/.icons/firealpaca
Exec=$APPIMAGE
Terminal=false
Categories=Graphics;
EOF
fi

if grep -q 'FireAlpaca-wayland' "$DESKTOP" && [ "$FORCE" = 0 ]; then
  log "Desktop entry already patched (-y to re-run)."
else
  cp -f "$DESKTOP" "$DESKTOP.bak.firealpaca-wayland"

  # Rebuild the Exec line cleanly: drop any previous injection and any of the
  # patching env vars, keep other env vars (e.g. DESKTOPINTEGRATION) and the
  # AppImage path, then prepend the Wayland environment.
  old_exec="$(sed -n 's/^Exec=//p' "$DESKTOP" | head -1)"
  keep_vars=""
  app_path=""
  for tok in $old_exec; do
    case "$tok" in
      env) ;;
      LD_LIBRARY_PATH=*|QT_PLUGIN_PATH=*|QT_QPA_PLATFORM=*) ;;
      *=*) keep_vars="$keep_vars $tok" ;;
      *) app_path="$tok" ;;
    esac
  done
  [ -n "$app_path" ] || fatal "Could not read the AppImage path from $DESKTOP"
  new_exec="Exec=env LD_LIBRARY_PATH=$INSTALL_DIR QT_PLUGIN_PATH=$INSTALL_DIR/qt6/plugins QT_QPA_PLATFORM=\"wayland;xcb\"${keep_vars:+$keep_vars} $app_path"

  awk -v new="$new_exec" '/^Exec=/{ print new; next } { print }' \
    "$DESKTOP" > "$DESKTOP.tmp" && mv -f "$DESKTOP.tmp" "$DESKTOP"
  log "Patched desktop entry: $DESKTOP"
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP" || log "Note: desktop-file-validate reported warnings (usually harmless)."
fi

cat <<EOF

Done! FireAlpaca will now run as a native Wayland app, so pen pressure works.

Next steps:
  - Close FireAlpaca if it is running, then relaunch it from your app menu.
  - If the pen still has no pressure in one app session, log out and back in
    so KWin registers the tablet as a tablet device.

Facts:
  - Patched desktop entry : $DESKTOP
  - Wayland plugin files  : $INSTALL_DIR
  - Original entry backed up at: $DESKTOP.bak.firealpaca-wayland

Rollback:
  ./patch-firealpaca.sh --uninstall
EOF
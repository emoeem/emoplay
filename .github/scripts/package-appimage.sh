#!/usr/bin/env bash
# Package the built Linux bundle into an AppImage via linuxdeploy.
# Usage: package-appimage.sh <arch-name> <flutter-target-dir> <tag>
#   arch-name:          amd64 | arm64 (output name; mapped to the linuxdeploy
#                       release asset x86_64 | aarch64)
#   flutter-target-dir: x64   | arm64 (build/linux/<dir>/release/bundle)
#   tag:                release tag, e.g. v2.0.0-alpha
#
# Inputs are the same facts package-linux.sh documents: bundle at
# build/linux/<dir>/release/bundle (emoplay + data/ + lib/, RPATH $ORIGIN/lib),
# desktop file assets/linux/com.emoplay.EmoPlay.desktop, icon
# assets/icon/emoplay_icon.png installed as com.emoplay.EmoPlay.png.
#
# Output: EmoPlay_linux_<tag>_<arch>.AppImage in the repo root (cwd), next to
# the tarball/deb pair. Staging (AppDir, linuxdeploy download) stays under
# build/, which .gitignore already covers.
#
# FUSE-less environments (containers): every AppImage invocation — linuxdeploy
# itself and any nested tool it spawns — runs with --appimage-extract-and-run
# plus APPIMAGE_EXTRACT_AND_RUN=1 (the env var is inherited by the produced
# AppImage's runtime too, so consumers in the same container can run it the
# same way). Run the artifact the same way:
#   ./EmoPlay_linux_<tag>_<arch>.AppImage --appimage-extract-and-run
#
# System libraries (GTK3, ALSA/pulse, VA-API/VDPAU, ...) are intentionally NOT
# bundled — identical policy to the deb Depends list in package-linux.sh; the
# AppImage targets distros that already ship the GTK/mpv runtime stack.
set -euo pipefail

arch="$1"
target_dir="$2"
tag="$3"

bundle="build/linux/${target_dir}/release/bundle"
[ -d "$bundle" ] || { echo "bundle not found: $bundle" >&2; exit 1; }
[ -f "$bundle/emoplay" ] || { echo "bundle binary not found: $bundle/emoplay" >&2; exit 1; }

# Map the deb/tarball arch naming to linuxdeploy's release asset naming.
case "$arch" in
  amd64)  ldarch="x86_64" ;;
  arm64)  ldarch="aarch64" ;;
  *) echo "unsupported arch: $arch (amd64|arm64)" >&2; exit 1 ;;
esac

# --- Acquire linuxdeploy (cache under build/, never committed) --------------
tools_dir="build/appimage-tools"
mkdir -p "$tools_dir"
linuxdeploy="${LINUXDEPLOY_BIN:-$tools_dir/linuxdeploy-${ldarch}.AppImage}"
if [ ! -x "$linuxdeploy" ]; then
  release="${LINUXDEPLOY_RELEASE:-continuous}"
  url="https://github.com/linuxdeploy/linuxdeploy/releases/download/${release}/linuxdeploy-${ldarch}.AppImage"
  echo "downloading linuxdeploy (${ldarch}) from $url"
  curl -fSL --retry 3 -o "$linuxdeploy" "$url"
  chmod +x "$linuxdeploy"
fi
# The packing step runs from inside the staging dir — anchor the tool path.
linuxdeploy="$(cd "$(dirname "$linuxdeploy")" && pwd)/$(basename "$linuxdeploy")"

# --- FUSE-less detection: containers typically ship /dev/fuse without fusermount3
extract_and_run=()
if ! command -v fusermount3 >/dev/null 2>&1 || ! [ -e /dev/fuse ]; then
  echo "no usable FUSE detected -> --appimage-extract-and-run mode"
  export APPIMAGE_EXTRACT_AND_RUN=1
  extract_and_run=(--appimage-extract-and-run)
fi

# --- Assemble the AppDir -----------------------------------------------------
# Keep the stock Flutter bundle layout intact under usr/bin: the binary keeps
# finding lib/ via its $ORIGIN/lib RPATH, and the custom AppRun below exports
# LD_LIBRARY_PATH to the same directory (belt and braces, and the documented
# contract of this script).
staging="build/appimage"
appdir="$staging/AppDir"
rm -rf "$staging"
mkdir -p "$appdir/usr/bin" \
         "$appdir/usr/share/applications" \
         "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -r "$bundle"/. "$appdir/usr/bin/"
cp assets/linux/com.emoplay.EmoPlay.desktop "$appdir/usr/share/applications/"
cp assets/icon/emoplay_icon.png \
   "$appdir/usr/share/icons/hicolor/512x512/apps/com.emoplay.EmoPlay.png"

# Custom AppRun (linuxdeploy-plugin-appimage uses it verbatim when present):
# expose the bundle lib dir (libflutter_linux_gtk.so, plugin .so files,
# libmpv.so.2, libmedia_kit_event_loop.so native assets) before exec.
cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
# EmoPlay AppRun: bundle libs live next to the binary (usr/bin/lib, the stock
# Flutter bundle layout) — export them, then hand off.
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="${HERE}/usr/bin/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${HERE}/usr/bin/emoplay" "$@"
EOF
chmod 0755 "$appdir/AppRun"

# --- linuxdeploy: validate desktop/icon, generate AppRun plumbing, pack ------
# Requires the `file` utility (appimagetool shells out to it for arch sniffing;
# the ARCH env override does NOT satisfy it — verified 2026-11-11). GitHub
# runners ship it; the EmoPlay build container got it via apt (rootfs only).
command -v file >/dev/null 2>&1 || { echo "missing dependency: file" >&2; exit 1; }
(
  cd "$staging"   # appimagetool writes the output AppImage into the cwd
  "$linuxdeploy" "${extract_and_run[@]}" \
    --appdir AppDir \
    --executable AppDir/usr/bin/emoplay \
    --desktop-file AppDir/usr/share/applications/com.emoplay.EmoPlay.desktop \
    --icon-file AppDir/usr/share/icons/hicolor/512x512/apps/com.emoplay.EmoPlay.png \
    --output appimage
)

# Normalize the name: linuxdeploy names the image after the desktop file id
# (com.emoplay.EmoPlay.AppImage); release artifacts follow the
# EmoPlay_linux_<tag>_<arch> convention shared with tarball/deb.
built="$(find "$staging" -maxdepth 1 -name '*.AppImage' -type f)"
[ -n "$built" ] || { echo "linuxdeploy produced no AppImage" >&2; exit 1; }
# shellcheck disable=SC2086 # deliberate: exactly one file is expected
set -- $built
[ "$#" -eq 1 ] || { echo "expected 1 AppImage, found: $*" >&2; exit 1; }
mv "$1" "EmoPlay_linux_${tag}_${arch}.AppImage"

echo "packaged: EmoPlay_linux_${tag}_${arch}.AppImage"

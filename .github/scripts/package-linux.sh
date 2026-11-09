#!/usr/bin/env bash
# Package a built Linux bundle into the release tarball + Debian package.
# Usage: package-linux.sh <arch-name> <flutter-target-dir> <tag>
#   arch-name:          amd64 | arm64 (deb Architecture and output names)
#   flutter-target-dir: x64   | arm64 (build/linux/<dir>/release/bundle)
#   tag:                release tag, e.g. v2.0.0-alpha
#
# EmoPlay packaging facts (replaces the Kazumi leftovers): bundle path
# /opt/EmoPlay, binary symlink /usr/bin/emoplay, desktop file
# assets/linux/com.emoplay.EmoPlay.desktop, icon assets/icon/emoplay_icon.png
# installed as com.emoplay.EmoPlay.png (the desktop entry's Icon= name).
set -euo pipefail

arch="$1"
target_dir="$2"
tag="$3"

bundle="build/linux/${target_dir}/release/bundle"
[ -d "$bundle" ] || { echo "bundle not found: $bundle" >&2; exit 1; }

# Tarball: unpack anywhere, run ./emoplay.
tar -zcvf "EmoPlay_linux_${tag}_${arch}.tar.gz" -C "$bundle" .

# Debian package.
pkgdir="EmoPlay_linux_${tag}_${arch}"
rm -rf "$pkgdir"
mkdir -p "$pkgdir/opt/EmoPlay"
mkdir -p "$pkgdir/usr/share/applications"
mkdir -p "$pkgdir/usr/share/icons/hicolor/512x512/apps"
cp -r "$bundle"/* "$pkgdir/opt/EmoPlay"
cp -r assets/linux/DEBIAN "$pkgdir/DEBIAN"
chmod 0755 "$pkgdir/DEBIAN/postinst" "$pkgdir/DEBIAN/postrm"

installed_size="$(du -sk "$pkgdir/opt" | cut -f1)"
cat > "$pkgdir/DEBIAN/control" <<EOF
Maintainer: emoeem <emoeem@users.noreply.github.com>
Package: emoplay
Version: ${tag#v}
Section: video
Priority: optional
Architecture: ${arch}
Essential: no
Installed-Size: ${installed_size}
Description: A local media player built on mpv.
 EmoPlay plays the videos and music on your disk with an mpv core
 (media-kit/libmpv), a media library with thumbnails, plugin shader and
 script support, and 1.x-compatible playback resume.
Homepage: https://github.com/emoeem/emoplay
Depends: libayatana-appindicator3-1,
         gir1.2-ayatanaappindicator3-0.1
EOF

cp assets/linux/com.emoplay.EmoPlay.desktop "$pkgdir/usr/share/applications"
cp assets/icon/emoplay_icon.png \
   "$pkgdir/usr/share/icons/hicolor/512x512/apps/com.emoplay.EmoPlay.png"

dpkg-deb --build --root-owner-group "$pkgdir" > /dev/null
echo "packaged: EmoPlay_linux_${tag}_${arch}.tar.gz EmoPlay_linux_${tag}_${arch}.deb"

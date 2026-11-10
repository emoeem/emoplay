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
# Depends rationale (deb audit 2026-11-10; binary control files reject '#'
# comment lines, so the reasoning lives here instead of inside control):
#   * Bundled and therefore NOT depended on: libmpv.so.2 +
#     libmedia_kit_event_loop.so (native_assets), libflutter_linux_gtk.so and
#     the plugin .so files — everything under build/linux/*/release/bundle/lib.
#   * Every library below is directly NEEDED by a bundled ELF and maps to a
#     package that is NOT reachable through libgtk-3-0t64's or the tray
#     packages' own Depends chains (verified with
#     `apt-cache depends --recurse --important` on Ubuntu 26.04):
#       - libgtk-3-0t64: the GTK runtime itself (bundle/emoplay directly
#         NEEDEDs libgtk-3.so.0 via libflutter_linux_gtk.so); previously only
#         reached transitively through the tray packages — now pinned
#         explicitly so app startup does not depend on that side chain.
#       - libasound2t64 (libmpv + libflutter_volume_controller_plugin),
#         libpulse0: audio output.
#       - libva2/libva-drm2/libva-x11-2/libva-wayland2/libvdpau1: hardware
#         decode, all direct NEEDEDs of bundled libmpv.so.2.
#       - libegl1/libgbm1/libdrm2/libxv1: video output / GL paths of libmpv.
#       - libxss1 (screensaver inhibit), libarchive13t64 (mpv archive loading),
#         libunwind8: direct NEEDEDs of bundled libmpv.so.2.
#   * Other non-bundled closure libraries (libgnutls30t64, liblcms2-2,
#     libxkbcommon0, libepoxy0, libwayland-*, libdbus-1-3, codec libs
#     libsndfile1/libmpg123-0t64/libopus0/libogg0/...) are pulled in
#     transitively by the set above; the bundle's ldd closure maps inside
#     this set's recursive Depends closure (diff empty; verified R3
#     2026-11-10: the closure's 104 dpkg packages ⊂ the 251-package
#     recursive Depends closure of the 17 Depends above).
#   * Library-count口径 (audit P2 re-measure 2026-11-11, per
#     AUDIT_FULL_2026-11-10 §P2: `readelf -d | NEEDED | sort -u | wc -l`
#     over every bundle ELF): direct NEEDED union = 63 unique sonames
#     (release == debug bundle; 13 / 12 ELFs; ldd not-found = 0), 9 of
#     them bundled (8 plugin .so + libflutter_linux_gtk.so). ldd
#     transitive closure = 125 unique resolved paths = 9 bundled + 116
#     external, plus 3 dlopen-only bundled libs (libapp.so /
#     libmedia_kit_event_loop.so / libmpv.so.2 — never in ldd output;
#     loaded by the Flutter engine / native assets, not DT_NEEDED).
#     Historical five口径 (R3 2026-11-10: 250 / 234 / 166 / 64 / 113)
#     differ by statistical scope — direct NEEDED union vs transitive
#     closure, whole bundle vs lib/ only vs main binary, with/without
#     bundled libs — none equals the originally written 115. 64→63
#     matches the R6 screen_brightness_ohos removal; the R3 "113
#     external" subtracted all 12 bundled FILES from the 125 ldd paths
#     although 3 of those files are dlopen-only (116 external today).
#   * t64 package names are the Ubuntu 24.04 (noble) and later ones — the
#     same naming the CI native-tool install steps already use.
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
Depends: libgtk-3-0t64,
         libayatana-appindicator3-1,
         gir1.2-ayatanaappindicator3-0.1,
         libasound2t64,
         libpulse0,
         libegl1,
         libgbm1,
         libdrm2,
         libva2,
         libva-drm2,
         libva-x11-2,
         libva-wayland2,
         libvdpau1,
         libxv1,
         libxss1,
         libarchive13t64,
         libunwind8
EOF

cp assets/linux/com.emoplay.EmoPlay.desktop "$pkgdir/usr/share/applications"
cp assets/icon/emoplay_icon.png \
   "$pkgdir/usr/share/icons/hicolor/512x512/apps/com.emoplay.EmoPlay.png"

dpkg-deb --build --root-owner-group "$pkgdir" > /dev/null
echo "packaged: EmoPlay_linux_${tag}_${arch}.tar.gz EmoPlay_linux_${tag}_${arch}.deb"

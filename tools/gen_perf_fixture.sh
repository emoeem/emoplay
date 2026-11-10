#!/usr/bin/env bash
# PERF fixture generator for test/perf_scan_benchmark_test.dart — 2026-11-11
# 性能定量实测 round (ROADMAP §4.1 "性能实测").
#
# Generates a 2000-file synthetic media library under /tmp (NEVER inside the
# repository): the LibraryStore walk classifies by extension and stats each
# file (lib/media/library_store.dart:405-440) without reading content, so
# 4 KiB of random bytes per file is enough. Layout: root + 16 level-1 dirs
# + 160 level-2 dirs; files at depths 0/1/2 (400/600/1000) — all inside the
# default ScanOptions.maxDepth=2 envelope so the full 2000 are found.
#
# Usage:   tools/gen_perf_fixture.sh [/tmp/emoplay-perf-lib]
# Idempotent: an existing complete fixture (marker + 2000 files) is kept.
set -euo pipefail

ROOT="${1:-/tmp/emoplay-perf-lib}"
TOTAL=2000
MARKER="$ROOT/.perf-fixture-ok"

count_files() {
  find "$ROOT" -type f ! -name '.perf-fixture-ok' | wc -l
}

if [[ -f "$MARKER" ]] && [[ "$(count_files)" -eq "$TOTAL" ]]; then
  echo "perf fixture already present: $ROOT ($(count_files) files)"
  exit 0
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"

# 16 top groups x 10 subdirs = 160 leaf directories (zero-padded like emit).
for g in $(seq 0 15); do
  gp="$(printf '%02d' "$g")"
  mkdir -p "$ROOT/group$gp"
  for s in $(seq 0 9); do
    mkdir -p "$ROOT/group$gp/sub$(printf '%02d' "$s")"
  done
done

# Extension mix mirrors real libraries (video + audio, both classified by
# mediaTypeForSuffix at lib/media/library_store.dart:505-514).
ext_for() {
  case $(( $1 % 8 )) in
    0) echo mkv ;;
    1) echo mp4 ;;
    2) echo webm ;;
    3) echo avi ;;
    4) echo mp3 ;;
    5) echo flac ;;
    6) echo ogg ;;
    7) echo m4a ;;
  esac
}

i=0
emit() { # emit <depth:0|1|2>
  local depth="$1" dir ext
  ext="$(ext_for "$i")"
  case "$depth" in
    0) dir="$ROOT" ;;
    1) dir="$ROOT/group$(printf '%02d' $(( (i / 50) % 16 )))" ;;
    2) dir="$ROOT/group$(printf '%02d' $(( (i / 12) % 16 )))/sub$(printf '%02d' $(( (i / 12) % 10 )))" ;;
  esac
  # 4 KiB random payload; the walk only stats and classifies the name.
  dd if=/dev/urandom of="$dir/clip$(printf '%05d' "$i").$ext" \
     bs=1024 count=4 status=none
  i=$((i + 1))
}

# Depth distribution: 400 root / 600 level-1 / 1000 level-2.
while (( i < 400 )); do emit 0; done
while (( i < 1000 )); do emit 1; done
while (( i < 2000 )); do emit 2; done

printf 'files=%s\ndirs=root+16x10\ndepths=0/1/2=400/600/1000\ngenerated=%s\n' \
  "$TOTAL" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER"
echo "perf fixture ready: $ROOT ($(count_files) media files)"

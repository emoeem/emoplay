# NOTICE

EmoPlay is a local media player built on mpv (via media-kit). This project is
licensed under the **GNU General Public License v3.0** (see `LICENSE`).

This repository imports and adapts code from the following upstream projects;
their copyright notices and license headers are preserved in the source files.
A file-level import/strip record is kept in `docs/UPSTREAM.md`,
`docs/STRIP-LIST.md` and `docs/PORT-MAP.md`.

## Kazumi

- Copyright (c) Predidit and contributors
- License: GPL-3.0 (<https://github.com/Predidit/Kazumi>)
- Scope: application skeleton, player stack, settings components, shader
  service, platform shells (imported at commit `7265274`, see
  `docs/UPSTREAM.md`). All anime-business code (Bangumi API, rule engine,
  danmaku, Syncplay, download) was stripped; the remaining framework code
  keeps its upstream license headers.

## PiliPlus

- Copyright (c) bggRGjQaUbCoE and contributors
- License: GPL-3.0 (<https://github.com/bggRGjQaUbCoE/PiliPlus>)
- Scope: selected player interaction widgets (progress bar, gesture
  overlays), adapted to EmoPlay's local-playback controller.

## Anime4K

- Copyright (c) bloc97
- License: MIT, see `assets/shaders/LICENSE`
- Scope: the GLSL shader set under `assets/shaders/`, kept verbatim.

## media-kit / mpv

- media-kit: Copyright (c) 2021 & onwards Hitesh Kumar Saini — MIT License
  (pinned fork `Predidit/media-kit` at commit `83b7ca63772856e1ea0158916177e136f7b7b0be`,
  see `pubspec.yaml`).
- mpv: Copyright (c) the mpv project — GPLv2+ (<https://mpv.io>), used through
  media-kit's prebuilt native packages.

## EmoPlay 1.x

- Copyright (c) emoeem
- EmoPlay 1.x (`mpv-emo`) was released under MIT; its behavior semantics and
  JSON data schemas are carried into EmoPlay 2.0, which is re-licensed as a
  whole under GPL-3.0. The 1.x repository remains at
  <https://github.com/emoeem/mpv-emo> under its original MIT license.

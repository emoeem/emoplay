# NOTICE

EmoPlay is a local media player built on mpv (via media-kit). This project is
licensed under the **GNU General Public License v3.0** (see `LICENSE`).

This repository imports and adapts code from the following upstream projects;
their copyright notices and license headers are preserved in the source files.

## Kazumi

- Copyright (c) Predidit and contributors
- License: GPL-3.0 (<https://github.com/Predidit/Kazumi>)
- Scope: application skeleton, player stack, settings components, shader
  service, platform shells (imported at commit `7265274`, see
  `docs/UPSTREAM.md`).

## PiliPlus

- Copyright (c) bggRGjQaUbCoE and contributors
- License: GPL-3.0 (<https://github.com/bggRGjQaUbCoE/PiliPlus>)
- Scope: player interaction widgets to be adapted in S2 (progress bar,
  gesture overlays). Not yet present in M1.

## Anime4K

- Copyright (c) bloc97
- License: MIT, see `assets/shaders/LICENSE`
- Scope: the GLSL shader set under `assets/shaders/`, kept verbatim.

## EmoPlay 1.x

- Copyright (c) emoeem
- EmoPlay 1.x (`mpv-emo`) was released under MIT; its behavior semantics and
  JSON data schemas are carried into EmoPlay 2.0, which is re-licensed as a
  whole under GPL-3.0.

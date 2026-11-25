# Licenses & provenance

## Game ROM

`Boogerman (E) [!].gen` — Boogerman: A Pick and Flick Adventure,
© 1994 Interplay Productions / licensed by Sega Enterprises Ltd.
This folder contains **the user's own cartridge dump** for personal use.
The ROM is embedded in `rom/boogerman.gen.js` for offline play.
**Do not redistribute this project with the ROM embedded**, and do not
upload it to public hosts.

## Emulator core

Genesis Plus GX — Copyright (c) 1998-2003 Charles MacDonald,
(c) 2007-2026 Eke-Eke, portions Nicola Salmoria / MAME team.
Full text: `vendor/gpgx/LICENSE.txt` (upstream
libretro/genesis-plus-gx `LICENSE.txt`).

Key terms: redistributions may **not be sold or used in a commercial product
or activity**; modified redistributions must include complete source;
credits must be retained. This project is personal/non-commercial.

Build used: `romdev-core-gpgx@0.15.2` (npm), from the monteslu/romdev project
(https://github.com/monteslu/romdev), which pins upstream
https://github.com/libretro/genesis-plus-gx and applies the
`genesis-plus-gx-romdev-memory-regions.patch` debugger extension.
Files kept verbatim: `vendor/gpgx/genesis_plus_gx_libretro.js`,
`vendor/gpgx/genesis_plus_gx_libretro.wasm`, `vendor/gpgx/package.json`.
`vendor/gpgx/gpgx.web.js` is a mechanically browser-adapted copy of the glue
(see `tools/patch-glue.ps1`); `vendor/gpgx/gpgx.wasm.js` is a base64 embedding
of the unmodified wasm.

## Frontend / port framework

All `js/`, `css/`, `index.html`, `mods/`, `tools/`, `test/` files were written
for this project. No third-party JS libraries, fonts, images, or audio assets
are used; all sound comes from the emulated hardware via WebAudio.

## Reference material consulted (facts only, no code copied)

- libretro API constants/semantics: https://www.libretro.com/api/
- genesis-plus-gx libretro frontend (input map, options, memory, cheats):
  https://github.com/libretro/genesis-plus-gx (`libretro/libretro.c`)
- EmulatorJS CDN/build layout (core candidate survey):
  https://cdn.emulatorjs.org/ , https://github.com/EmulatorJS/build
- Game Genie code lists (EU): almarsguides.com, etherealgames.com,
  gamehacking.org (community codes, unverified on hardware)

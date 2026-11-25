# Boogerman PC — enhancement port framework

A multiplatform PC port of **Boogerman: A Pick and Flick Adventure** (Sega Mega
Drive, EU release) built around your own cartridge dump
(`Boogerman (E) [!].gen`, 3 MB, header checksum `DFAE` verified).

It is an **emulation-based port**: the cartridge runs on the accurate
Genesis Plus GX Mega Drive core (compiled to WebAssembly), wrapped in a
purpose-built PC shell with explicit hooks for future visual and gameplay
enhancements. It is *not* a native recompilation of the game code — see
[PORTING.md](PORTING.md) for what that would take and why this architecture
was chosen.

## Run it

**Double-click `index.html`.** That's it.

- Windows / macOS / Linux — any modern browser (Chrome, Edge, Firefox, Safari).
- No install, no server, no network: the core and your dump are embedded as
  base64 in local JS files, and everything uses classic scripts so `file://`
  works (a secure context: localStorage etc. function normally).
- Click **BOOT CARTRIDGE** once (browser autoplay policy requires a gesture
  for audio).

Optional dev server (not required): any static server works, e.g.
`python3 -m http.server` on machines that have Python.

## Controls (default, remappable in the Input tab)

| Key | Mega Drive |
|---|---|
| Arrows | D-pad |
| Z / X / C | A / B / C |
| A / S / D | X / Y / Z (6-button) |
| Enter | Start |
| Right Shift | Mode |

Gamepads (standard layout) map automatically to port 1. Touch controls appear
on coarse-pointer devices. Shortcuts: `P` pause, `F5`/`F8` save/load state,
`F9` screenshot, `M` mute, `H` help, `.` frame-advance while paused.

## What's in the shell

- **Video tab** — aspect-correct fit / integer / stretch scaling; a chainable
  WebGL post-processing pipeline (sharp-bilinear, scanlines, CRT, LCD grid
  built in; add your own shaders); brightness/contrast/saturation grade.
- **Input tab** — presets, per-button remap, per-button turbo, 3/6-button pad.
- **Cheats tab** — Game Genie (`XXXX-XXXX`) and Pro Action Replay
  (`AAAAAA:DDDD`) codes, decoded and applied by the core. An EU code pack
  ships as a mod (disabled by default).
- **States tab** — 8 save-state slots with thumbnails, export/import `.state`.
- **Mods tab** — enhancement packs: ROM patches (IPS/BPS), cheats, shaders,
  and live per-frame scripts. Drop `.js/.json/.ips/.bps` files on the page.
  See [mods/README.md](mods/README.md).
- **System tab** — volume/mute, load another ROM for the session, and all 61
  live core options (incl. `no_sprite_limit`, `enhanced_vscroll`,
  `vdp_mode` 50/60 Hz, overscan, NTSC filters, overclock).
- **Dev tab** — the gameplay-enhancement workbench: live hex view of the 64 KB
  68000 work RAM, watch expressions, and a poke box.

Drag & drop anywhere: ROMs (`.gen/.md/.bin/.smd/.sms/.gg`), patches, mods,
states. SRAM battery saves persist automatically for games that use them
(Boogerman has none).

## Verify it

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-headless.ps1 ^
  -Url "file:///S:/home/dev/boogerman-pc/web/test/harness.html" ^
  -Out test\harness-dom.html -Mode dom -Budget 30000
```

53 assertions: patch formats (IPS/BPS/CRC32), Game Genie decoding, core boot,
PAL timing (49.7015 fps / 44100 Hz), RAM access, deterministic save-state
round-trips, cheats, live options, shader chain, rendered-frame pixel checks,
mod system, WebAudio graph. Current result: **53/53 PASS**
(`test/harness-dom.html`). `index.html?autotest=1` boots the real app headless
and reports `AUTOTEST PASS`. Reference screenshots: `test/app-title.png`,
`test/app-gameplay.png`.

## Regenerate embedded assets

After replacing the dump or updating the core:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\patch-glue.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\embed-assets.ps1
```

## Legal

Personal use of your own cartridge dump. The Genesis Plus GX core is under a
**non-commercial** license; the game itself is © Interplay. Do not redistribute
this folder with the ROM embedded. See [LICENSES.md](LICENSES.md).

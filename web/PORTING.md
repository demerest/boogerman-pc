# PORTING.md — architecture, enhancement surfaces, and the native-port question

## What this port is (and is not)

A *true native port* means disassembling the 68000 code, recovering the game
logic and assets, and rewriting/rebuilding them as native PC code. For a
3 MB commercial game that is a months-to-years reverse-engineering project
(cf. Sonic CD Forever, SM64 decomp). It cannot be produced in a session, and
attempting a partial static recompilation here would yield something broken
and unmaintainable.

What ships instead is the standard, honest foundation for console→PC work:
**the original code running unmodified on an accurate emulator core, inside a
PC-native shell you own and can extend.** Every enhancement surface below is
real and tested; nothing about the game is faked or re-implemented.

## Architecture

```
index.html (classic scripts, file:// safe)
├── vendor/gpgx/gpgx.web.js      Emscripten glue, browser-adapted (tools/patch-glue.ps1)
├── vendor/gpgx/gpgx.wasm.js     base64 of genesis_plus_gx_libretro.wasm (2.73 MB)
├── rom/boogerman.gen.js         base64 of your 3 MB dump (tools/embed-assets.ps1)
└── js/
    ├── core.js     libretro bridge: env/video/audio/input callbacks, game load,
    │               timing, work-RAM access, states, SRAM, cheats, core options
    ├── video.js    framebuffer → RGBA8 → WebGL source texture → normalize pass
    │               → user shader chain → grade pass → screen; 2D mod overlay
    ├── shaders.js  GLSL ES 1.00 pass registry + chain state
    ├── audio.js    44.1 kHz stereo batches → WebAudio buffer scheduling
    ├── input.js    keyboard/gamepad/touch/virtual → retro joypad ids
    ├── patches.js  IPS + BPS appliers (CRC-verified)
    ├── cheats.js   Game Genie / PAR validation + decode (core applies them)
    ├── states.js   8 slots + export/import + SRAM persistence
    ├── mods.js     enhancement pack registry + user file loading
    ├── hooks.js    per-frame/boot/audio/state event bus (the mod API)
    └── main.js     boot, fixed-timestep run loop, UI
```

### Core provenance

- **Genesis Plus GX v1.7.4 (162c343)**, libretro build from the
  `romdev-core-gpgx@0.15.2` npm package (monteslu/romdev), which pins upstream
  libretro/genesis-plus-gx and adds a debugger patch
  (`genesis-plus-gx-romdev-memory-regions.patch`).
- The stock glue targets Node/ESM; `tools/patch-glue.ps1` applies five asserted
  mechanical replacements (disable `ENVIRONMENT_IS_NODE`, drop the
  `createRequire` bootstrap, replace two `import.meta.url` uses, export a
  global) so it loads as a classic script from `file://`. The original glue and
  wasm are kept alongside for provenance.
- The core is loaded with `Module.wasmBinary` (no fetch), and the ROM is staged
  into the Emscripten FS (`Module.FS.writeFile('/roms/…')`) because this core
  loads content through its VFS from `retro_game_info.path`.

### libretro bridge notes (things that bit during development)

- Callbacks are registered with `Module.addFunction` (table growth enabled):
  env `iii`, video `viiii`, audio batch `iii`, audio single `vii`,
  input poll `v`, input state `iiiii`.
- Pixel format: the core requests **RGB565**. Packed 16-bit texture uploads
  (`UNSIGNED_SHORT_5_6_5`) are rejected by some WebGL2 drivers (SwiftShader),
  so `video.js` normalizes 565/1555/8888 → RGBA8 in JS (~61k px/frame) and
  uploads with one `texSubImage2D` per frame.
- The core's framebuffer **pitch (1440 B) is wider than the active width
  (320 px)** — rows must be stepped by pitch, not width.
- `video_refresh` dimensions change at runtime (title 256×192, gameplay
  320×224); textures/FBOs/canvas reallocate on change.
- After reallocating FBOs, **rebind the source texture** — otherwise uploads
  land on an FBO texture and the source stays mipmap-incomplete (black).
- Timing: PAL = 49.7015 fps, 44100 Hz; fixed-timestep accumulator, max 3
  catch-up frames (10 in fast-forward).
- Button map (core descriptors): retro Y=MD A, B=MD B, A=MD C, L=MD X, X=MD Y,
  R=MD Z, START=Start, SELECT=Mode.

## Enhancement surfaces (all live except ROM patches)

1. **Shaders** — `BP.shaders.register(name, {frag, filter, params})`; users add
   passes in the Video tab. Pass contract: `uTex`, `uSourceSize`, `uOutputSize`,
   `uTime` + declared float params; varying `vUv`. GLSL ES 1.00.
2. **ROM patches** — IPS/BPS applied to the dump at boot (`BP.mods` patch
   entries). BPS CRC-checks against this exact dump; IPS does not.
3. **Cheats** — GG/PAR via `retro_cheat_set`; the core decodes them. EU codes
   only for this dump.
4. **Script hooks** — `BP.hooks.onFrame(api)` with
   `api.ram.read8/16/32/write8/16/32` (64 KB work RAM, big-endian, offset 0 =
   0xFF0000), `api.input.setVirtual`, `api.video.overlayCtx` (source-res 2D
   HUD), `api.audio` taps, `api.core` (states/cheats/options). This is the
   gameplay-mod surface: trainers, auto-play, reactive effects, HUDs.
5. **Core options (61, live)** — notably `genesis_plus_gx_no_sprite_limit`
   (removes the 80-sprite/line cap), `enhanced_vscroll` (+limit),
   `vdp_mode` (force 50/60 Hz — note 60 Hz on a PAL game speeds logic ~20%),
   `overscan`, `blargg_ntsc_filter`, `overclock`, audio EQ/filters.
6. **Save states / SRAM** — `retro_serialize` (~1.01 MB snapshots),
   deterministic round-trip verified.
7. **Experimental romdev debugger API** (present in this build, 23 functions,
   exposed raw as `BP.core.romdev`): `setreg/getreg`, `vramwatch_*`,
   `dmawatch_*`, `watchpoint_*`, `readwatch_*`, `cheat_*`, `range_*`,
   `pcbreak_*` (PC breakpoints), `watchdog_set`, `regsnap_get`, `trace_*`,
   `run_pure`, `cov*`. Signatures per the romdev project docs; not yet wrapped
   in UI — the natural next step for a trainer/RE toolchain. VRAM watch hooks
   are also the plausible route to *texture replacement* style visual mods.

## Verification matrix (headless Chrome on this machine)

| Check | Result |
|---|---|
| IPS/BPS/CRC32 unit tests | pass |
| GG decode / PAR validation | pass |
| Core boot, sysinfo, addFunction | pass (v1.7.4 162c343) |
| Load dump, PAL 49.7015 fps, 44100 Hz | pass |
| 64 KB work RAM read/write | pass |
| State serialize/unserialize determinism | pass |
| Cheats set/reset, 61 options, live option set | pass |
| Rendered frame pixels (whole-frame readback) | pass |
| Shader chain (crt+scanlines, sharp-bilinear) | pass |
| Mods + cheat sync | pass |
| WebAudio context + scheduling | pass |
| Real app `?autotest=1` | AUTOTEST PASS |
| Title & gameplay screenshots | test/app-title.png, test/app-gameplay.png |

Audio was verified as a running, scheduling WebAudio graph; headless runs
cannot prove audibility — listen once on real hardware.

## Roadmap to a true native port (if ever wanted)

1. 68k disassembly + trace-based decompilation (the romdev trace/pcbreak API
   here is a usable starting instrument), asset extraction (tiles/palettes/
   maps from VRAM dumps), audio driver rewrite (YM2612 + PSG → WebAudio/native).
2. Reimplement engine subsystems against recovered logic, test against
   emulator reference frames (this shell can serve as the oracle).
3. Only then: native rendering, widescreen, recompiled gameplay code.
Estimate: person-months to person-years. The emulation shell remains the
pragmatic base until then; enhancements made here (patches, shaders, scripts)
carry over to a native port as specifications.

## Multiplatform story

The app is platform-neutral (browser runtime). For a desktop-icon experience,
wrap `index.html` in Electron/Tauri later — no code changes needed; the
embedded-asset design keeps it offline-capable inside a wrapper too.

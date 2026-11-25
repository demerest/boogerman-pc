# Mods - enhancement packs for Boogerman PC

A mod is a plain object registered with `BP.mods.register(def)`. Built-in mods
are `.js` files in this folder loaded by `index.html`. Users can also drop
`.js`, `.json`, `.ips` or `.bps` files anywhere on the page (or use the Mods
tab loader) - no server, no build step.

## Mod definition

```js
BP.mods.register({
  id: 'my-mod',                 // unique; user files get 'user:<filename>'
  name: 'My enhancement',
  version: '1.0',
  author: 'you',
  description: 'What it does',
  enabledByDefault: false,

  // 1) ROM patches - applied to the cartridge bytes at boot (needs reboot).
  //    IPS and BPS are both supported; BPS verifies CRCs against this dump.
  patches: [{ format: 'ips', b64: '<base64 of .ips file>' }],

  // 2) Cheats - added to the Cheats tab (not auto-enabled).
  //    Game Genie 'XXXX-XXXX' or PAR 'AAAAAA:DDDD'. EU codes for this dump!
  cheats: [{ code: 'AT4T-AA86', label: 'Infinite lives' }],

  // 3) Shaders - registered into the video pipeline; user adds them to the
  //    chain in the Video tab. GLSL ES 1.00 fragment shader.
  shaders: [{
    name: 'my-green-tint',
    label: 'Slime vision',
    filter: 'linear',           // source sampling: 'nearest' | 'linear'
    params: [{ name: 'uAmount', label: 'Amount', min: 0, max: 1, step: 0.05, def: 0.5 }],
    frag: `precision mediump float;
      varying vec2 vUv;
      uniform sampler2D uTex;
      uniform vec2 uSourceSize;
      uniform vec2 uOutputSize;
      uniform float uTime;
      uniform float uAmount;
      void main() {
        vec3 c = texture2D(uTex, vUv).rgb;
        c = mix(c, c * vec3(0.6, 1.2, 0.6), uAmount);
        gl_FragColor = vec4(c, 1.0);
      }`
  }],

  // 4) Script hooks - live gameplay scripting, run every emulated frame.
  hooks: {
    boot(api) { /* game (re)loaded */ },
    frame(api) {
      // api.frame            - frame counter
      // api.ram.read8/16/32(addr)      - 68000 work RAM (addr 0..0xFFFF = 0xFF0000..0xFFFFFF)
      // api.ram.write8/16/32(addr, v)  - poke RAM (big-endian words)
      // api.ram.bytes()      - raw Uint8Array view of the 64KB work RAM
      // api.input.setVirtual(0, id, down) - inject controller input
      // api.video.overlayCtx - 2D canvas at source resolution for HUD drawing
      // api.video.clearOverlay()
      // api.core             - full BP.core surface (states, cheats, options...)
    },
    audio(api) { /* api.samples Int16Array stereo, api.frames */ }
  }
});
```

## What each surface is good for

| Surface | Applies | Good for |
|---|---|---|
| `patches` | at boot (reboot) | gameplay rewrites, difficulty edits, text/graphics swaps in ROM |
| `cheats` | live | infinite lives/energy, level select, physics tweaks via RAM |
| `shaders` | live | visual enhancements: CRT, color, scanlines, custom effects |
| `hooks` | live | HUDs, trainers, auto-play, RAM watchers, reactive effects |

## Built-in examples

- `overlay-demo.js` - script mod: frame/session HUD + live RAM word (template).
- `eu-cheats.js` - cheat mod: community Game Genie codes for the EU release
  (unverified; toggle individually in the Cheats tab).

## Finding RAM addresses for gameplay mods

Use the **Dev** tab: hex view of the 64KB work RAM, live watch, and poke box.
Typical workflow: watch a value while playing (e.g. lives counter), narrow the
address by change-searching manually, then poke to confirm, then write a
`hooks.frame` mod or a Game Genie code for it. The core also ships experimental
`romdev_*` debugger extensions (registers, watchpoints, PC breakpoints,
tracing) - see PORTING.md.

## Notes

- Game Genie codes are **region-specific**. This port embeds the EU dump
  (`Boogerman (E) [!].gen`); US codes will usually patch the wrong bytes.
- BPS patches CRC-check the source: they only apply to the exact dump they
  were built for. IPS has no checksums - wrong-version patches apply silently.
- A patch mod that changes ROM bytes requires a reboot (the Mods tab shows an
  "Apply patches & reboot" button when any patch mod is enabled).

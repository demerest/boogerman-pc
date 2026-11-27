# Cartridge dump (not included in this repository)

The web port embeds your **own** cartridge dump as base64 for offline play.
That embedded copy (`boogerman.gen.js`) is deliberately **not** committed:
the game is © Interplay and only your personal dump may be used.

To run the web port from a fresh clone:

1. Place your dump here as `Boogerman (E) [!].gen`
   (EU/PAL, 3,145,728 bytes, header checksum `DFAE`,
   SHA-1 `4fd33eeaf1e804d005793a6e1185122fd7e9a751`).
2. From the repository root run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File web\tools\embed-assets.ps1`
   (the script also accepts the dump one directory above `web/`).
3. Open `web/index.html`.

Other regions/versions may work but are untested; the cheat pack and RAM map
in `native/docs/RAM_MAP.md` target the EU release.

## US oracle (s64)

If `Boogerman (U) [!].gen` is also present (repo root or `web/`), the embed
script additionally writes `rom/boogerman_us.gen.js` (also never committed).
`web/test/ram-shot.html?rom=us` then runs the US dump as a region-matched
oracle for the native US port; add `wtFull=1` to watch the whole level header
0A50..0AD6. The core reads the region from the cartridge header (US = NTSC),
so web-US frame numbers differ from web-EU — compare by phase
(0244/0254/1506 events), not by raw frame.

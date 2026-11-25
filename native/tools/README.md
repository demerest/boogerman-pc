# native/tools — local-only tooling (binaries not committed)

## GenesisRecomp (static recompiler)

Prebuilt Windows x64 recompiler used for codegen:

- Package: `romdev-core-gpgx` is the *core*; the recompiler binary comes from
  the framework releases:
  https://github.com/mstan/segagenesisrecomp/releases/tag/v0.1.3
  asset `GenesisRecomp-windows-x64-v0.1.3.zip`
- SHA-256 of the zip: see `SHA256SUMS.txt` (kept in git); verify after download.
- Extract to `native/tools/recompiler/` so the exe lands at
  `native/tools/recompiler/GenesisRecomp.exe`.
- CMake picks it up via `-DGENESIS_RECOMPILER_EXE=<that path>`; alternatively
  build the recompiler from the `segagenesisrecomp` submodule
  (`recompiler/` target).

## Local debug artifacts (gitignored)

`boot-snd_ring.txt`, `boot-chip_ring.txt`, `boot-z80_ram.bin`, `ram-web-*.html`
are session debug dumps produced by the runner's `snd_dump` command and the
web oracle's `web/test/ram-dump.html`. Regenerate as needed; never commit
(they contain copyrighted game state/imagery).

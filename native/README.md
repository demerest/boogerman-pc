# BoogermanRecomp — native PC / Steam Deck port (static recompilation)

Native port of **Boogerman: A Pick and Flick Adventure** (Mega Drive, EU) built
on [segagenesisrecomp](https://github.com/mstan/segagenesisrecomp): the game's
68000 code is **statically recompiled to C** and compiled into a native
executable against a clean-room Genesis runtime (VDP, YM2612, PSG, Z80,
scheduler, SDL2). **No emulator core in the hot path.**

The web port in `../web/` is kept as a reference oracle for validation.

## Status: M2 — native exe builds and boots; stalls at PAL screen (M3 next)

Measured on our dump (`Boogerman (E) [!].gen`, SHA-1
`4fd33eeaf1e804d005793a6e1185122fd7e9a751`, header checksum `DFAE` verified):

- **203 functions discovered statically → 245 after boundary splitting**
- 394 native callgraph edges; emitted as 32 C parts + dispatch + layout +
  cycles TUs (38 files, ~2.86 MB of C) in `generated/`
- 28 dispatch sites: 23 static, 1 hybrid, 4 dynamic-register (runtime
  Tier-3 interpreter fallback covers misses)
- 1 PC-indexed jump table auto-enumerated (25 targets); 6 register-indirect
  JMP sites logged in `generated/boogerman.unresolved_jumptables.log`
- Only **5 unsupported-instruction events**, all from one odd-address
  auto-discovery artifact (`$010001`, now blacklisted)
- **Zero manual reverse-engineering was needed for this pass**
- **Native build + boot:** `build/Release/BoogermanRecomp.exe` runs headless
  and renders the authentic PAL boot screen (`captures/frame_000000.png`);
  a 7200-frame session logged **0 dispatch misses / 0 interpreter-floor
  entries**. The guest then dies in an exception loop at PC=0: the boot
  register-save area (`$FF16F8`, A6 pointer) is never established, the movem
  restore at `$294` loads zeros, and a write through `(A1=0)` bus-errors.
  Divergence window: `$244-$294` (decoder/movem semantics suspect; the
  interpreter shares the decoder and crashes identically). Engine fixes so
  far (bus-ack latency, boot trace, rewind-size guards) are saved in
  `patches/segagenesisrecomp/`. Evidence + next experiments:
  `docs/ROADMAP.md` (M2 blocker), `docs/RAM_MAP.md`.

## Layout

```
native/
├── game.toml               game config (ram_layout placeholders pending RE)
├── .recomp.json            recomp.fyi project metadata (status: exploring)
├── generated/              emitted C (regenerate; never hand-edit)
├── segagenesisrecomp/      framework clone w/ submodules (pinned; see below)
├── reference-top-gear-2/   shipped per-game recomp used as build-layout reference
├── tools/recompiler/       prebuilt GenesisRecomp v0.1.3 (SHA256-verified)
└── docs/ROADMAP.md         feasibility findings + milestones
```

Framework pin: clone of `mstan/segagenesisrecomp` @ HEAD on 2026-11-24
(submodules: m68k-recomp-core `6f705f2`, rbengine `b29bdde`, recomp-net
`2103d5e`, z80-recomp-core `4dfc5fc`, s1disasm `d343882`). Record the exact
commit before shipping; convert to a submodule pin like the reference repo.

## Engine patches (per-game work, kept in THIS repo)

The submodule gitlink stays at the **public upstream base** so a fresh clone
fetches cleanly. The Boogerman engine work (boot-assist, 68K/Z80 lockstep,
immediate bus-ack, `[BOOT-TL]`/`[JOY-TL]`/Z80 traces) is carried as
`segagenesisrecomp.diff` and applied to the submodule with:

```
powershell -File native\apply-engine-patch.ps1
```

Idempotent (skips if already applied). These patches are **never pushed to the
upstream `mstan/segagenesisrecomp` repo** — only this repo is published.

## Regenerate the C

```
native\tools\recompiler\GenesisRecomp.exe "..\Boogerman (E) [!].gen" ^
  --game game.toml --output-dir generated
```

(Or build the recompiler from `segagenesisrecomp/recompiler` with CMake once
the C++ toolchain is installed — see ROADMAP M2.)

## Next milestone (M2) — in progress

Build the runner: VS2022 Build Tools installed (C++ workload; Windows SDK
being added via `--includeRecommended` modify install), SDL2 2.28.5 VC devel
in `external/SDL2-2.28.5/`, minimal `game/boogerman_spec.c` adapter +
`CMakeLists.txt` modeled on `reference-top-gear-2/`. RE findings for the
adapter (vectors, VBlank counter `$FF0288`, routine index `$FF0516`, stack
`$FF0200`, ROM CRC32 `DBC4340C`) are in `docs/RAM_MAP.md`.

Configure + build:

```
cmake -S native -B native/build -G "Visual Studio 17 2022" -A x64 ^
  -DGENESIS_RECOMPILER_EXE=native\tools\recompiler\GenesisRecomp.exe
cmake --build native/build --config Release --parallel
```

Then headless capture and compare boot frames against the web port:

```
native\build\Release\BoogermanRecomp.exe "..\Boogerman (E) [!].gen" ^
  --input-script native\tests\boot-route.txt --capture-out native\captures ^
  --capture-from 500 --capture-to 2400 --capture-every 100 --exit-at-frame 2500
```

Details and the full milestone plan: `docs/ROADMAP.md`.

## License

Framework + reference: **PolyForm Noncommercial 1.0.0**. Our adapter/config:
same intent (personal, non-commercial). The ROM, generated game code and
Interplay artwork are **not** covered by any project license — keep them local,
never commit or redistribute them.

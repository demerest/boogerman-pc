# Feasibility & roadmap — Boogerman native recomp

## The question, answered with evidence

"Is it really that hard to reverse/recompile a Mega Drive ROM? People port
PS2/PS3 games now."

Correct intuition, with one correction: those PS2/PS3-era ports (and the N64
recomp wave) are mostly **static recompilation or large team decompilations**,
not magic. What changed since my first assessment is that **Genesis now has a
public static-recompilation framework**: `mstan/segagenesisrecomp` (C11
68000→C + clean-room VDP/YM2612/PSG/Z80 runtime, SDL2, fibers scheduler,
headless capture, interpreter fallback for dynamic dispatch). Proof it works
end-to-end: Sonic 1 playable (Green Hill complete), and
`vittau/top-gear-2-genesis-pc` — a shipped, widescreen, 60 fps native recomp
**tested on Steam Deck**, built from a user-supplied dump, 495 commits of
per-game work (disclosed as AI-assisted under maintainer review).

Measured on *our* ROM with zero manual RE (first pass, 2026-11-24):
245 native C functions, 394 callgraph edges, 23/28 dispatch sites fully
static, 5 unsupported-instruction events in one suspect data region,
6 register-indirect dispatch sites for the runtime fallback.
**The code-translation half of the port is already largely automatic.**

What remains hard (and is the real cost):
1. **Runtime integration & validation** — per-game RAM layout, VBlank/IRQ
   shape, Z80 sound driver behavior, DMA/timing quirks; proving behavior
   matches the original across routes (TG2 needed a validation ledger over
   all 16 tracks + soak runs).
2. **Dynamic dispatch coverage** — RAM-pointer dispatch and data-driven
   tables need runtime evidence (`dispatch_misses.toml`) or manual entries.
3. **Z80** — static Z80 recomp is experimental in the framework; the sound
   driver may need the runtime Z80 backend or manual work.
4. **Enhancements** (widescreen/60 fps) are per-injection-site RE work, like
   Sonic's `[[widescreen_site]]` list — optional, after baseline parity.

So: not "impossible in a session" anymore for the *pipeline*, but a **serious
multi-milestone project** for a *validated playable port*. TG2's 495 commits
is the honest order-of-magnitude for polish; incremental milestones are
verifiable much sooner.

## Milestones

- **M0 ✓** Web reference port (`../web/`) — doubles as the validation oracle
  (frame captures + input scripts can be compared against it).
- **M1 ✓** Framework setup + first codegen (numbers above). Prebuilt
  recompiler v0.1.3 SHA256-verified; framework + submodules cloned.
- **M2 — native boot. BUILD DONE, BOOT RENDERS, STALLS AT PAL SCREEN.**
  VS2022 Build Tools + Windows 10 SDK 22621 installed (winget; the VS
  `setup.exe modify` path failed with 5007, standalone SDK winget package
  worked). SDL2 2.28.5 VC devel is **vendored by the framework** at
  `segagenesisrecomp/runner/external/SDL2/SDL2-2.28.5/` (no download needed).
  `native/CMakeLists.txt` + `game/boogerman_spec.c` build
  `native/build/Release/BoogermanRecomp.exe` (MSVC, 32 generated shards).
  Headless capture run exits 0 and writes real frames:
  `native/captures/frame_000000.png` = the authentic PAL/SECAM warning screen
  rendered by the clean-room VDP from recompiled C.
  Evidence files after a 7200-frame session: **0 dispatch misses, 0 tier-3
  floor entries** — all executed code was statically materialized.
  **Blocker (localized 2026-11-25):** guest halts at `$000436` (`60FE` =
  `bra.s *`) with `imask=7`; VBlank counter `$FF0288` never increments.
  Evidence gathered with the framework's own debug server (`debug.ini` next
  to the exe enables it; port 4400):
  - `rdb_insn_break`/`rdb_step_insn` park at exact PCs; `rdb_dump` bus ring
    (with `rdb_range` filters) shows the last guest accesses are the JSR
    pushes of the region-string routine (`$3DC-$434`), then nothing: the
    halt loop makes no bus accesses.
  - `GENESIS_FORCE_INTERP=1` (full Tier-3 interpreter, same runtime) stalls
    identically ⇒ **not a native-codegen bug**; runtime/environment or
    boot-path divergence.
  - `GENESIS_STRICT_JSR_STACK=1` clean ⇒ no return-address corruption.
  - Dispatch misses / tier-3 floor entries: 0 ⇒ all dispatches materialized.
  - ROM immediates verified (`46FC 2700` at `$298/$310`) ⇒ decoder correct.
  - The interrupt unmask is `ANDI #$F8FF,SR` at **`$000702`**, inside a
    post-boot init block (`$6xx`) that also clears `$FF0516` and programs
    VDP regs. Our boot never executes that block: it goes reset →
    region-string routine → halt. Working hypothesis: `$436` is a deliberate
    main-thread halt (VBlank-driven state machine takes over), and the boot
    is supposed to pass the `$6xx` init (which unmasks) FIRST; a wrong branch
    in `$210-$3DC` (TMSS/IO reads `$A10008/$A1000C/$A1000D` are the prime
    suspects) skips it.
  - **Z80 state at halt (2026-11-25): `z80_state` → `reset_held:1`,
    `bus_requested:0`, PC=12** — the Z80 driver IS uploaded to `$A00000`
    (bytes verified) but the Z80 never leaves reset, so the sound-driver
    handshake never completes. Web oracle at frame 3 is still inside the
    bus-grant/upload phase (`A0=$A00026` cursor, `A1=$A11100`), i.e. native
    races through boot waits that web honors. Framework reset polarity is
    correct (`$A11200` bit8=1 → running, genesis_bus.c:501); the release
    write simply never happens with the right value on the native path.
    Register-save area `$FFFF16F8` is zero in BOTH at f3 (ruled out).
  - **Session 3 (2026-11-25) corrections and new evidence:**
    * Silent build failure found: adding fields to `GenesisBus` tripped
      `rb_state.c` `_Static_assert` size guards, so every build after the
      bus-ack patch FAILED and probes were talking to a stale exe. Asserts
      updated (24688 / 90600); engine changes saved as
      `patches/segagenesisrecomp/0001-boogerman-bus-ack-boot-trace.patch`.
      **Always verify the link line, not just exit code of a piped build.**
    * `GEN_DEV_TRACE=1` + `SND_TRACE_START_FRAME 0` + `snd_dump` cmd give a
      boot bus/reset ring: with the ack patch the `$25A` grant wait now
      spins ~70k cycles as designed, upload proceeds, second reset pulse
      happens — then `RESET_OFF=0` forever and **zero Z80 writes**.
    * Tier-4 insn breaks need the generated C regenerated with
      `--reverse-debug` (build helper caches; touch game.toml to force).
      `rdb_get_state` is the rich probe (parked PC/SR/D/A/stack).
    * **True crash mechanism: guest PC is literally 0** — an exception loop
      executing the vector table (imask 7, no bus activity). Not a halt at
      `$436`. Register evidence: native `A6=0` vs web `A6=$FFFF16F8`;
      save area `$FF16F8` zero; the movem restore at `$294` loads zeros,
      later writes through `(A1=0)` bus-error into the PC-0 loop.
    * ROM `$240-$244` genuinely sets A6=0/USP=0 (`moveq #0,d0; move.l d0,a6;
      move.l a6,usp`), so A6 must be re-established by a later lea before
      the movem save at `$250`; the divergence lives in the `$244-$294`
      save/restore window (decoder or movem semantics suspect; interpreter
      shares the decoder, which is why it crashes identically).
  - **Session 4 (2026-11-25) corrections:**
    * PAL timing engine patch landed: header region byte ($1F0) selects
      312-line raster + 49.7015 Hz pacer + PAL VBlank threshold
      (`g_genesis_pal`, genesis_machine.c/h, main.c). Verified live:
      `[region] header=E -> PAL timing`, pacer 49.7015.
    * **The "PC=0 exception loop" theory was WRONG**: `get_registers`/
      `rdb_get_state` PC is untracked in native builds; `crash_trail` shows
      656k blocks all at **$000436** — the guest halts in the region-check
      failure path (`bra.s *`), exactly as first concluded.
    * **Tier-4 `rdb_insn_break`/`rdb_step_insn` park the ORACLE only**, not
      native execution — all "break never fired ⇒ code never executes"
      conclusions were artifacts. Use `rdb_dump` bus ring + `crash_trail`
      for native truth.
    * Bus ring at halt: last writes are JSR pushes from `$3DC`/`$420` into
      func_000438 (conversion) ⇒ region routine DOES execute; but the
      message buffer at `$FF0484` is all zero at halt ⇒ the conversion
      wrote elsewhere ⇒ **A2 (destination) diverges inside the region
      routine**. Web at frame 3 hasn't reached the routine yet (buffers
      zero there too) — phase-matched comparison still needed.
  - **Session 5 (2026-11-25) corrections:**
    * The "$FF0484 message buffer empty ⇒ conversion wrote elsewhere"
      hypothesis was WRONG for both sides: the boot fill-loop
      (`dbra d6`, d6=$3FFF → 16384 longs = one full 64 KB work-RAM wrap)
      zeroes ALL work RAM in web AND native; empty buffers at $472-$4B2
      are expected at every web frame scanned (6/10/16/24/40).
    * Web f3/f6 register snapshots are POST-boot (web boot completes in
      ~1 frame; native boot with the ack patch takes ~3): web f3
      PC=$26C-readings and f6 PC=$E3E are gameplay-init phases, not the
      boot movem moment. Phase-matched comparison needs web frames 1-2.
    * `GENESIS_BUS_ACK_CYCLES=0` (stock immediate grant) + PAL timing
      STILL halts at $436 ⇒ the ack patch is not the cause; the divergence
      is in the region-routine translation or bus/VDP modeling,
      independent of bus-grant timing.
  - **Session 6 (2026-11-25): US profile wired; new failure subsystem.**
    * User supplied `Boogerman (U) [!].gen` (verified: checksum 8BD9,
      CRC32 1A7A2BEC, SHA-1 bb1d23ca…, region U, IRQ4=$6BDE). Two profiles
      now build side by side: `profiles/eu`, `profiles/us`, targets
      `BoogermanRecomp_eu.exe` / `_us.exe`, launchers `-EU.bat` / `-US.bat`.
    * **Entry/IRQ must use `recomp_call_addr()`** (owns a dispatch frame);
      direct `func_XXXXXX()` calls abort exit 2 on any recompiled tail call.
      Both specs fixed.
    * US boots PAST the region check (EU's $436 halt is region-specific).
      US dies at frame ~20 in the **Z80 sound-driver handshake**: 68K polls
      `$A00FAC` while `busreq=1, reset_off=1`, Z80 halted (`$0D60`/`$10A5`);
      no-progress fallback answers $00; then V-int handler runs ~9 frames
      → IRQ-DEBT crash probe. With ack=0 (stock grant) it AVs (0xC0000005)
      even earlier; with ack=70000 non-service-aware it spun ~659 frames.
    * Ack patch made **service-aware** (grant immediately inside
      `g_native_register_budget.in_vblank_service`, latency only in
      scheduled chunks) — removed the infinite service spin.
  - **Session 7 (2026-11-25): Z80 concurrency model fixed; US boot 20→110.**
    * Root cause of the frame-20 IRQ-DEBT: the scheduler slices the Z80 per
      scanline and (inside atomic V-int service) only advanced it on
      Z80-domain bus accesses, so a boot sound-init handler that polls a Z80
      flag starved the Z80. Fixes (engine patch `0001-…patch`):
      - bus-request edge syncs the Z80 across the release window
        (`genesis_bus.c`); `GENESIS_Z80_BUS_QUANTUM` models the
        finish-current-instruction latency (default 0).
      - `machine_z80_sync_to` asserts EVERY periodic Z80 vblank IRQ the
        requested time crosses (multi-frame atomic handler), replacing the
        one-frame cap (`s_z80_irq_frame`).
      - `z80_sync_for_68k_access` (glue.c) advances the Z80 on EVERY 68K bus
        access during service (true CPU parallelism), not just Z80-domain.
      - bus-ack default window 70000→1500 master (real HW grant is a few µs;
        70000 inflated every poll and starved the Z80).
    * Verified the uploaded Z80 driver image is byte-identical to ROM
      `$98D54..+$1400` (only runtime data differs) — upload is NOT corrupt.
      The driver is fully polling-driven (iff1 stays 0; the only `ei` is the
      `$0038` stub), so interrupts are not the blocker.
    * With these, US boot passes the early handshakes and reaches ~frame 110
      (was 20). Remaining blocker: a later command-ack loop (`$98D2A` waits
      `$A00FE4`==0) that no timing config completes — a superzazu-vs-driver
      interaction in the FM-init/DAC loop (`$0D2F-$0D7F`, `$174C`), i.e.
      genuine per-game Z80 RE (M3), not starvation.
    * Debug tooling: `tools/run-us-trace.ps1` (frames/quantum/interleave/
      sync-trace knobs), `tools/probe-us-z80.ps1` (live `z80_state` /
      `read_z80_ram` / `snd_dump`). Env-gated `[Z80-TRACE]` ring kept (off by
      default); unconditional probes stripped.
  - **Session 8 (2026-11-25): watchdog headroom removes the abort; boot
    completes but display never enables (M3 sound-driver RE confirmed).**
    * The exit-2 was the *instruction watchdog* (20M native insns without
      yield), not a true deadlock. Made both watchdogs env-tunable
      (`GENESIS_WATCHDOG_INSN` / `GENESIS_WATCHDOG_BUS`, glue.c). With
      headroom (400M/100M) and quantum 0, a 900-frame run exits 0 — the boot
      sound-init handler now runs to completion instead of being aborted.
    * Added env-gated `[Z80-INSN]` instruction ring (pc/opcode/A/F/BC/HL,
      dumped at exit) — it shows the Z80 *is* progressing: consuming command
      01, running `$11BE`/`$1230` channel init and draining the `$174C` DAC
      (BC decrementing). So superzazu executes the driver; it is not stuck on
      a bad instruction.
    * BUT `[VBLA] cvblank_fires=0` and 667 no-progress fallbacks: the 68K
      never leaves boot sound-init (`$98D2A`→`$98D52`→`$981F0`), so the
      display stays black and the title is never reached. The Z80 command-ack
      (`$A00FE4`) / DAC-drain handshake still doesn't complete in step with
      the 68K. This is per-game 68K↔Z80 sound-driver protocol RE (M3).
  - **Session 9 (2026-11-25): mailbox protocol decoded; 68K boot wait is the
    divergence (not Z80 concurrency).**
    * Added env-gated `[MBOX]` trace (every 68K/Z80 write to `$0FAC/$0FAD/
      $0FE4/$0FE5/$0FC2/$0FAF`) and `GENESIS_Z80_NO_BUS_HALT` test knob.
    * Protocol: the 68K builds its wait pointer `$FF051A` = `$A00000 +
      (z80[$0005]<<8 | z80[$0004])` (`$98134-$98148`); with the driver image
      that is `$A00FAC`. `func_098D24` waits `(A6)==0`. The Z80 DOES clear
      `$0FAC` after every deposit (mailbox trace), so that wait completes.
    * But the Z80 NEVER writes the "started/ack" flag (`$0FE4`), and `$0FAD`
      never receives `$FE` (68K writes 0), so the boot sound-init loop repeats
      forever and `cvblank_fires=0` → display stays black. `NO_BUS_HALT` does
      not help ⇒ the divergence is in the 68K boot's awaited value / the
      Z80's started-flag path, i.e. 68K-side boot RE (M3), not CPU scheduling.
  - **Session 10 (2026-11-25): EU region-check FIXED via region-aware $A10001.**
    * The bus returned a fixed version `0x80` (overseas NTSC). EU (PAL) games
      read `$A10001` and halt at `$436` when bit6 (PAL) is clear. Now
      `io_read` returns `0xC0` (PAL) when `g_genesis_pal` (genesis_bus.c).
    * EU now boots PAST the region screen into the SAME sound-init handshake
      as US (trail `$98D2A…$981F0`, no `$436` halt). Both profiles converge on
      the single remaining blocker: the sound-driver "started" flag.
  - **Session 11 (2026-11-25): started-flag localized to the $0FAD handshake.**
    * The Z80 writes `$0FAD=$FE` at `$0C95`, but ONLY under the guard
      `c==4` AND `($0FAD)!=0` (`ld a,($0FAD); or a; jr z,$0CC0`). The 68K
      initializes `$0FAD=0`, so the Z80 never sets `$FE` and the boot's
      "started" condition never holds. This is a 68K↔Z80 command-path
      handshake (the `$0FAD` seed value / `c==4` command), not vblank timing.
    * Boot loop after the `$0FAC` ack: `$98D52→$98AC6→$98ACA→$98AE0→$98AF4→
      $98A30→$983CE→$981F0` (re-send command). The awaited "started" flag is
      downstream of the `$0FAD` seed.
  - **Session 12 (2026-11-25): boot sound-init timeout-retry protocol fully
    mapped; ack never written by Z80.**
    * `$98AC6`: 68K deposits cmd `01` to `(A6)`=`$A00FAC`. `$98ACA`: reads ack
      at `(A6+56)`=`$A00FE4` → `$FF05BE`. `$98AD4`: reads `$A10001` bit6 (PAL);
      US (NTSC) increments timeout counter D0, EU skips. `$98AE0`: D0 vs
      `$FF0520` (timeout) → `$98AF4` release/retry. `$98ABA`: `$FF054C` nonzero
      → re-deposit. So the boot waits for the Z80 to clear `$A00FE4`.
    * The Z80 NEVER writes `$A00FE4` (=IY`$0F3C`+`$A8`); no `(iy+$A8)` opcode
      exists and no `ei` anywhere (polling-driven). Channel init `$1230`
      terminates (no YM-busy spin). The music-start/ack path simply never
      completes in superzazu. This is the hard M3 core.
  - **Session 13 (2026-11-25): NO_BUS_HALT cures Z80 starvation; boot-assist
    knob added; boot still loops before title (user chose boot-assist path).**
    * `GENESIS_Z80_NO_BUS_HALT` (z80_ready ignores busreq) raises Z80 throughput
      ~6× (265k→1.6M cycles/900f) and drops no-progress fallbacks 667→0: the
      cmd-01/DAC handshake now completes cleanly. This is the correct model for
      a polling-driven Z80 during brief arbitration.
    * Added `GENESIS_BOOT_ASSIST` (68K reads of `$0FAC`/`$0FE4` report clear in
      boot window) — had NO effect (the stuck poll isn't those reads); kept as
      a documented knob but the effective lever is NO_BUS_HALT.
    * With NO_BUS_HALT the boot passes sound-init and reaches the checksum
      stage `$1A9A` (frame ~65) but oscillates back to `$98A30` by frame ~158;
      display stays black, `cvblank_fires=0`. A deeper boot-state loop remains.
    * Probe tooling now also dumps `rdb_get_state` + `$FF0500` RAM
      (`tools/probe-us-z80.ps1 -NoBusHalt`).
  - **Session 14 (2026-11-25): boot stall = raster-timing detect mismatch.**
    * The `$1A36/$1A9A` loop is a timing/region detect: it writes measured
      D1/D2 to `$FF0216/$FF0218` and compares against expected `$FF0A78/$FF0A7A`.
      Live (NO_BUS_HALT, frame ~68): measured = 21/14, expected = 40/32 → never
      converges → boot loops (oscillates with sound-init) and never enables the
      display. So the remaining M2 blocker is V-int/raster TIMING fidelity, not
      the Z80 mailbox (which NO_BUS_HALT already fixed).
    * Probe `read_memory` needs `addr` as a hex STRING and returns `hex` (fixed
      `tools/probe-us-z80.ps1`); now dumps `$FF0500/$FF0A70/$FF0210`.
  Next experiments (in order):
  1. Match the game's raster-timing detect: determine what D1/D2 count (V-ints /
     raster lines between flags) and tune `g_vblank_threshold` / V-int line /
     pacer so measured == expected (40/32). Compare against web oracle 68K RAM
     `$FF0216/$FF0218/$FF0A78` at the same boot phase.
  2. Once boot reaches title: input-script route validation (Start → level),
     audio check, then M3 (RAM map re-verify), M4 polish/Deck.
- **M3 — RE pass.** Establish `[ram_layout]`: game_mode, vint_runcount,
  vint_routine, stacks, object table (use web port's Dev RAM watch + framework
  reverse-debug/trace to find them). Resolve the 6 indirect dispatch sites
  with runtime evidence. Decide Z80 path (runtime backend vs static).
- **M4 — playable baseline.** Cold boot → title → first level route validated
  against the web port (input, scrolling, collision, audio, transitions);
  record passed/failed/untested like the framework guide demands.
- **M5 — platforms & polish.** Linux/Steam Deck build (gcc/ninja/SDL2 deps per
  reference README; AppImage or static-SDL tarball; gamescope fullscreen),
  Windows release build, controller mapping, save states.
- **M6 — enhancements (optional).** Widescreen injection sites, 60 fps
  presentation with unchanged simulation, internal-res redraws — each behind
  a fidelity guarantee (options off ⇒ byte-identical output).

## Toolchain notes (this machine)

- No compiler existed; VS2022 Build Tools install started via winget
  (system-level, documented framework path; uninstallable via VS Installer).
- Prebuilt recompiler avoids needing MSVC for codegen itself.
- No Python: `.recomp.json` hand-written to the recomp.fyi v1 schema; avoid
  TG2-style Python build steps (icon embedding) in our adapter.
- Steam Deck target = Linux x86_64, glibc ≥ 2.35 floor for releases; develop
  builds can run on newer hosts.

## Validation strategy

Web port = trusted-enough oracle for pixels/input (itself verified 53/53
against the core). Framework cosim (recomp vs its own interpreter) plus
headless frame captures on both sides give repeatable regression checks.
Audio: capture WAV from the runner (`--capture-wav`) and compare against web
port audio dumps qualitatively first, spectrally later.

## Licenses

PolyForm Noncommercial 1.0.0 (framework, reference, our code). ROM/generated
code/artwork: © Interplay, local-only, never redistributed.

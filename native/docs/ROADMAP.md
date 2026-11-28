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
- **M2 — native boot. DONE (2026-11-25, session 16): BOTH EU and US reach the
  authentic title screen natively** (with the boot accommodations below).
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
  - **Session 15 (2026-11-25): oracle diff pins root cause — atomic V-int
    handler starves H-int counters.**
    * Added `tools/web-ram-probe.ps1` (headless-Chrome web 68K RAM dump; NOTE
      web `ram()` is LITTLE-endian, regex must skip `<title>RAMDUMP DONE`).
    * Web (oracle) by frame 120: `vint_routine=8` (game running), `$FF0218=32`
      (detect converged), counters `$FF06D2≈36`, `$FF069A≈288`. Native at the
      same phase: `$FF0216/18=21/14` (not converged), counters ~half.
    * `$FF06D2/$FF069A` are incremented by the game's H-int/V-int handlers. The
      native boot V-int handler runs ATOMICALLY (giant, Z80-bound), so level-4
      H-ints never fire during it and the counters stay low → detect fails.
      VDP H-int counter model (reg10) itself is correct.
    * => The engine must not starve H-ints/main-loop during a long boot V-int
      handler: interleave long V-int service (deliver H-ints between chunks)
      instead of running it atomically. `GENESIS_INTERLEAVE_IRQ` currently only
      applies when parked at WaitForVBlank, not to the boot poll-loop handler.
  - **Session 16 (2026-11-25): M2 DONE — both EU and US reach the title.**
    * The session-15 "counters ~half" was a PHASE mismatch (native frame 96 vs
      web frame 120). Normalized per-frame, native V-int/H-int counters advance
      at the SAME rate as the oracle — the boot is just SLOWER, not broken.
    * A 3000-frame run with `GENESIS_Z80_NO_BUS_HALT=1` + watchdog headroom
      (400M/100M) renders the authentic title screen on BOTH profiles
      (`captures-us/long/frame_000003.png`, `captures/long/frame_000003.png`):
      "BOOGERMAN — A PICK AND FLICK ADVENTURE", START, ©1994 Interplay/Sega.
    * The earlier 900-frame runs were simply too short; the detect converges
      slowly (~2000+ frames) because the Z80/handshake runs below hardware rate
      during the atomic boot handler. NO_BUS_HALT lets the polling Z80 finish.
    * Launchers (`BoogermanRecomp-US.bat` / `-EU.bat`) now set NO_BUS_HALT +
      watchdog headroom so a double-click reaches the title. Added knobs:
      `GENESIS_VINT_YIELD`, `GENESIS_Z80_OVERCLOCK` (tested; not required).
    * Remaining for M3/M4: boot is ~40 s to title (timing fidelity — interleave
      the long boot V-int handler / raise Z80 share so it matches the oracle's
      ~100-frame boot), audio correctness, then route validation & Deck build.
  - **Session 17 (2026-11-25): M3 RAM-map re-verified; route validation blocked
    on interactive-state fidelity.**
    * US `[ram_layout]` confirmed to inherit EU: `$FF0288` vint_runcount
      (`$004E14`), `$FF0516` vint_routine/game_mode (mode index 0/4/8/10/12…).
      `game_mode` set to `$FF0516` in both game.toml; RAM_MAP.md gained a US
      section. `player_object`/`plc_pending`/`level_modes` still TODO (need
      post-Start gameplay RAM diffs).
    * Route validation (`--script-start 3600 --script-right 3700`, 6000 frames)
      still shows the title: the rendered title is a boot-stage frame, not yet
      the live interactive title loop, so Start is ignored. Interactive
      playability (M4) needs the boot to reach the real title state-machine —
      same timing-fidelity root as boot speed.
    * Added service-sync Z80 overclock scaling (GENESIS_Z80_OVERCLOCK now also
      scales the in-handler sync); tested — does not by itself fix boot rate.
  - **Session 18 (2026-11-25): boot-timing fidelity — handler de-giantized;
    remaining slowness is distributed, not one giant handler.**
    * With NO_BUS_HALT the boot V-int handler no longer exceeds one frame (no
      `[IRQ-DEBT]` lines at 300 frames) — the atomic-handler starvation is
      fixed. H-int/V-int counters ($FF06D2/$FF069A) advance at ~oracle rate.
    * Yet boot still ~2000 frames: the detect converges ~200 but later boot
      stages add ~1800 more. `GENESIS_FORCE_INTERP` is SLOWER (black at 950),
      so the recompiled path + NO_BUS_HALT is the better base.
    * => Boot-speed fidelity is a multi-stage cycle-alignment task (cosim vs
      oracle per stage), not a single knob. M2 render-title + M3 RAM map stand;
      interactive title (M4) still gated on reaching the live title state.
  - **Session 19 (2026-11-25): per-stage cosim timelines captured.**
    * Added env-gated `[BOOT-TL]` (per V-int: frame, vint_count, pre-handler
      mode `$FF0516`, handler cycles). NOTE: read mode BEFORE the handler
      (it clears `$FF0516`); headless runs need `--capture-out` to advance.
    * Native (internal V-ints): mode0@~18 → mode4@~700 → mode8@~1400, then
      stays 8. Web (gx frames): mode0@vc43 → mode8@vc83. So native needs ~17×
      more V-ints to reach the title mode; each stage ~10× slower.
    * Handler cycles are small (~5.7k) and H-int counters ($FF069A) advance at
      ~oracle rate, so the lag is in the MAIN-LOOP boot state advancement per
      V-int (the detect `$FF0216/18` accrues ~1.7× slower and mode transitions
      ~10× slower), not the V-int handler nor H-int rate.
    * => Next: cosim the main-loop boot routine (the `$1A36/$1A9A` detect and
      the mode-transition code) cycle-by-cycle vs the oracle to find why it
      accrues less per V-int (likely a wait-on-flag that the native scheduler
      satisfies less often).
  - **Session 20 (2026-11-25): main-loop cosim — WaitForVBlank NOT detected.**
    * `GENESIS_YIELD_LOG=1` produced an EMPTY yield log over the boot: the
      game fiber never calls `glue_yield_for_vblank`, i.e. the codegen's
      WaitForVBla pattern (Sonic-style poll of vint_runcount) does not match
      Boogerman. So the fiber never parks; the park/interleave/pacing machinery
      that gives oracle cadence never engages, and boot runs on budget-yields
      alone → ~17× slow main-loop advancement.
    * Candidate vblank-wait: `$00616E` reads `$FF0288` but tests bit4 (`&$10`),
      not a counter-change, so it isn't auto-detected. A per-game
      WaitForVBlank/main-loop hook (spec `resume_main_loop_pc` /
      `dispatch_main_loop_pc` or a codegen pattern) is the concrete fix.
  - **Session 21 (2026-11-25): yield-hook mechanism confirmed; target non-idiomatic.**
    * The codegen supports `[game] vblank_yield_addr = <func>` (game_config.c:385,
      genesis code_generator.c:5282) to emit `glue_yield_for_vblank` for a chosen
      function; auto-detection only matches the 4-insn idiom
      (move#sr; tst.b; bne self; rts), which Boogerman lacks.
    * Inspected candidates: `$616E` (bit4 poll, mode-dispatch), `func_0062E4/AE/B4/BA`
      (VDP DMA cmd writes), `func_00169C` (OR-flag into `$FF0684`) — none is the
      WaitForVBlank. The boot main loop is a mode-dispatch chain with tail calls
      (`func_0018FC…`), so the wait is embedded, not a standalone idiom.
    * => Wiring the hook requires locating Boogerman's embedded vblank wait
      (e.g. a function/PC histogram at the live title state), a focused RE task.
      Until then M4 interactivity remains gated; M2 render-title + M3 RAM map stand.
  - **Session 22 (2026-11-25): histogram pins a 68K↔Z80 protocol deadlock.**
    * Added `tools/probe-func-histogram.ps1` (samples rdb func at title). Peak =
      `$098A30`/`$0981FC` (sound-init bus handshake), NOT a title main loop — the
      rendered title is a boot-stage background; the game never leaves sound-init.
    * Overclock 64 does NOT move the peak ⇒ not Z80-speed-bound. Live Z80 state:
      PC=$101A (main loop idle, waiting for a command at `$0FAC`), reset_held=0,
      bus_requested=1. So the Z80 consumed cmd-01 and returned to idle, but the
      68K still waits for the `$0FE4` ack ⇒ deadlock.
    * The ack is written only by the DAC-stop routine (`$1788`) when the DAC
      drains; that tick never runs because the Z80 is idle and iff1=0 (no IRQ
      tick). => The cmd-01 handler must write the ack itself; focused sound-
      driver RE (why `$11BE/$1230` doesn't reach the ack) is the next step.
  - **Session 23 (2026-11-25): BOOT_ASSIST window extended (16–4000) — no effect.**
    * Overriding 68K reads of `$0FE4`/`$0FAC` to 0 across the whole boot does NOT
      move the histogram off `$098A30` ⇒ the spin is an OUTER retry on a 68K RAM
      flag (e.g. `$FF054C`), whose success depends on the Z80 reaching the ack
      via a path that never executes — not a simple Z80-RAM poll.
    * => Next: cycle-accurate Z80 trace of cmd-01 (`$10A7→$11BE→$1230`) to the
      ack (`$1788`), and of the 68K outer retry condition, to find the exact
      missing write. This is a dedicated sound-driver RE effort.
  - **Session 24 (2026-11-25): key-PC tally — DAC-start/tick/ack never execute.**
    * Added `[Z80-KEY]` PC tally to the insn trace. Over 300 frames:
      `$1017`(cmd poll)×119857, `$10A7`/`$11BE`(cmd01)×227, `$1230`(chan init)×1362,
      `$174C`(DAC phase)×62690, but `$16E0`(DAC start)×0, `$10B4`(vblank tick)×0,
      `$1788`(ack)×0, `$0C95`×0, `$0038`(IRQ)×1.
    * `$174C` is a fractional DAC drain (`add a,e; ret nc` — only carries decrement
      BC); with the DAC never started (`$16E0`×0) the phase never carries, BC never
      reaches 0, `$1788` never writes the `$0FE4` ack ⇒ 68K waits forever.
    * cmd-01 initializes channels but never produces the ack; the DAC-start trigger
      (`$0FC2`/`$16E0`) and the vblank tick (`$10B4`, needs `$0FAD=$FE`) never fire.
      => Find what starts the DAC on real HW (the 68K's next command after init, or
      the Z80 init's ack path) — the missing link in the boot handshake.
  - **Session 25 (2026-11-25): `$0FE4` write scan — no post-init ack exists.**
    * Scanned the driver for `ld ($0FE4),a`: only `$16E0` (set `$FF`, DAC start) and
      `$1788` (clear, DAC stop). There is NO "ack after cmd-01 init" write. So the
      68K's boot wait cannot be satisfied by init alone; it expects the DAC/music
      tick to run (which needs `$0FC2`/`$0FAD` set), and those triggers never fire
      natively. `$0FC2` is only CLEARED by the Z80 (`$1740`); it is SET by the 68K
      (via `$A00FC2`), which never happens because the 68K is stuck earlier.
    * => The boot is a circular 68K↔Z80 startup that resolves on real HW via correct
      concurrent timing; native scheduling breaks the cycle. Two viable paths:
      (a) reference-Z80 cosim to find the exact divergent step, or (b) a documented
      per-game boot accommodation that breaks the cycle (skip the boot sound wait).
  - **Session 26 (2026-11-25): path (a) reference cosim — superzazu is CORRECT.**
    * Added `tools/z80_ref_test.c` (runs the uploaded driver in superzazu with a
      faithful bus stub + correct 68K stimuli). With `$0FC2=1`/`$0FAD=$FE` issued
      after cmd-01, superzazu runs `$16E0`(DAC start)×1, `$10B4`(tick)×1 and CLEARS
      the ack `$0FE4=0` (at `$178D`). ⇒ the Z80 core executes the driver correctly.
    * => The defect is on the NATIVE 68K side: it never issues the post-init
      DAC-start (`$0FC2`) / vblank (`$0FAD=$FE`, via cmd-04 `$0C95`) stimuli because
      it stalls in the sound-init wait first. The boot wait-pointer (`$FF051A` from
      z80[$0004/5]) / sequence differs from real HW.
    * Path (b) (documented boot accommodation) remains the backup to reach the
      interactive title without full 68K sequence fidelity.
  - **Session 27 (2026-11-25): path-(b) assists insufficient; framework interleave needed.**
    * Implemented path-(b) accommodations (env `GENESIS_BOOT_ASSIST`): supply
      `$0FC2=1`/`$0FAD=$FE` on cmd-consume; lengthen `$FF0520` timeout; clear
      `$FF054C` retry. NONE moves the histogram off `$098A30` (inner bus-arbitration
      wait on the DAC ack). The Z80 DAC drain is too slow under the native
      per-line/per-bus-access scheduler, so the ack never lands within the wait.
    * => Per-game knobs are exhausted. Interactive native boot requires a
      FRAMEWORK-level cycle-accurate 68K/Z80 interleave (run the Z80 concurrently
      per 68K instruction during the boot handler), a dedicated engine effort.
      Path (b) remains documented; the web port is the playable deliverable meanwhile.
  - **Session 28 (2026-11-25): full-sync + overclock also insufficient.**
    * Added `GENESIS_Z80_FULL_SYNC` (sync Z80 on every 68K bus access in the main
      loop too) and tested with overclock 64. Histogram still pinned at
      `$098A30`/`$0981FC`. Live Z80: idle main loop, shadow BC=0 (DAC never started),
      bus_requested=1. Wait pointer `$FF051A`=`$A00FAC`.
    * => No Z80 scheduling knob resolves it; the 68K sound-init state machine and
      the Z80 handshake require a cycle-accurate concurrent scheduler (per-instruction
      interleave), a dedicated engine rework. M2 render-title + M3 RAM map stand.
    * Also tested `--pacing=accurate` (CYCLE_ACCURATE wall-frame V-int guarantee) +
      full-sync: still pinned at `$098A30`. The 68K deposits cmd-01 under busreq and
      waits `$0FAC==0`; the Z80 (halted under busreq) never consumes within the wait.
      The release/consume window ordering is the crux — a per-instruction lockstep of
      the two CPUs during the handshake is the required engine change.
  - **Session 30 (2026-11-25): LOCKSTEP rework implemented (`GENESIS_LOCKSTEP`).**
    * machine_run_frame_ex now interleaves 64-cycle 68K sub-chunks with a Z80 sync
      after each (env-gated), giving true concurrency inside tight handshake loops.
    * Verified under lockstep+full-sync: Z80 runs concurrently, mailboxes clear
      (`$0FAC=0`,`$0FE4=0`), Z80 idle at `$1009`. BUT the 68K still spins at
      `$098A30`/`$981FC` = the bus-ACK wait (`$981F0` reads `$A11100` bit0). So the
      remaining stall is the busreq/ack semantics under NO_BUS_HALT, not Z80 speed.
    * => Next: reconcile z80_busreq_word (ack) with NO_BUS_HALT so the 68K's
      request/ack/release handshake completes; the ack window / busreq reporting is
      the last mismatch. M2 render-title + M3 RAM map stand; web remains playable.
  - **Session 31 (2026-11-25): TITLE REACHED in interactive mode (M2 complete).**
    * The missing link was the Z80 vblank flag `$0FAD=$FE` + DAC request `$0FC2`,
      which the stalled 68K never issues. BOOT_ASSIST now supplies them each V-int
      (glue.c), breaking the circular handshake. Combined with LOCKSTEP + FULL_SYNC
      + NO_BUS_HALT + immediate-ack, the boot advances mode 0→4→8 and renders the
      authentic BOOGERMAN title (logo/START/©1994 Interplay/Sega) by ~1500-1750f.
    * Launchers (US/EU .bat) now set the full working combo. Evidence:
      `captures-us/adv2/frame_000001.png`, `captures-us/play/frame_000001.png`.
    * Remaining for full playability: Start@1900 did not yet leave the title
      (input/title-transition gap) — next step. Boot is ~1500f (~25s); speed later.
  - **Session 32 (2026-11-25): mode 0→4→8 is automatic boot staging; Start→game
    is a separate transition.**
    * The `$FF0516=4` ($79E) and `=8` ($7DE) writes are unconditional within their
      handlers (after JSRs), so the title (mode 8) is reached without Start. Start
      must trigger a further mode change in the mode-8 routine; held Start via TCP
      (`tools/probe-start.ps1`) still left the title ⇒ the mode-8 Start detection /
      joy-RAM update is the next RE gap.
  - **Session 33 (2026-11-26): Start gate localized to $FF05B4 + joy-bit tests.**
    * Joy RAM = $FF0502 (held) / $FF0504 (pressed); under held Start $FF0502=0x0080
      (Start sampled correctly). Title mode stays 8. `tools/probe-joy.ps1` added.
    * Title Start accept requires 0 < $FF05B4 < 0x66 (attract timer); it stalls at 0
      natively. BOOT_ASSIST now holds $FF05B4=0x30 (glue.c) to open the gate; held
      Start still left the title ⇒ the joy-bit7 → game-init ($6424, mode=$10) branch
      is the remaining trace. The $61xx branch is a level-select (bits0/1), not Start.
  - **Session 34 (2026-11-26): Start-bit7 tests located in sound routine ($98666/
    $9868A), not the title.** The title→game transition is the mode=$10 write at
    $6424 (part08), guarded by the joy Start edge ($FF0504 bit7). Held Start sets
    $FF0502 bit7 but the pressed-edge/title branch still doesn't fire ⇒ next: trace
    the title routine's $FF0504 bit7 read → $6424 call, and the pad pressed-edge
    computation (part02:1801 / part21:231).
  - **Session 35 (2026-11-26): title reads processed joy $FF050C/0E (empty), not raw
    $FF0502/04.** Title Start branch = $628E read $FF050C|$FF050E, &$90, → func_0063DE
    (game-init). Raw P1 joy $FF0502=0x80 under Start but $FF050C/0E=0 ⇒ the processed-joy
    routine (part11:233/291, func_0058xx) isn't populating them. BOOT_ASSIST mirrors raw
    into $FF050C/0E + holds $FF05B4=0x30; still no transition (part11 likely overwrites
    back to 0). Next: make the part11 joy-processing routine read the correct raw pad /
    run each frame, so $FF050C/0E carry Start.
  - **Session 36 (2026-11-26): reverted 5B4/mirror assists (ineffective; kept 0FAD/0FC2).**
    * Start@1600 (title up, natural mode-8 staging) still shows title ⇒ the title's
      Start branch ($628E read $FF050C|$FF050E &$90 → func_0063DE) is not firing even
      with raw joy present. The pressed-edge ($FF050C) is 0 except on the press frame;
      the title must sample it that frame. Remaining: verify the part11 edge computation
      runs on the press frame and the title samples $FF050C in mode 8 (ordering/gate).
    * M2 (native renders authentic title) stands; boot ~1500f. Start→game is the last gap.
  - **Session 37 (2026-11-26): Start-guard hypothesis — main-loop Start poll parked.**
    * Title renders via the mode-8 V-int routine, but the Start poll is in the MAIN
      loop, which parks at WaitForVBlank. Spec resume/dispatch_main_loop_pc=0, so the
      main-loop resume may not run at the title ⇒ Start never polled. Joy mirrors/edge
      assists don't help because the poll itself isn't executing. Next: wire the
      Boogerman main-loop/WaitForVBlank resume (spec or codegen vblank_yield_addr) so the
      title main loop runs and samples Start each frame.
  - **Session 38 (2026-11-26): title histogram confirms main loop stuck in sound-init.**
    * At ~26s (title rendered) the func histogram peaks at $00203C (36) / $0030E2 (24) —
      the sound-init bus handshake, NOT the title Start routine ($628E). So the V-int
      draws the title but the MAIN loop is blocked in func_0030E2's Z80 handshake and
      never reaches the Start poll. The Start→game gap IS the sound-init handshake.
    * => The remaining blocker is the main-loop Z80 sound-init ack ($0030E2→$98xxx).
      BOOT_ASSIST (0FAD/0FC2) lets the V-int stage/render but not the main-loop ack.
      Next: resolve the main-loop sound-init Z80 response (the $00203C wait condition).
  - **Session 39 (2026-11-26): sound-service ack traced; real blocker = boot wait-for-mode.**
    * $98A10/$98A1A/$98A30 (bus request/ack/release) is immediate-ack under
      NO_BUS_HALT (read $A11100=0) ⇒ NOT a spin. func_0030E2 is a bounded
      channel-list walk (terminator at $31AC) ⇒ not a spin either.
    * Added env-gated [JOY-TL] (GENESIS_JOY_TL) per-frame joy/mode trace; use
      --measure-runtime N (uncapped, exits) — --exit-at-frame only works in capture
      mode, --runtime-uncapped needs --measure-runtime. With --script-start 1600:
      raw $FF0502=0080 and processed edge $FF050C=0080 at f1601-1602 ⇒ pad+edge
      pipeline WORKS. But $FF0516 stays 0 ⇒ the title Start branch never runs.
    * Localized: main boot parks at label_000786 (and schedulers label_0059D2 /
      label_005CD2) waiting $FF0516!=0; the 4/8/0C writes are all LATER main code, so
      the FIRST non-zero must come from the V-int boot/title handler, which never
      writes it ⇒ circular wait. Holding mode=8 via assist let schedulers pass but
      consumed the Start edge and still no $10 ⇒ reverted (ineffective).
    * => Next: find the V-int handler that first sets $FF0516 non-zero and its gate
      (likely a Z80 sound-started flag, e.g. $0FE4), or fix 68K/V-int ordering so the
      main loop reads the mode before it is cleared.
  - **Session 40 (2026-11-26): corrected wait polarity; main loop parked, only V-int runs.**
    * The mode waits (label_000786/0059D2/005CD2) loop while $FF0516 NON-zero and
      proceed at 0 (s39 had the polarity backwards). The V-int CLEARS $FF0516, so
      post-handler reads of 0 are expected (matches oracle memory), not a blocker.
    * Dispatcher re-read: at title, A (0x10) calls func_006060 (accepts Start-or-A via
      &0x90 -> func_0063DE); Start alone calls func_006F82. Pressing A at frame 1600
      (--script-start 900) still left the title.
    * Func histogram at title (120 samples): ONLY 00203C (64) / 0030E2 (56) — the V-int
      and its sound service. The MAIN loop is parked in a glue_yield_for_interrupt_poll
      wait and never executes boot staging / title dispatcher.
    * crash_trail at title: last 64 blocks ALL 000786 (total 1.39M) ⇒ main parked at
      label_000786 waiting $FF0516==0. Main wrote mode=4/8; the title V-int renders but
      does NOT clear $FF0516 to 0, so the wait never completes. THE handoff bug.
    * => Next: make the V-int clear $FF0516 after servicing (find where routine 8 should
      write 0), or assist the main/V-int mode handoff, so main resumes to the title
      dispatcher and Start/A -> func_0063DE (mode=$10).
  - **Session 41 (2026-11-26): V-int DOES clear mode; real gate = title dispatcher init flags + edge ordering.**
    * func_004DF0 (V-int) reads $FF0516, calls the routine via table at $20002, then
      WRITES $FF0516=0 at $4E00 ⇒ the handoff works; the 000786 spin is the normal
      per-frame wait, not a park. s40's "V-int doesn't clear" was wrong.
    * Added seen-mask (rdb_on_block: 1=006060,2=0063DE,4=006F82,8=005960) + a65 to
      [JOY-TL]. At title seen=8 only: dispatcher func_005960 runs but returns early.
    * func_005960 gates: $FF05D4==0xF, $FF0A65 bit0, $FF02BA!=0, $FF0284&9, then reads
      pressed edge at $598E BEFORE func_005898 computes it at $59DA ⇒ stale-edge return.
      All init flags 0 natively (title init never ran). Assisting 5D4/A65/2BA/284 opened
      the title (attract timer runs) but the edge-ordering gate still blocks Start/A.
      Flag-assist chain reverted (ineffective); seen-mask/JOY-TL kept.
    * => Next: make the processed joy edge fresh before func_005960's $598E gate (run
      func_005898 / edge compute at frame start), and set the title-init flags via the
      real init path, so Start/A reaches func_0063DE (mode=$10).
  - **Session 42 (2026-11-26): full gate chain mapped; input-frame ordering is the last blocker.**
    * func_005960 gate order: $FF05D4==0xF → $FF0A65 bit0 → $FF02BA!=0 → $FF0284&9 →
      $598E edge&0x80 (Start) → $599A wait mode==0 → func_006F82; A-path via $59E8 &0x10
      → func_006060 → &0x90 → func_0063DE. Start accept also needs 0<$FF05B4<0x66.
    * Tried: frame-start func_005898 (fresh edge) + flag assist (5D4/A65/2BA/284) +
      attract-timer hold 0x30. Attract timer runs and flags open, but seen stays 8:
      the frame-start joy samples the pad one frame early (input frame counter updates
      at V-int), so $598E still sees a stale edge. Raw A=0x40 also ≠ processed A mask 0x10.
    * => The remaining gap is input/scheduler frame ordering (pad sample vs main-loop
      read), not a RAM value. All assist chains reverted; known-good title build restored.
      Next: align s_current_frame_for_input / pad sampling so the pressed edge is present
      when func_005960 reads it, or drive the title dispatcher directly once at title.
  - **Session 43 (2026-11-26): dispatcher-drive attempt; edge lags press ~2 frames — scheduler input alignment needed.**
    * Drove func_005898+func_005960 each frame at title (+flag/timer assist). Processed
      edge appears ~2 frames AFTER the scripted press (edge=0080 at 1602 for a 1600-1601
      press), so the dispatcher never sees a coincident press; seen stays 8.
    * => The pad-sample / frame-counter / main-loop read ordering is the true last blocker.
      It is a scheduler/input-timing fix (dedicated effort), not a RAM assist. All
      assist/drive chains reverted; known-good title build restored. M2 (native authentic
      title, EU+US) stands; Start→game remains open.
  - **Session 44 (2026-11-26): edge is a 1-frame pulse; 40-frame hold + drive + flags still seen=8.**
    * func_005898 transfers a V-int pad sample from $FF04DE then computes edge=(prev^cur)&cur;
      with a sustained hold prev==cur so edge is a single pulse at the press transition.
    * Lengthened scripted Start hold to 40 frames (kept, harness). Combined with frame-start
      drive (5898+5960) + flag/timer assist: still seen=8 — the dispatcher never sees the
      pulse, i.e. the pad-sample→04DE write and the dispatcher read are not co-scheduled.
    * => Confirms a genuine scheduler/input-pipeline ordering defect. Needs dedicated work:
      make the V-int pad sample, the 04DE→0502 transfer, and func_005960's $598E read occur
      in one frame in the right order (or run the title loop as the resident main loop).
      Drive/flag assists reverted; 40-frame hold kept. M2 stands; Start→game open.
  - **Session 45 (2026-11-26): post-V-int co-scheduled drive also seen=8 — assist/drive approach exhausted.**
    * Placed func_005898+func_005960 AFTER the V-int pad sample (so $04DE fresh) + flag/timer
      assist + 40f hold: still seen=8 (no 006F82/006060/0063DE). The dispatcher never reaches
      the Start/A call under any assist/drive placement.
    * => The blocker is architectural: the recompiled boot main loop does not run the title
      state machine as a resident loop, and injected recomp_call_addr dispatches do not
      reproduce the game's frame ordering. Next dedicated effort: rework the fiber scheduler
      so the guest's own main loop runs the title routine each frame (fix the boot-loop
      re-entry / mode handoff at the scheduler level), not via injected calls or RAM assists.
      All drives reverted; known-good title build restored. M2 stands; Start→game open.
  - **Session 46 (2026-11-26): genuine --input-script held Start also fails ⇒ root cause is stalled boot main loop, not input.**
    * Used the framework's intended frame-indexed --input-script (tools/start-hold.txt,
      P1:START 1600-1700) on the known-good build: seen stays 8. Input pipeline is fine;
      the title-init flags ($FF05D4/A65/2BA/284) are 0 because the boot MAIN loop never
      completes title init (it stalls in boot sound-init / mode handoff). Title renders via
      V-int independently.
    * => Root cause confirmed upstream of input: make the boot main loop complete title init.
      Dedicated next step: wire Boogerman spec.wait_for_vblank to its actual vblank-wait
      routine (reference games set it; Boogerman=0) so the fiber parks correctly and the boot
      main loop completes, OR fix the boot sound-init completion at the scheduler level.
      Compare Sonic1/RKA main-loop/WaitForVBlank wiring. M2 stands; Start→game open.
  - **Session 47 (2026-11-26): reference-game-guided effort — Sonic1 on_post_reset sound seed applied; still stalls.**
    * Studied sonic1_spec.c: on_post_reset seeds Z80-stub sound RAM ($FFF009=$80) so UpdateMusic
      exits cleanly; resume/dispatch_main_loop_pc are save-resume fields (not per-frame).
    * Added Boogerman US on_post_reset seeding Z80 $0FAD=$FE/$0FC2=1 at reset (mirrors Sonic).
      Genuine --input-script Start hold still seen=8 ⇒ boot sound-init/title-init stall is on
      the 68K side, not fixed by Z80 seeding at reset.
    * => Precise remaining RE step: trace the boot main-loop sound-init call chain
      (func_0039EC/func_000AD2/func_0030E2) to find the 68K-side ready flag that never sets and
      why title init (5D4/A65/2BA/284) never runs; compare a working reference boot. on_post_reset
      kept (harmless, mirrors Sonic). M2 stands; Start→game open.
  - **Session 48 (2026-11-26): mode-clear handoff + genuine input also fails; title init never runs.**
    * Tested post-handler $FF0516=0 (completes the V-int→main handoff if the sub-routine RTEs
      early) combined with genuine --input-script Start hold: title still renders, seen stays 8,
      title-init flags remain 0 ⇒ the boot MAIN loop never executes title init regardless of the
      mode handoff. Mode-clear reverted; on_post_reset kept.
    * => The stall is inside the boot main loop BEFORE title init (boot sound-init / staging),
      not the V-int handoff nor input. Dedicated next step: single-step the boot main loop
      (func_0007xx) from reset to find the exact wait that never completes and the 68K/Z80 flag
      it polls; seed/fix that flag. This is the last RE gap to a playable native port.
  - **Session 49 (2026-11-26): boot-loop trace — staging runs; title warm-up (5D4→0xF) never completes.**
    * [BOOT-TL] shows mode=4/8 alternating from f73 ⇒ boot main loop runs staging each frame
      (NOT stalled at 000786). func_006A00 counts $FF05D4 up to 0xF via $FF05D6 countdown with
      reload $FF05D8; natively 5D8=0 so 5D4 stays 0 ⇒ title never "active" (dispatcher gate).
    * Start at f4000 (after would-be warm-up) via genuine --input-script: still title.
    * => Last RE gap: the title/sound init that seeds $FF05D8 (and a65/2BA/284) never runs; find
      its gate (likely the Z80 sound-started flag) and make it run, or seed 5D8 so warm-up
      completes. Combined with the earlier edge-ordering gate, both must be resolved for Start→game.
  - **Session 50 (2026-11-26): oracle-grounded title assist + pad pipeline fixed; edge forms; dispatcher cadence is the last gap.**
    * Web-oracle flag dump (web/test/flag-dump.html, f2400, byte-swapped per little-endian-word):
      interactive title has 5D4=0F, a65=03, 2BA=0001, 25A=0001, 25E=0004, 276=0080, 278=0090,
      and **5D8=0000 even on web** ⇒ s49's "5D8=0 blocks warm-up" was wrong: with reload 0 the
      warm-up ticks every frame once 284&2 holds. The native gap is the init FLAGS, not 5D8.
    * GENESIS_TITLE_ASSIST (glue.c, env-gated, f>=200) holds the gates open with those oracle
      values (284|=9, a65|=3, 2BA=1, 25A=1, 5D4=0F). Bus-tap (PAD-TL) then exposed the pad gap:
      V-int 6DE0 writes raw pad to 502, but main 5A36 overwrites 502 from $FF02B8 (pad-history
      table $FFFE00+2B6, never filled natively; 2B6 doesn't wrap) ⇒ pressed edge never formed.
      Assist mirrors 502→2B8 and holds 2B4=1 so 5A36's signed compare takes the 2B8→502 path.
    * Edge then formed (edge=0080) but 5960 runs only on mode-8 frames while 5898 recomputes a
      1-frame pulse each frame ⇒ press on a mode-4 frame lost. Assist forces prev 508/50A=0 so
      the edge is level-triggered (held button reads pressed every frame); edge now persists.
    * Still title: with gates open and edge held, 5960 early-returns mid-main because the attract
      routine 6A00 (runs before 5960) mutates 284/5D4 between the V-int assist and the dispatcher,
      and the boot-main mode-4/8 alternation skips the 5960 tail on half the frames (flow mask).
      => This is a scheduler/cadence artifact, not flags or input. Dedicated next step: make the
      guest main loop run 5960 every frame with stable gates (fix mode alternation / RTE-pending
      bails at the scheduler level, reference-game guided), then Start→func_0063DE (mode=$10).
    * TITLE_ASSIST kept (env-gated, off by default); on_post_reset kept; known-good title build.
  - **Session 51 (2026-11-26): ROOT CAUSE — V-int mode-service stubs never recompiled (data-table-only reachability); promoted via [functions] extra. Warm-up + pad now run natively.**
    * [SCHED-TL] (new env-gated gate dump at 6A00/5960/579E entry, reverse_debug.c/.h) showed the
      dispatcher gates and the 6A00 attract mutation per frame. Tracing the V-int dispatch
      (func_004DF0 reads $FF0516, JSR via long-pointer table) revealed the table base is ROM $4E22
      (the C literal `20002` is DECIMAL), mode 0/4/8/C/10 → 4E36/4E38/4E4A/4E5C/4E66.
    * Those 5 stubs are reached ONLY via the data table, so static discovery never emitted them;
      recomp_dispatch_once logged "interior-label miss" and silently no-opped each frame ⇒ the
      guest's own per-mode title init / pad-history / counter seeding never ran. THIS is the
      upstream stall behind s46–s50 (not input, not the V-int handoff).
    * Fix: profiles/{us,eu}/game.toml [functions] extra = [4E36,4E38,4E4A,4E5C,4E66]. Regeneration
      emitted 5/5 (217→259 funcs). Now 5D4 warm-up reaches 0F and the pad history fills natively
      (pressed edge forms without assist); the 4E38/4E4A dispatch misses are gone.
    * Added 5D6=1 hold to TITLE_ASSIST: 6A00's $6AC0 decrements 5D6; at 0 it wraps negative and
      $6ACC decrements 5D4→0E right before 5960 (gate1 fail). Holding 5D6=1 skips that decrement.
    * Still not playable: with assist the gates read stable (5D4=0F,a65=3,2BA=1,284&9,edge=80) but
      5960 still early-returns before 599A/6F82; the title OBJECT-handler state machine (attract bit
      284.2 set by 5CCA) is driven by init behind the 4 unresolved indirect JMPs (0031D8/003A12/
      000A5E/0070B8 = object-handler dispatch via RAM pointers). No-assist boot still stops at the
      Interplay splash (title-object init needs a65/284). => Next: promote the object-handler
      targets (read spawn constants / bus-tap the object table) so the guest's own title init runs.
    * game.toml comment corrected: vint_routine ptr table at ROM $4E22 (decimal 20002).
  - **Session 52 (2026-11-26): object-handler promotion TESTED and RULED OUT; built interpreter-coverage
    diff pipeline; real stall = second func_0030E2 display-list walk (mode 4→8), object spawn/init stride.**
    * Implemented MOVEP in runner/m68k_interp.c (exec case; cycle entry already existed). Boogerman uses
      MOVEP at $4F6A (op $0388) which previously HALTed GENESIS_FORCE_INTERP; now the clean-room
      interpreter drives the whole boot. Added GENESIS_STATE_TL (glue.c) per-120-frame PC+gate+Z80 dump.
    * New pipeline: run with GENESIS_FORCE_INTERP=1 + --exec-coverage-out, then tools/diff-coverage.ps1
      subtracts the emitted rdb_on_insn PC set from the interpreter's executed-PC set → unemitted runs.
      (PS 5.1 pipeline/ToArray quirks forced an imperative List-based implementation.)
    * RESULT: the unemitted executed set is only 138 PCs in 114 tiny runs (max 5 insns) = jump-table /
      interior fragments, NOT whole missing functions. Identical with/without TITLE_ASSIST and Start.
      Promoting these would split emitted parents (invalid extra seeds). => object-handler promotion via
      [functions] extra is NOT the lever; game.toml left unchanged.
    * STATE-TL + probe-objtable.ps1: object table $FF1A0E IS initialized (status $8058, stride $58); mode
      oscillates 0↔4 (splash runs). func_0006DA writes mode 4 at $79E then mode 8 at $7DE SEQUENTIALLY;
      native stalls in the SECOND func_0030E2 walk ($7BE) between those writes on a spawned splash object
      with a malformed/zero stride. FORCE_INTERP stalls at the same mode-4 point. So the blocker is the
      object spawn/init stride/handler seeding at splash — upstream of the title dispatcher, common to
      native+interp, not a recompiler coverage gap.
    * => Next: bus-tap object-table ($FF1A0E+) writes during the mode-4 splash to identify the spawn/init
      routine that sets strides/handlers; promote THAT real function entry; re-test mode 4→8 and Start.
  - **Session 53 (2026-11-26): bus-tap found the REAL root cause — PEA+RTS computed-jump idiom compiled as
    plain return; engine codegen fix; native now runs the object sweep; both modes converge on the splash
    +10 wait.**
    * New taps/tools: GENESIS_OBJ_TL in glue.c (object table first, then full WRAM $FF0000..$FF2212; writer
      PC real under FORCE_INTERP); GENESIS_CALL_TL watch-list entry trace (CALLT) + indirect-source trace
      (CALLSRC) + ROM→RAM flight catcher (RAMJMP) in reverse_debug.c/h and m68k_interp.c;
      tools/diff-writes.ps1 (ordered), tools/diff-writes-byaddr.ps1 (per-address, V-int-jitter immune),
      tools/probe-objchain.ps1 (stride-chain walk).
    * s52 zero-stride hypothesis DISPROVEN: stride chain healthy ($8058→$87A8→$FF220E end). Ordered
      write-diff first divergence = V-int timing jitter only; per-address diff of 8201 addresses clean ⇒
      native/interp divergence was control-flow, not data.
    * CALLT diff: after the common first spawn, interp runs the object sweep func_0029D0 (entered from
      $2900), native skipped it. Root: func_0028BE = `PEA $29D0; …; RTS` (computed jump via stack).
      code_generator MN_RTS emitted plain `return;` (the split-SP model only handles net POPS) ⇒ native
      silently skipped the sweep and stalled downstream.
    * FIX in external/m68k-recomp-core/profiles/genesis/code_generator.c MN_RTS: when path-local
      _sp_popped == -4 (one unmatched push), pop the pushed target and recomp_call_addr it
      (guest-stack-neutral), then return; 41 RTS sites carry the runtime guard. Carried as
      native/m68k-recomp-core-pea-rts.diff (nested submodule gitlink stays public); apply-engine-patch.ps1
      applies both patches. Rebuilt GenesisRecomp (build-recomp) + regenerated US.
    * Verified: native sweep entries now match interp (29D0→2A2A→2CDA…); per-address write sequences
      identical; title gate flags 5D4=0F / A65=03 / 2BA=1 set WITHOUT TITLE_ASSIST; mode oscillates 4/8.
    * Remaining blocker (BOTH modes): splash object +10 ($FF1A18) stays 0 and scroll accumulators
      $FF0A90/$FF0A92 stay 0; main fiber waits in the $14C30 loop (`cmpi #1,$A(A4)`); the V-int mode-8
      long branch func_006D60→6DE0→098000 script VM runs every frame but never completes. TITLE_ASSIST+Start
      regressed (5960 no longer reached): the assist path now blocks in the same splash wait — assist and
      authentic paths converge on one blocker.
    * => Next: find the healthy-boot writer of $FF1A18=1 / $FF0A90/92 (suspect: 098000 script VM / mode-8
      6D60 chain, gated on a Z80 SMPS ack for the splash jingle); satisfy that handshake (runner fix or
      documented SPLASH assist); re-test interactive title and Start→func_0063DE.
  - **Session 54 (2026-11-26): splash object-thread system decoded; splash COMPLETES natively;
    post-splash spawn seeds a camera object instead of the title script — the new lever.**
    * New tools: tools/dump-rom.ps1 (big-endian ROM word dump for unemitted regions; PS 5.1 `-shl`
      on [byte] truncates — cast to [int] first), tools/web-obj-probe.ps1 (oracle object-chain walk;
      ram-dump buffer is little-endian per word), run-us-misses.ps1 -SplashAssist.
    * Object system = cooperative threads: entry +4 long = continuation PC, +10 = done flag,
      +16 = countdown, w0 bit15 = inactive. Splash controller $FF1A0E (w2=5): 14ABA spawn children →
      14AF4 wait +16==0 → 14B02 stage2 → 14C30 loop (bsr 14C54 Start-skip, jsr 4970/31E0/3A14) wait
      +10==1 → 14C80 jsr 32D8 + jmp 3450 = NORMAL death (ori #8000,(A4) at 348E; 28A subi is
      bookkeeping, NOT a timeout kill — s53's kill-timeout theory corrected). obj2 (1AB08 tree) final
      gate = camera-Y $FF069A==0 at 1AB80; obj3 (15238) scroll-in drains camera 2/frame via $184A;
      obj3 completion writes controller +10 from $153E0.
    * Native completes the splash UNASSISTED: +10=1 @f552 (pc 153E0), death @554, next-stage spawn
      @747. But the respawned controller runs the camera routine (cont oscillates 54F6/54FC =
      func_005466 interior) while web's title controller runs the 15xxx script (cont 15532 @f1200).
      Title init flags only partial (a65=03/284=0002 oscillate), mode never written (md=0 at every
      V-int), 5960/6F82/63DE never entered ⇒ Start dead.
    * Sound service decoded (M3 core): func_0981FC tick body gated on 0548==0/0524==0; completion
      984D0 clears 054C after 0542 reaches 0x40; 98AA0/98D24 retry loop RE-DEPOSITS the command each
      iteration (mailbox seeding useless); Z80 stuck iff1=0 with sticky periodic IRQ in the
      $171F-$1745 poll whose per-frame flag comes from the $0038 V-int handler ⇒ genuine per-game
      Z80 RE, not scheduler starvation (per-line Z80 budget is full hardware rate).
    * GENESIS_SPLASH_ASSIST added (glue.c, env-gated, off by default): hold 28A=7FFF while controller
      cont in [14A00,14C80); seed z80 0FAC/0FE4=0; force 054C/0524/0548 idle; z80 iff1=1. Insufficient
      alone — the post-death spawn-parameter divergence is the lever, not the handshake.
    * Interp side-quest: post-splash flight to pc=FF0202 (executing data; stack/continuation
      corruption on the death/spawn path) — needs a targeted trace, separate from the native path.
    * => Next: trace the f747 respawn (3450 death tail → $6C3C branch → 2CDA spawn params) against
      web's title-controller seed; find the flag selecting camera-object vs title-script; fix or
      assist; re-test 5960/Start→63DE; restore assist-path regression coverage.
  - **Session 55 (2026-11-26): spawn chain fully decoded; s54 death-tail misdecode corrected;
    oracle region truth (web=EU); blocker moved INTO the title bytecode VM (6F82) yield/ack.**
    * Oracle region: web/rom/boogerman.gen.js sha1 = 4fd33ee… = the EU dump. All prior web-vs-native
      comparisons were cross-region (native US). run-us-misses.ps1 gained -Rom eu; EU native vs web
      EU is the clean same-ROM pair. EU native behaves like US native post-splash (camera stall),
      so the blocker is engine-side, not region-side.
    * Death tail CORRECTED: $3450-$34AE is a sprite-release loop — andi.b #$FE,($FF16EE,D2.W);
      move.w #$180,($FF182E,D6.W); addi #2,d6; dbra d2 — NOT a bra $6C3C (s54 misread the andi
      extension word 6000 + move opcode 37BC as bra.w). +40/+42 = sprite base/count (template[-8]/
      [-6]); +64/+66 = script words; ALL identical native vs web at spawn (s54's "+40/+42 diverge"
      was reading +64/+66).
    * Spawn chain: 2C0E (d0/d1/d3 ← 0A58/5A/5C, d7=FFFF) → 2CDA (template ptr = ROM[$3848+d3*4];
      w0=a1[-2], w2=a1[-4]; tst d7 selects template vs RAM 027E/0280 for +40/+42) → 2E30 free-object
      stride walk / 2E0C free-sprite scan. $34E0 = inline-param spawn helper (jsr; d4/d5/d3 read
      from the return-address stream); $49B0 = yield (pops resume PC into object+48).
    * obj2 tail: 1AB80 camera-Y gate → 1AB98 jsr 34E0 with inline type 0x2E (camera) in US — authentic
      US stage order; EU inline type 5. EU native spawns the title controller (type 5) correctly
      @f735, but its thread never leaves the camera-handler yield oscillation (cont 54BA/54C0 EU,
      54F6/54FC US); web EU reaches the attract loop (cont 154C0) by f760.
    * Title script 15740: jsr 6F82 = INLINE BYTECODE VM (consumes bytes from the stack stream,
      deposits sound cmd at 0518, tail-dispatches 9816C/98194), then +54 countdown to 0x127. The
      stall is the VM's script-pointer/ack yield interaction — same stack-idiom family as s53
      PEA+RTS — not spawn parameters. That is the s56 lever.
    * Pacing sensitivity: WITHOUT OBJ_TL (fast host run) the object sweep dies @f65; WITH OBJ_TL the
      splash completes deterministically (s55a/s55e logs line-identical). Boot completion depends on
      host pacing (audio-queue yield suspected) — needs a deterministic-pacing fix.
    * Trace truth: the hybrid interp path bypasses rdb_watch_note (CALLT blind there); OBJ-TL writer
      PC is the reliable trace for unemitted code. CALLT watch extended with death-tail + 34E0/28C4/31F2.
    * Assist regression restored: US -TitleAssist -SplashAssist + Start@1700 completes splash (@552)
      but 5960/6060/63DE/6F82 never entered ⇒ init-flag assists insufficient; the gate is inside the
      VM/camera stage. SPLASH_ASSIST remains documented, off by default.
    * => Next: EU-pair trace of the 6F82 VM byte consumption + 49B0 yield/resume stack cells
      (FF01F0-FA, object+48) vs web phase-matched; find the stuck opcode/ack; fix the codegen stack
      idiom or add a documented VM assist; re-test Start→63DE; deterministic pacing for OBJ_TL-off runs.
  - **Session 56 (2026-11-26): VM-stall hypothesis REFUTED; Start gate chain decoded (correct
    polarities); TITLE_ASSIST fixed; Start accepted (mode 0C); native EU title screen renders.**
    * Script tracks the oracle: EU native obj1 cont phases 14B2A→14C7C (intro) → 154C0/154EE
      (camera, f737-925 — the s55 "oscillation" was the authentic camera phase) → 15532 (attract
      wait). Web handler values match phase-for-phase (f760=154C0, f900=154EE, f1500=15532).
      15532 loop reads pad direction bits directly; Start goes through main-loop dispatcher 5968
      (called at 7FE every mode-8 frame; its body is read-only until the gates pass, which is why
      entry traces looked "dead").
    * Gate chain (EU 5968, correct polarities — s41 had two inverted): 5D4==0F && A65 bit0 &&
      2BA==0 && (284&9)==0 && 050C&80. 2BA=1 is the attract-DEMO marker (55CE sets it when A65
      bit1); 284 bit2 is the warm-up tick 6A36 consumes (6A94/6AAE: bit2 set + 5D4==0F → clear
      bits1+2, keep 5D4; bit2 clear → 6AB8 DECREMENTS 5D4 → gate1 sees 0E). Native pad/sound
      service never sets bit2 (2B6 history never wraps) and A65 stays 0 until a late indirect
      byte-copy (143C-1444, sound-status block; web A65=0E early) ⇒ the gate flags are an M3
      sound-init dependency, not a codegen bug.
    * TITLE_ASSIST fixed: 284 | 4 ONLY (bit2 tick; bits0/3 must stay clear for gate4), 2BA held 0
      (old assist forced 1 and blocked Start itself), A65|3, 5D4/5D6 holds unchanged. With assist,
      Start@1000 (interactive window shifts to f928-1145) is accepted: 59B2 284|10 @f1004,
      59D2 mode=0C; capture shows the native EU title (logo/START/toilet/copyright) — first
      native title visual. Right-half scroll garble during the Start loop is cosmetic at this stage.
    * Next blocker (s57): mode-C V-int handler (table 4E22 idx6 = 6054) runs every frame
      (649A-64E8 push chain, staging write FF1506=0160) but never completes to mode 10; Start
      (level-triggered by assist) re-commits mode C every 5 frames. Attract-demo path
      (countdown→1557A→+48=15776) likewise parks after f1831 (black screen) while web runs the
      demo by f2400. Both are level-init/sound-completion dependencies.
    * Tooling: web-obj-probe gained +48/+4C, stack1EC, sound and gate cells; l() needed a [long]
      cast (PS 5.1 int*int overflow promotes to Double → X6 format error). web/test/ram-shot.html:
      frame-exact web screenshots via 2D dump of BP.core.lastVideo (headless-safe). Verified
      chain-trace method: OBJ-TL JSR-push attribution (stack write v=return-addr, pc=jsr site) —
      e.g. pc=7FE v=802 proves the 5968 call. CALLT misses inlined/hybrid callees; the new
      GENESIS_INSN_TL insn-watch never fired (attribution mystery, LTCG suspect) — experimental.
    * Pacing: OBJ_TL-off runs still never leave boot (s56g); keep OBJ_TL on for regression runs.
      Deterministic-pacing fix remains open.
    * => Next: mode-C level-init completion (6054→64xx staging consumer / completion flag) native
      vs web; then Start→level-1 route; deterministic pacing; M3 sound RE to retire the assists.
  - **Session 57 (2026-11-26): Start→load route decoded end-to-end; V-int table mapping
    corrected; dispatcher-retirement assist fix; intro/teardown gap localized to the
    demo-controller tail.**
    * V-int truth: 4DF0 dispatches via LONG at 4E22+mode (byte offset = mode; the emitted C's
      "20002" is decimal 0x4E22). mode C→4E64 (flush FF3822/FF3832 blocks via 4FD8, which
      arbitrates the Z80 bus and calls RAM stub FF0202 = move.w d0,(a0); rts), 10→4E6E (4E8C
      scroll), 18→6054. s56's idx=mode>>1 was wrong; the 649A/FF1506 staging is main-loop
      7B4→6482 (gated A65 bit0 && 0246), not V-int.
    * Interactive chain: 5968 gates → 59D2 0516=0C + ack spin → 59E6 A65 bit0 → 59F0 pad bit4
      (B) → 608E load: 670C stages FF146E-150E=0180 (671C), 716C copies 71FA→FF369A, 631A sound
      blocks+VM, 62F6/6308 VDP cmds, 63AA commits 10 @63E6 + 8 scroll iters + 200× vblank wait
      (6994 = $C00004 bit3 = in_vblank in the runner), 6414 second scroll loop; then in-608E
      menu 6108-62E2 (Right/Left climb 025E, Up/Down 05B4/05B6; (A|C)&&d7==8 → 6160 confirm:
      0244=2, 0284|5, 050C|80). 5A16 Start-held fallthrough = VM 04 + 566E (sprite-table
      builder, NOT a load). s57a: B@1100 → 608E @1100, mode 10 @1102 — native runs the load.
    * Why title persisted: while the assist pins the gates, the 59D2 wait loop re-commits C
      every frame, overwriting the load. Web oracle (ram-shot press timeline + mode trace):
      stock web also has 5D4=F/A65=0 at attract (Start via 5968 only once A65 arrives ~f2400);
      its proven gameplay route is the attract demo: C@1861-1954 shows the "FLATULENT SWAMPS"
      intro with ALL object slots inactive, FF1506=0180, FF385x staged, 0245=34.
    * Phase-matched RAM diff (new tools/diff-ram.ps1 + DUMP_RAM/DUMP_VRAM script directives):
      native post-608E keeps title objects (obj0 cont 15532), FF3832 unstaged, 1506=0160 —
      6482 (enabled by our A65 bit0 hold) overwrites 670C's 0180; web keeps A65=0 so 6482 skips.
    * Assist fix (glue.c): drop A65 bit0 once 0244!=0 or md_pre==10 → gate2 fails → the 59D2
      loop retires (verified s57f: no re-commits) and 6482 skips. Necessary, not sufficient:
      the B path never runs the confirm/teardown; synthesized 0244=2 alone (s57h) also does
      not teardown. Menu climb attempts (s57e/g): 608E re-enters ~11f but 025E never persists
      — the menu pad edge plumbing (58A0/5A36, 2B4/286 signed compare) is itself broken natively.
    * Demo path (s57b): 15776 controller spawns types 1EF-1F3/3/4 @f777-1263 then parks at a
      49B0 yield whose resume never fires — before the intro stager (15978+ / FF3832 writer).
      That yield-resume ack (M3 sound family) is the s58 lever for both routes.
    * Tooling: run-us-misses -InputScript; s57-*.input timelines (frame-index lines and
      sequential directives share one op list); ram-shot.html gained a press timeline +
      mode/gate trace — web ramRead16 returns BYTE-SWAPPED words (ram() little-endian per
      word); diff-ram.ps1 swaps web pairs before diffing.
    * => Next: s58 demo-tail yield-resume + intro stager RE; menu pad plumbing; then route
      validation; deterministic pacing; M3 sound RE to retire the assists.
  - **Session 58 (2026-11-26): attract/demo state machine decoded; pad-pipeline root cause
    found and assist-fed; attract-skip reaches the intro stager natively; V-int cadence
    starvation after mode commits is the remaining core blocker.**
    * Attract controller = obj0 (FF1A0E). 154C0-1576A state machine: phase-1 pump (154DC)
      resumes the demo script 157D6-158D6 (4B8C = per-controller sprite-template ATTACH via
      obj+4E table, title ptr 112EC2 — not a spawn); +4C = countdown ticked by 4970
      (subq/bpl; FFFF = next-pass; 49AA = yield-FFFF); demo idles at 15AC2 (jsr 49AA loop) —
      s57's "park" = intentional idle + countdown waits (6f/134f), not a stuck ack. Phase 2
      (15500, +10=0190≈800f) pumps 158DA/15900 loop; +10 expiry → 1557A demo restart (+A=1).
    * Intro stager 15978 (types BB-C7) seeded ONLY at 15678: attract wait 15532 polls pad
      &8/&4 (Right/Left) or obj0+8 bit11 (demo-completion, sound-ack dependent → never fires
      natively). Post-intro 156A4-15766 seeds 15A8C (C8-CA); level scroll-in init 15ADA→15F70
      (FF0690=1/FF0A90=80, seed 15F76) never seeded natively; C8-CA completion = s59 lever.
    * Pad truth: 6D96/6E16 sampler is DEAD CODE in EU (no callers). 58A0 (main 772) transfers
      04DE→0502 + edges 050C/050E; 5A3E (main 76E) overwrites 0502 from the 2B8 mirror when
      2BA==0. Native main loop stops completing 4/8 passes post-splash; mode freezes at 4 or
      8 per-run (pacing nondeterminism); frozen-8 runs form no pad sample at all → s57's
      "broken menu plumbing" was this. Engine pad phases: TH=0 carries Start/A (bits7/6),
      TH=1 carries CBRLDU; merge ~(((p0<<2)&C0)|(p1&3F)); TH drives a 6-button protocol
      counter (io_data/pad_th_count/pad_th_prev) that must be saved/restored around probes.
    * Assist s58 (glue.c, env-gated): pad feed on mode-8 V-ints (two-phase port read, correct
      merge, TH save/restore — first attempt inverted phases → 0x3F all-buttons storm);
      retirement ONLY on confirm 0244!=0 (s57's mode-10 retirement killed the 59D2→608E menu
      pump); hold 0246=0 while mode10-unconfirmed so 6482 skips without killing the pump.
    * Verified s58g: RIGHT@1000 → 0502=8 → 15678 seeds 15978 @1001 → stager + 15A8C C8-CA
      execute (f1001-1032). Intro card still NOT rendered (black @1300/2300). s58j: Start
      accepted (mode C @1004), B@1100 → 608E re-entered every 11f while held (pump alive),
      but V-int delivery dies ~f1020-1100 after the mode-10 commit → Right/A never sampled,
      025E never climbs. Post-load black + intro black + this starvation likely share one
      root: mode-10/C V-int handler cadence (s59).
    * Tooling truths: input-script frame-index lines accept BUTTONS ONLY; any directive on a
      numbered line (EXIT/DUMP_RAM/WRITE_RAM*) rejects the WHOLE script (s_active=0) ⇒
      s57-confirm/s57h mixed form never ran — s57h "0244=2 alone doesn't teardown" UNVERIFIED,
      retest with sequential form. OBJ-TL 600k cap hit ~f1148 on demo paths → added
      GENESIS_OBJ_TL_MAX env knob. Hybrid OBJ-TL pc is stale (last interp PC) — attribute by
      address/value, or use FORCE_INTERP (which has its own post-splash stack bug, s54).
    * => Next: s59 V-int/main-loop cadence determinism (elevated); intro render + C8-CA→15F70
      chain; valid-script confirm retest; then M3 sound RE to retire assists.
  - **Session 59 (2026-11-26): cadence determinism PROVEN (s58 starvation claims were
    measurement artifacts); menu climb+confirm verified natively; web-oracle gameplay
    route decoded (Start post-attract → 0244=1 → level load); the single remaining root
    is the staged V-int RAM stub / intro-level script completion (s60).**
    * Determinism: s59c (OBJ_TL on) vs s59d (OBJ_TL off), same script/env otherwise —
      [BOOT-TL] per-V-int sequences byte-identical (2584 lines, diff=0); mode C @1005,
      mode 10 @1104 in both. The sim is sealed per tick (sim_step.c); presentation is
      output-only. s58's "V-int dies post-mode10 / 025E never climbs / frozen mode 4-8
      nondeterminism" were grep artifacts (patterns omitted the pc=/vc= fields between
      f= and a=/mode=) plus parser-rejected scripts: s58j DID climb 025E 4→6→8 @1117/1128.
      No engine cadence fix needed; item closed.
    * Menu route native: s59c/e (s59-menu2.input: Start@1000, B hold, Right×2 windows,
      wide A window 1230-1300) → 025E 4→6→8, confirm 6160 @1250 (0244=2, 284|5, 050C|80,
      025E=d7, bsr 6414). 6414 = scroll/DMA + mode-10 recommit + 200×6994 waits ×8.
      d7≠8 → 618C (6394 table → eori #1,(obj) + bsr 631A direct load); d7==8 → flag path.
      A 10f window can fall inside the ~11f 608E load-wait (no pad sampling) — widen it.
    * Post-confirm stall RE: 762 clears 0244 and 76A (5076: 5162/5AEA/55CE) run ONLY at
      cold entry — the main-loop loopback at $000802 is `bra 76E` (ROM). Per-frame head
      work therefore runs only via indirect dispatch (dispatch.c table) from the staged
      V-int RAM stub (FF0202/FF3832, mode-C handler 4E64→4FD8). Natively FF3832 is never
      staged post-boot (OBJ_TL_HI tap) ⇒ 0254 shadow/5AEA/55CE never run ⇒ both the
      menu-confirm flags and the Start flow die. Same root as s58 item 2 (intro black).
    * Web oracle (ram-shot.html gained wt=1 per-frame change timeline; s59web2, presses
      phase-matched to web's ~f2400 interactive title): Start@2450 with 2BA=1 →
      5A3E/5A48(Start held)/5A56(2B4==FFFF)/5AC0(bit2)/5ACE → 2BA=FFFF, 284|5,
      0244=[0A62]=1; ~30f later 284→0 (sound-service consumption) coincident with
      0254=1 + FF1506=0180 level staging; 05B4 countdown; level load. 5A3E full decode:
      2BA==0 → return (no mirror); 2BA!=0 + Start not held → 5A9E bit2 → 5AAC(0244=1);
      Start held + 2B4==FFFF → 5AC0; else pad-history mirror (2B6 wrap).
    * Assist s59 (glue.c, env-gated TITLE_ASSIST): OBJ_TL_HI knob (tap range, default
      2212; level objects FF36EE/FF3832 need 4000); attract-marker chain once obj0 cont
      >=15532: 2BA=1 + 2B4=FFFF (history-wrap emulation; s50's 2B4=1 hold blocked 5AC0)
      + 0A62=1 (55CE-tail value); flow-gated 284 (bit2 supply pre-transition, &~5 after
      0244/0254=1 = consumption emulation); confirm-consumption block (bit0 clear +
      Start feed while 0244==2, retire A65 only at 0244==1). s59i/j: marker engages
      @1740, Start edge forms @2202, but 0244=1 still never commits — 5A3E itself is
      head work (76E runs, but 5AC0 needs bit2 at the right instant AND the 5ACE→5AEA
      dispatch chain is stub-driven); the chain completes only once the staged V-int
      stub runs ⇒ s60.
    * Tooling: ram-shot.html wt=1 change timeline (web oracle); s59-menu2.input /
      s59-startlate.input; OBJ_TL_HI; grep discipline: OBJ-TL/BOOT-TL lines carry
      pc=/vc= fields between f= and a=/mode= — patterns must include them.
    * => Next: s60 staged V-int RAM stub / intro-level script completion (FF3832/FF0202,
      BB-C7 draw + C8-CA completion → 15ADA/15F70); then M3 sound RE to retire assists.
  - **Session 60 (2026-11-26): tap-cap blindness found+fixed (OBJ_TL_ADDRS); US V-int
    dispatch decoded (flush = pure VDP DMA, NOT head-work dispatch — s59 stub model
    corrected); web phase model decoded (attract plays a demo level, 2BA=0 through
    demo, marker returns post-demo); native demo commit verified @1816; assist
    load-starvation (A65/6482 pinning FF1506) and dead pad-feed gate fixed; Start edge
    forms natively @2201. Remaining root = post-splash V-int mode freeze at 8 (s61).**
    * Tooling: OBJ-TL's default 600k line cap was silently exhausted at f=819 with
      HI=4000 (hot boot-RAM writes) — s60a/b were blind past f819 and part of s59's
      "never commits" evidence is unverified. New GENESIS_OBJ_TL_ADDRS env knob
      (comma-list of low-16 addresses) keeps whole-run logs small (s60c-f).
    * US ROM decode (EU is +8 bytes shifted from 4E64): 4DF0 = movem, movea.w FF0516,a1,
      movea.l (4E22,a1),a0, JSR (a0), then 4E00 FF0516=0, bsr 6D60, jsr 98000 (object
      pump EVERY V-int), 0288++, rte. Table offsets: 0→4E36 rts, 4→4E38, 8→4E4A,
      C→4E5C (flush FF3822+FF3832), 10→4E66 (scroll). Flush 4FD0 = bus-req + VDP ctrl
      longs from slot+0/+6/+10 + jsr FF0202 stub (move.w d0,(a1); rts, seeded from US
      505E) + DMA-busy wait. Slots are 16-byte VDP DMA command blocks (4F60 init fill
      pattern; boot 0D76→4F8E builds FF3832 from FF146E). The flush does NOT dispatch
      5076/5AEA/55CE — s59's "staged stub performs head work" model was wrong.
    * Web phase model (s60web, wt extended with 2B4/2BA/0A62/288/3832-38/202): attract
      PLAYS A DEMO LEVEL: 0244=34 @1811 (script 1562E) + 284=5; @1841 284→0 + 0254=34 +
      0A90=60 + 0A62=35; mode C 1861-1954 (demo play); demo end → 1506=160 @2030,
      2BA=1 @2036, A65=3 by 2399 (guest-set). 2BA=0 through attract AND demo; 2B4 is a
      running counter (never FFFF); Start@2450 commits via 5AAC (Start-not-held + bit2)
      → 0244=1+284=5; @2480 0254=1/284=0/1506=180/0A62=0; @2512 55CE clr 2B4/2BA.
      Mode alternates 4/8 EVERY frame through the title.
    * Native object threads DO run: demo commit 0244=34 @1816 pc=01562E (s60c). The
      post-commit stall was assist-induced: holding A65 bit0 kept 6482's gate open so
      FF1506 was re-pinned 0160 every 2f (pc 0064B2) forever, starving the load (web
      keeps A65 bit0=0 through load/demo).
    * Assist s60 phase model (glue.c TITLE_ASSIST): commit flag on 0244/0254!=0;
      load window (0254==0 or md_pre==C) clears A65 bit0 (menu-confirm window exempt);
      post_title (commit && 0244!=1 && 0254!=0 && 1506==160) restores A65=3 + 2BA=1 +
      0A62 + service tick (284&~1)|4; load consumes 284&~5; marker 2BA=0 during
      load/demo (s60d's early supply caused spurious 5ACE 0244=1 @1817); pre-commit
      attract keeps the s59 supply incl 2B4=FFFF — the history-wrap emulation gates
      the attract demo trigger (s60e lost the demo commit without it). Pad-feed gate
      fixed to md_pre==8 (the handler clears 0516 before the assist runs; the live
      read was always 0) → Start edge 050C=80 @2201 forms natively (s60f).
    * Remaining root (s61): V-int mode FREEZES at 8 post-splash (BOOT-TL mode=8
      constant @1816-2480; web alternates 4/8 every frame). Guest pad sampler skips
      mode-8 frames; the load/demo script's mode waits stall (0254 never taken, mode C
      never reached, demo never ends → post-demo interactive title never arrives →
      Start-late cannot commit: 2BA=0 during load, web-faithful). Native 6A00 family
      runs the byte-tick branch (5B4 +1 byte @6AA4) vs web word-tick (+100/2f) — the
      branch selector diverges post-splash. s58's "frozen mode" was REAL for the
      post-splash phase; s59's determinism proof covered OBJ_TL on/off, not web
      phase-match.
    * => Next: s61 mode-4/8 alternation freeze; then route validation; M3 sound RE.
  - **Session 61 (2026-11-27): s60's "mode freeze at 8" was a grep artifact (s60f's
    own log alternates 4/8 every frame). Real root = the assist froze the guest's
    6A36 sound-service countdown; releasing it makes the demo play and Start-late
    commit natively (0244=1 @2452, 0254=1/1506=180 @2484 vs web 2480). Menu
    regression intact. Native port now reaches level-load staging from cold boot.**
    * Re-aggregated s60f/s61a BOOT-TL into mode ranges: full 4/8 alternation
      73-2599, no freeze anywhere. The real gap was 0254 never taken natively
      (no mode C, demo never played), not V-int cadence.
    * Load-chain decode (US ROM): demo script 1562E writes 0244=34 + 284|5 then
      bra 15560 wait loop (jsr 4970/31E0/3A14; tst (4C,a5); bmi exit). 4970 =
      coroutine yield: +4C countdown, +48 = resume PC, 49AA sets +4C=-1 when the
      continuation returns. The 15740 continuation = intro chunk loader
      ((54,a0) counts to 0x127); it completes natively @~1814 then idles at 579C
      re-arming +4C=1 (the 0/1 mailbox oscillation both ports show).
    * Guest consumption lives in 6A36 (main 7FA): bit2 set → 6AB8 5D4 countdown
      (decrement written via the 5D6 wrap); at 0 with bit0 set → 6B38 tail-calls
      506A→5076: 0252=0254, 0244&=FF, 0254=0244, then 5162/70B4/7040/5AEA/55CE.
      s59's "head work only via staged stub" model wrong again — 5076 is
      guest-driven once the countdown runs.
    * s60 assist load rules (284&~5 every frame + 5D4≥0F hold + 5D6=1 hold) froze
      exactly that countdown. s61 releases all three during the committed load →
      0254=34 @1846 (pc 005096), 1506=180 @1847, mode-C demo play @1852+, demo end
      ~2268 (web 2030; demo length rides the emulated pad-history counter).
    * US 5A3E polarity INVERTED vs the EU-derived decode: Start held (5A4A bne) →
      5A96; the 0244=1 commit (write @5AAC) needs Start held AND 284 bit2 CLEAR;
      bit2 set detours to 5A4E (2B4==FFFF → 5AB8 0244=[0A62], else mirror). The
      s60 post_title bit2 supply starved it. s61 post_title emulates the idle
      service (284 &= ~0xF; web post-demo 284=0) → Start@2450 (s61-startlate.input)
      commits @2452; guest 5076 stages 0254=1/1506=180 @2484 (web 2480).
    * Regression s61m: menu climb 025E 4→6→8 and confirm 0244=2 @1250 unchanged.
    * Tooling truths: the US build compiles
      native/build/generated/boogerman_us/boogerman_us_partNN.c (profile-prefixed,
      rdb-instrumented, staged from the ROM at build time); tools/manual-gen (EU)
      and native/generated are reference copies — edits there never reach the
      exe. 5A3E is interpreter-only in the US build; INSN_TL's fixed watch list
      only sees emitted code. Above 4E64 the US/EU shift makes EU-generated
      labels ≠ US PCs — verify against US ROM dumps before trusting EU decodes.
    * => Next: s62 gameplay validation past level load; M3 sound RE to retire assists.
  - **Session 62 (2026-11-27): gameplay validation. Native reaches mode-10 (menu
    route) and Start-commit + level staging (Start route), but the level WORLD
    never loads: the spawn-param deposit copies a zeroed source, so obj0 respawns
    as camera (5418) instead of the level controller (5452). Web deposits
    b4/91/2e and runs a live level. Root = the sound-ack-gated level-header
    stager (s58 C8-CA family) never fills the copy source natively (M3).**
    * Routes: web's 5968 menu/Start dispatcher is UNREACHABLE stock — it needs
      2BA==0 AND A65 bit0, which never coincide (pre-demo A65=0, post-demo
      2BA=1; gate snapshots @1800 [f 0 0 0] vs @2399 [f 3 1 0]). Web playability
      is via Start→5A3E (2BA=1). Native menu2 works only because TITLE_ASSIST
      forces the gates. ⇒ the Start route is the correct cross-port entry.
    * US 5968 decoded verbatim: 5D4==F → A65 bit0 → 2BA==0 → 284&9==0 → 050C&80
      (Start edge) → 6F82 + mode-C/5D4=8; A→6060; confirms s56 polarities.
    * Start route phase-matched: native commit 0244=1 @2452, 5076 staging
      0254=1/1506=180 @2484 (web 2480). Then BOTH teardown objects (~2502/2508).
      Web obj0 → 5452→54C0→54EE→5532→5698/56D6/571C (level controller; ASCII
      video @3000 = live level scene). Native obj0 → 5418/541C then 5484/548A
      camera loop; PNG @2900 = TITLE screen. Scroll accums 0690/0A90 never
      seeded natively (menu route too).
    * ROOT: spawn params. Web @2480 writes 0A58=b4/0A5A=91/0A5C=2e (type 2E =
      level controller). Native @2484 the 143C byte-copy loop (move.b (a0)+,d1;
      move.b d1,(a1)+/(a1); dbra) writes 0A58/5A/5C=0 — the source buffer is
      zeroed because the level-header decompress/stager (sound-ack gated, s58
      intro-stager/C8-CA) never ran. Spawn template ROM[3848+d3*4] then picks
      camera (5418) not level (5452). 027E/0280=2d/10 match both ports.
    * Tooling: ram-shot.html gained a coarse 40x28 luminance VID map (dump-dom
      can "see" the screen) + object-cont (1A14/1A6A/1AC2/1B1A, stride 58) and
      spawn-param (A58/A5A/A5C/27E/280) wt addrs; native PNG capture confirms
      screen state. tools/s62-startgame.input / s62-gameplay.input added.
    * => Next: s63 find the 143C copy source buffer + its writer (jsr callers of
      142C), then fix the sound ack (M3) or env-gated assist-seed the header so
      obj0=5452 and the level loads; validate scroll/player vs web.
  - **Session 63 (2026-11-27): level-load RE. CORRECTS s62: the 142C/13E8 LZ
    decompressor and the 0A50 header deposit are CORRECT natively; s62's
    "zeroed source" was a measurement artifact (read the even/zero high bytes).
    Also discovered web oracle = EU ROM while native = US, so raw obj-cont
    address comparison (5452 vs 5418) is region-shifted and unreliable. The
    level-world failure is DOWNSTREAM of the header (first level stager skips on
    0A7E=FF). An assist post_title discrimination edit regressed the Start commit
    and was reverted (net engine change zero).**
    * Decode: 13E8 = RAM LZ decompressor (window $FF3422, falls into 142C body);
      13C6 = wrapper (a0=dest from caller, d0=src asset idx via table $9CBC4,
      size=next-cur); 1496 = VDP-dest variant. 515A (US; EU 5162) = level stager:
      d0=0244, word table $6EFE[d0]→asset idx, dest $FF0A50, bsr 13C6. Level 1 =
      asset 5 = ROM $9F010 (size ~0x86). Literal path 143C writes (a2)+ window AND
      (a1)+ dest (single bytes, NOT duplicated); backref path 1454+.
    * Proof decompressor correct: s63a OBJ-TL byte writes @2484 = 0A59=B4,0A5B=91,
      0A5D=2E (spawn params live in ODD bytes); web wt words a58=b4/a5a=91/a5c=2e
      are the same bytes read as words (00B4/0091/002E). s62 read a=FF0A58 v=0 (the
      zero high byte) and wrongly concluded "zeroed source". Header matches web.
    * Region: web/rom/README.md confirms web embeds the EU dump (3,145,728 B,
      checksum DFAE); native runs US. US spawn table $3848 idx2E=5418 (camera);
      EU level ctrl 5452 has no US immediate/table twin ⇒ cross-port cont compare
      invalid. Need a US web oracle for apples-to-apples level validation.
    * Downstream gate: s63c @2484 header writes 0A7E=FF/0A80=FF; 5268 does
      move.w 0A7E,d0; bmi ⇒ first level tilemap stager SKIPS natively. Whether US
      backref output is wrong (codegen) or EU/US headers differ is undecidable
      without the US oracle. 0206 (dest end) logged 00FF, also suspect.
    * Assist experiment: restricting s60_post_title to 0254==0x22 regressed the
      Start commit (s63b no 0244/0254 writes) ⇒ reverted. Measured: 0254=34 through
      post-demo title, =1 at level; 1506=0x160 at title, =0x180 during load/level,
      so the EXISTING post_title (1506==0x160) already disables title-emulation in
      the level — it is NOT the revert-to-title cause.
    * Tooling: tools/s63-scan.ps1 (jsr/jmp/bsr.w/bsr.s/bra/lea/movea caller scan;
      PS5.1 [int16] cast throws >32767, use manual sign-extend). ram-shot wt addrs
      += 0A50/52/54/56/5E. OBJ-TL addresses are full 24-bit (a=FF0A58), grep accordingly.
    * => Next: s64 build a US web oracle; compare full 134-byte header + 0A7E; if
      native diverges, fix backref codegen; else trace the level-controller spawn gate.
  - **Session 64 (2026-11-27): US web oracle + level-load RESOLVED. The native
    port LOADS and PLAYS the level world. Full 134-byte level header is
    byte-identical to the region-matched US oracle (0 diffs); 0A7E=FFFF is
    authentic US data (web identical — the 5268 bmi skip happens on web too);
    the controller state machine 541C→5484/548A→54B8→54FC tracks web with a
    constant ~350-frame offset; s62's "camera loop / level never loads" was a
    capture-timing artifact. Right/A probes @3950+ scroll (0698 AB→34A), jump,
    and score 000350 natively.**
    * Oracle: web/rom/boogerman_us.gen.js (gitignored) via embed-assets.ps1 US
      block; ram-shot.html ?rom=us (document.write rom loader) + wtFull=1 (whole
      0A50..0AD6) + 5D4/5D6/686/688 watches. web-US phases: demo commit @1825,
      post-demo title @2057/2065, Start@2100 → 0244=1, 0254=1/1506=180 @2131.
    * s64-headerdiff.ps1 (web WT words vs native OBJ-TL byte/word assembly):
      0 diffs across all 67 words incl. the backref tail 0A60..0AD6 ⇒ the 1454+
      backref codegen is CORRECT; no engine fix needed.
    * Service decode US 6A00-6B00: 284 bit1 + 5D4==F → 5B4 byte countdown (6A28);
      bit2 path increments (6AA4); 5D6 wrap → 5D4 phase. Native runs it
      identically (5B4 D→0 @2545 = web 2196 + 349).
    * Controller: obj base a4=1A0E; +4C=1A5A yield timer, +48=1A56 resume,
      1A14 cont (31E0 = move.l (sp)+,(4,a4) pops a return address; mid-block
      re-entry points 548A/54B2 are intentional ori.b-skip tricks). The 54B8
      wait releases on 1A5A=FFFF (49AA) at +148 frames on BOTH ports; the 157xx
      family is the level entity spawn loop (types 1EF..214 via 4B8C).
    * Gameplay: s64-play.input (Start@2450; RIGHT@3950, RIGHT+A@4250) → PNG @4400
      shows scrolled forest, jump pose, score 000350; web-US counterpart
      (3@2100:40,7@2600:300,8@2900:40) VID scrolls likewise. s62's probes
      @2600-3200 landed pre-level natively — that was the whole "failure".
    * Remaining: native level pipeline runs ~350-1000 frames behind web (offset
      grows after 54B8); quantify/align in s65; boot assists still active (M3).
    * Tooling: s64-webdump.ps1 (MODES/GATES/WT/VID parser), s64-abscan.ps1
      (abs-operand scan), s64-headerdiff.ps1. PS gotcha: a typed [string]$Web
      param constrains the case-insensitive $web local (rename locals).
      run-us-misses logs live in captures-us/<Tag>/err.log (per-tag dir).
    * => Next: s65 phase/timing alignment + transitions/death/pause validation;
      M3 sound RE to retire assists.
  - **Session 65 (2026-11-27): Gameplay-fidelity diagnosis. Native PLAYS the
    level on the new build (s65l PNG @4500: jump pose, enemy, score 000400).
    The "growing offset" splits into (1) an intermittent whole-guest FREEZE
    and (2) a 3.3x spawn-window stretch; the pre-spawn pipeline is
    phase-aligned once the boot offset is removed.**
    * Freeze root cause: the 68K music driver takes the Z80 bus (98A30:
      move.b #0,(A11100)) and enters the service tick (981FC) which never
      completes under the cooperative 68K/Z80 interleave — a host-timing
      race. Live-catch evidence: SR=0x2009 (IPL 0), rdb func=098A30,
      crash_trail ends 98B52 cmd-copy -> 98A30 -> 983CE -> 981FA; no
      read-side parks, Z80 not halted. NOT recomp codegen (interp freezes
      too), NOT pacing mode (accurate freezes too).
    * Trace-volume coupling: the wide OBJ-TL HI=2400 tap (~600k fprintf
      lines during boot) slows the host enough to hit the race
      near-deterministically (s65a/b/c/g/h/j all froze ~f1000-1600); the
      narrow OBJ_TL_ADDRS tap is stable (s65k/s65l clean; s64d was clean).
      Measurement rule: use ADDRS lists, not wide HI, for gameplay runs.
    * Engine hardening (submodule 596b892, carried in segagenesisrecomp.diff):
      sound_ack_note() acks A00FE4/A00FAC + 0524/0548/054C the instant the
      guest sets them (SPLASH_ASSIST-gated). Necessary but not sufficient
      alone; the interleave starvation fix itself is s66/M3 engine work.
    * Phase table (s65k vs web-US, input-relative): commit +58 both ports;
      548A/54B8/54FC at +349 constant (= the boot/input offset); spawn
      window 54FC->5572 native 800f vs web 54FC->5662 240f ⇒ the growth is
      an object-cadence gap in the spawn loop. Main loop + V-int mode
      writes are FULL pace on both (0516 = 2 writes/frame); the half-pace
      seen in s64 was object-level only.
    * Boot pace is host-load dependent: identical pre-input configs
      diverged ~275f before the first press (s65k vs s65l) ⇒ fixed-frame
      transition probes cannot land reliably; s66 must phase-lock inputs
      to observed RAM phases. Web oracle also shows run-to-run input-phase
      variance under headless virtual time (webE vs web2/web3).
    * Pause/death/level-exit/damage/scroll-limit validation deferred to s66
      with phase-locked probes (s65l's pause press landed pre-control).
    * Tooling: s65-phases.ps1 (cont/timer/scroll/spawn parser for OBJ-TL and
      web WT), s65-probe.ps1 (live freeze catch + rdb func tally),
      run-us-misses -Accurate; ram-shot watches += 19DE/698/69A.
    * => Next: s66 engine interleave fix + spawn cadence + phase-locked
      transition validation; M3 sound RE to retire assists.
  - **Session 66 (2026-11-27): s65's two headline gaps DISPROVEN as measurement
    artifacts. Native is playable end-to-end on the wide tap; no engine freeze
    exists. The real remaining work is phase-matched transition validation.**
    * Freeze disproven: a wide OBJ-TL HI=2400 run to --exit-at-frame 4600
      completes exit=0 with a live level PNG (s66wide). The s65 "freeze" was the
      probe's criterion (crash_trail lacks V-int 004DF0) false-positiving during
      the boot sound-upload: the last 64 blocks are all 98xxx while frames still
      advance. Live catch with the new sched_state cmd showed frame_count
      244->285 over 1.5s, cycle_accum climbing, in_vblank_service=0,
      irq_cycle_debt=0, yield_site=BUDGET — a healthy guest, not a park. The
      probe then killed a healthy run. s65's "host-timing race" was the wide tap
      slowing the host so the 4s poll landed inside the sound-upload window.
    * Engine debug addition (carried in segagenesisrecomp.diff): glue_sched_debug
      + TCP `sched_state` (yield site, in_vblank_service, irq_cycle_debt,
      interleave_active, spin/z80poll streaks, watchdog) — read-only snapshot.
    * Probe corrected: s66-probe.ps1 now uses a vblank_info frame_count delta
      over 1.5s as the liveness test (trail-lacks-V-int alone is NOT a freeze).
    * Spawn-cadence re-measure (s66narrow, clean ADDRS tap, new build): Start
      commits 5418@2509; first spawn span 54FC@2710 -> 5662@2952 = 242f, matching
      web-US 54FC@2360 -> 5662@2600 = 240f. The s65 "800f vs 240f" compared
      native's SECOND 54FC span (2986 -> 5572@3786) against web's FIRST
      (->5662): mismatched transitions, not a 3.3x cadence gap. The second-span
      difference needs a phase-matched re-compare (web capture ends in steady
      54FC), not an engine fix.
    * Boot-pace host-load variance (~275f pre-input) remains real but is a
      harness/pacing property, not a fidelity bug; phase-locked probes remove it.
    * => Next: s67 phase-matched transition validation (pause, death, level exit,
      collision damage, camera scroll limits) vs web-US using corrected probes;
      re-compare the second spawn span phase-matched; M3 sound RE to retire assists.
  - **Session 67 (2026-11-27): Phase-locked input scripting + pause validation.
    Pause freezes gameplay RAM natively; first spawn span aligns 242f web==native.
    Camera/health vars and reliable auto-entry deferred to s68.**
    * Phase-locked inputs work with NO engine change: input_script already has
      WAIT_RAM8/16, PRESS/HOLD/RELEASE, DUMP_RAM, SCREENSHOT. Scripts anchor to RAM
      phases (hold-Start-until-WAIT_RAM16 0244=1) instead of fixed frames, removing
      boot-pace variance (pause run committed 0244=1 @2755, pc=005AAC).
    * Pause VALIDATED native: across a 120f pause the object table ($FF0100-01FF)
      and camera/HUD ($FF0600-06FF) are byte-identical (0 word diffs); only the
      level-controller yield timer ($FF1Axx) and audio/service counters
      (0286/0288/052C/052E/0544/0560/0562/056C/056E/0578) keep ticking — music
      continues during pause, gameplay halted. Web-US shows the same signature
      (06D0 anim ticker + 0632 intro countdown freeze, 0516 V-int continues).
    * Spawn span phase-matched: native first 54FC@2710->5662@2952 = 242f equals
      web-US W6 first 54FC@3559->5662@3801 = 242f. The s65/s66 "second span 800f"
      gap is an INPUT-PHASE mismatch (the pause press lands INSIDE native's 2nd
      span but BEFORE web's 2nd span), not an engine cadence bug; a phase-aligned
      input schedule is needed to compare it (s68).
    * Measurement traps corrected: (a) a gameplay script MUST include a title->game
      entry press or it stalls at title and the observed "gameplay" is the attract
      demo; (b) 0698 and 06A0 are NOT the gameplay camera (06A0/06A2 track the
      attract demo; 064E-0674 are background/water anim oscillators); (c) 5D4=0F is
      a boot stage (~f101), not title-ready, and A65=3 is post-commit, so neither
      anchors the entry.
    * Entry reliability finding: hold-Start-until-commit committed in the pause run
      but NOT in the scroll run (boot-variance / pressed-edge interaction) — auto-
      entry must be made deterministic (s68).
    * Tooling: s67-web.ps1 (US dump/shot + wtx custom watches), s67-diffram.ps1
      (full-RAM word diff), s67-scroll.ps1 (per-addr timelines/clamps), s67-native.ps1
      + s67-{pause,scroll,walk}.input; ram-dump.html gained ?rom=us&script=,
      ram-shot.html gained ?wtx=. RAM_MAP.md gained the s67 gameplay-phase table.
    * => Next: s68 deterministic auto-entry + gameplay camera/health/lives discovery,
      then scroll-limit / damage / death / level-exit validation and a phase-aligned
      second-span compare; M3 sound RE to retire assists.
  - **Session 68 (2026-11-27): ROOT CAUSE of the s67 hybrid = TITLE_ASSIST itself.
    With it OFF, phase-anchored entry is deterministic (commits f2074 twice) and the
    level PLAYS; gameplay camera + player pos identified; scroll validated both
    directions. s67's "pause" was title-idle; a held START quits to title.**
    * s67 native runs (pause/scroll) had TITLE_ASSIST=1. Its per-V-int 284/A65/2BA
      writes keep the 15xx title supervisor alive AFTER the 5AAC commit, so the
      guest ran the level controller (5418@2811, 0254=1/1506=180) while the display
      stayed title and the gameplay camera/anim stayed dead (06D0=0) — a hybrid.
      The s67 "pause freeze" (01xx/06xx identical + audio ticking) was this hybrid /
      title-idle, NOT a gameplay pause; the "0698/06A0 not camera" dismissal was a
      hybrid artifact.
    * Clean config (TITLE_ASSIST OFF, keep BOOT/SPLASH assist + lockstep): entry =
      WAIT_RAM16 0244=34 → WAIT_RAM16 1506=160 → WAIT 30 → HOLD START →
      WAIT_RAM16 0244=1 → RELEASE. Commits at exactly f2074 (s68d == s68e). The
      guest's own service opens the title natively; TITLE_ASSIST is unnecessary and
      harmful for gameplay. (s68b 8f-PRESS gave the edge but the hold-from-boot s67
      recipe lacked a title-time edge; the assist, not the edge, was the real blocker.)
    * Gameplay camera X = 0698=06A0=06AC (idle 02E3→right 05AE, reverses on LEFT);
      Y = 069A=06A2=06AE; tertiary 069C=06A4=06B0. Player world pos 0222/0224 (X),
      0226/0228 (Y); screen/vel 0216/0218. right.png/left.png show scrolled forest.
    * START semantics: HELD Start (40f) in-level quits to title (s68f/g pause1.png =
      title); the "pause freeze set" is the title-idle set. True gameplay pause
      trigger/timing NOT yet validated → s69. Intro countdown 0632; START during
      intro aborts to title.
    * Tooling: s68-native.ps1 (-NoTitleAssist/-NoSplashAssist, -CaptureFrom/-Every),
      s68-diffbin.ps1 (native 64KB bin word reader/differ, big-endian per word),
      s68-{entry,walk,pause}.input. RAM_MAP s67 table superseded + s68 table added.
    * => Next: s69 true pause trigger + health/lives + damage/death/level-exit and
      scroll-limit validation vs web-US (clean config); phase-aligned second-span
      compare; M3 sound RE to retire remaining assists.
  - **Session 69 (2026-11-27): s68's "deterministic entry / gameplay" was a FALSE
    COMMIT (released START before staging). Corrected entry + mode map established;
    the intro→play handoff and pause live in interp-only code → s70 disassembly.**
    * s68/s69a-h entry released START at commit+2 (before the +30f staging), so the
      guest never handed off; the "gameplay" camera/scroll seen in s68d/e was the
      attract demo / limbo, not a committed level. CORRECTED entry: WAIT 300 after
      post-demo title, HOLD START until WAIT_RAM16 0254=1 (staging at commit+30),
      then RELEASE. Verified native commit f2345 / staging f2375 (s69i).
    * Mode map (0244, mirrored 0254): 0=boot, 1=load/intro, 3=gameplay, 34/35=attract
      demos. 1506=160 title V-int / 180 level V-int. 0632=intro countdown (title stays
      on screen during it). 0516=4/8 game loop. Mode 3 with 0516=4 but frozen
      06D0/0222/0632 = PAUSED gameplay (reached only by the multi-press mash).
    * No-input after a true commit aborts to demo at ~staging+1100 (web f3589 ==
      native s69m). START tap/hold during intro = abort to title. Single B/C/A/UP/
      DOWN/RIGHT/LEFT taps or holds at +300/+600/+911/+1000 do NOT confirm play; only
      the cumulative mash (RIGHT,UP,B,DOWN,…) reached mode 3. Confirm is therefore a
      multi-press / interp state machine, not a single button.
    * 068C/068E are camera scratch (written from 06BC−0698 in the scroll routine,
      cleared by init 000AD2), NOT health/hearts. Discard as health candidates.
    * Tooling: s69-native.ps1 (clean default, -TitleAssist to repro), s69-web.ps1
      (web-US full-RAM → native-order bin), s69-{pause,confirm,title,death}-*.input.
    * => Next: s70 disassemble the interp intro/pause state machine (01562E caller,
      0632/0244 writers) to find the minimal play-confirm + pause trigger; then
      health/lives, damage/death/level-exit/scroll-limit validation vs web-US.
  - **Session 70 (2026-11-27): built a minimal 68k disassembler over the US ROM and
    decoded the attract/title state machines + all mode writers. CORRECTS s69: 0632 is
    the TITLE attract timer (not an intro countdown) and 06D0 ticks at title idle. The
    post-Start "intro" is a limbo that aborts to demo; mode-3 is written only by the
    attract coroutine (15606), gated by obj0+10/+22/0254. Minimal play-confirm NOT yet
    isolated (blind mash bisect failed) → s71 live obj0 trace.**
    * Tooling: tools/s70-disasm.html + s70-disasm.ps1 (headless-Chrome 68k disassembler
      over web/rom/boogerman_us.gen.js; -Scan finds MOVE.W #imm,(addr) writers; else
      disassembles [start,end)). tools/s70-wt.ps1 parses ram-shot WT timelines.
      Decoder covers MOVE/MOVEA/MOVEM/LEA/PEA/imm-ops/bit-ops/shifts/branches/DBcc/Scc/
      JMP/JSR/LINK/etc; unknown → dc.w. Extension-word order src-before-dst verified.
    * Mode writers (US, -Scan): 0244=3 @015606, =2 @01561A/00612A/00A2CC/018B3E,
      =34 @01562E/008268, =1 @005AAC/014C6E/015E46, =0 @000762/005C8E/09BC22,
      =37 @005C6E, =10 @01AE4A. 1506=160 @0064B2 / =90 @0064BE. 0632/06D0 have NO
      immediate-absolute writers (register/other forms).
    * Attract coroutine (obj0=A4=FF1A0E), 154C4-15730: +10=phase, +16=attract countdown
      (init 190), +22=progress counter, +8=flags, +4C=yield, +48=resume. Phase-1 (154EA)
      polls pad B(bit1)→1554A, Right(bit3)/Left(bit2)→15642 (intro stager), +8 bit11
      (demo-done). +16 expiry→+10=1. Phase-2 (15560): +10==1→1562E demo(34); else
      0254==0 & +22<200 (or 0254!=0 & +22<C0)→155AC clears player vars + 15606 mode 3;
      +22>=threshold→1561A mode 2. So mode-3 needs the coroutine in phase-2 with +10!=1.
    * Title dispatcher 5960 (US): needs 05D4==0F AND A65 bit0 AND 2BA==0 AND 284&9==0,
      then Start-edge→6F82/menu; A-edge→6060. On US web 25E/5D4/A65/2BA never coincide
      stock ⇒ START/A/B at first title do NOTHING (s70wS1/A1/B1 identical to no-input).
    * Start-commit 5A36: needs 2BA!=0, Start-held(0502&80), 284&4==0 → ORI#5,0284 +
      0244=1 @5AAC. (2BA must be set by the pad-history mirror; wt under-reported it.)
    * CORRECTED semantics: 0632 cycles 5f→0→60 at TITLE idle (attract timer), 06D0 ticks
      there too; both keep cycling post-Start (limbo) until abort→demo @~staging+1100.
      So s69's "intro countdown ~950f" was the title timer continuing, not a level intro.
    * Web empirical: first-title START/A/B no-op; post-demo RIGHT/LEFT no-op; first-attract
      B-hold no-op, RIGHT-hold only restarts attract; post-Start+RIGHT-hold(300f) aborts to
      demo (s70wSR 244=34@3625); reconstructed 8-press mash did NOT reach 3 (s69 mash is
      timing-sensitive; exact frames not persisted).
    * => Next: s71 recover exact s69 mash + live-trace obj0+10/+22/0254 (and 2BA) to find
      the minimal mode-3 branch condition; mirror on native; then pause trigger; then
      health/lives + damage/death/level-exit/scroll-limit vs web-US.
  - **Session 71 (2026-11-27): ISOLATED the minimal play-confirm (START + one DOWN tap)
    and mirrored it natively (deterministic mode-3 @2854 via 015606). Recovered the exact
    s69 mash from s69wmash2 WT and discovered the pre-staging "mash" was the game's own
    attract PLAYBACK (pad-history mirror), not user input. CORRECTED pad bits (&2=DOWN,
    MD B=0x10) and START-in-level semantics (= level RESTART, not pause/quit). No pause
    button exists among START/B/C/A/Mode/UP/DOWN; s69 "PAUSED" was the limbo/intro.**
    * Pad-history playback: while 2BA=1 (post-demo title f2065-2523) the 5A36 mirror
      overwrites 0502 from the FFFE00 history ring each frame; only a held START passes
      live (5A4A bne skips the mirror). So the s69/s70 pre-staging RIGHT/B/DOWN/C pattern
      is guest-generated attract playback, identical across runs — user taps there are
      invisible. This is why single-button pre-staging probes "did nothing".
    * CORRECTED s70 pad labels: 0502&2 = DOWN (not B); MD B=0x10, C=0x20, A=0x40,
      Start=0x80, Up=1, Left=4, Right=8 (web input.js LR.B=0→MD B=0x10). Phase-1 1550C
      &2→1554A is the DOWN join path; 15642 Right/Left = intro stager.
    * Minimal confirm (web s71wK): START hold @2450 (commit 2451/staging 2484) + DOWN tap
      @2900 (staging+416) → 0244=3 @2977, 0254=3 @3007, obj0 reinit level-ctrl @3053.
      RIGHT/UP/B post-staging alone do NOT confirm (s71wD/E/F); the s69 "multi-press mash"
      was playback + this one DOWN. DOWN window is late-staging (+416 ok, +116 fails
      s71wN); web has run-variance, native +400 is reliable.
    * Native mirror (s71n1, s71-entry.input): WAIT 0244=34→1506=160→WAIT300→HOLD START→
      WAIT 0254=1→RELEASE→WAIT400→PRESS DOWN4→WAIT 0244=3. Commit 2345/staging 2375/
      mode-3 2854 (pc 015606). Deterministic. Level opens with a LONG lab story-crawl
      cutscene (s71n2/n3/n4) before the swamp field; field+scroll validated s64/s68.
    * START in TRUE gameplay = level RESTART: tap or hold re-commits 0244=1 (web @3400)
      → re-staging 254=1/1506=180 @3432 → frozen limbo (needs DOWN again). NOT pause and
      NOT quit-to-title (s68 "hold quits" was the false-commit limbo). s71wP/R1.
    * Pause probe: B/C/A/Mode/UP/DOWN taps and START tap/hold in-level produce no
      mode-3+frozen-world pause; s69 "PAUSED (mode3+0516=4+frozen)" reinterpreted as the
      post-restart limbo / intro wait. True pause trigger absent or non-button (s72).
    * Tooling: tools/s71-wt.ps1 (windowed WT parser, -From/-To), s71-{entry,play,field,
      skip}.input. s70-wt.ps1 reused for full timelines.
    * => Next: s72 get past the lab cutscene reliably (find skip trigger or auto-advance),
      then health/lives vars + damage/death/level-exit/scroll-limit validation vs web-US
      in the true field; phase-aligned second-54FC-span compare; M3 sound RE.
  - **Session 72 (2026-11-27): s71 mode-3 "play" CORRECTED — 0244=3 is the lab
    story-crawl (fixed ~3200f, auto-advance, NO button skip); 0244=10 ($01AE4A) is the
    TRUE gameplay mode (level card "FLATULENT SWAMPS LEVEL 1" then the swamp field).
    Native field reached deterministically; but native HORIZONTAL input is dead in the
    field (TH=1 pad phase), the remaining playability blocker.**
    * Mode map corrected: 3=crawl, 10=field. Native timeline (s72n2): demo 1815 (01562E)
      / START commit 2345 (005AAC) / mode3 2854 (015606) / mode10 6056 (01AE4A); crawl
      3202f ≈ web 3207 (web mode3 2977 → mode10 6184). Crawl auto-advances; B/C/A taps
      mid-crawl do NOT skip (web s72wB/C/D all 6184). s72-field.input reaches the field.
    * Crawl coroutine $01AE16-01AE4A: +38 countdown, pad poll 01AE70 (only buttons
      >=0x0F call 6F82; directions ignored), +4C yield expiry → 01AE4A mode10 + 0284|=5.
    * True-field vars confirmed vs web-US idle→RIGHT diff (s72wE/F): camera X
      0698=06A0=06AC (0→0527), player X 0222/0224 (0→0517/0677), screen 0216. The s68
      vars ARE valid in the field; they read 0 during the crawl / idle-at-left edge.
    * s72 "direction-input BLOCKER" SUPERSEDED by s73: it was a SCRIPT-SYNTAX error
      (HOLD takes no duration; "HOLD RIGHT 800" ignored the 800), NOT an engine bug.
    * Tooling: s72-web.ps1 (budget-param ram-shot; s69-web's fixed 60s budget starves
      >~3600f), s72-field.input, s72-right.input, s72-interp.ps1.
  - **Session 73 (2026-11-27): s72 blocker RESOLVED as input-script syntax — native
    horizontal play VALIDATED byte-identical to web-US. The native port IS playable
    (scroll + jump); health/lives + damage/death/level-exit need hazard targeting (s74).**
    * Root cause: input_script HOLD takes NO duration (holds until RELEASE); PRESS btn N
      is the timed form. s72's "HOLD RIGHT 800" set the mask but advanced 0 frames, so
      DUMP/EXIT fired next frame and RIGHT never held. IO trace (env-gated, added then
      reverted) proved pad/TH model correct (START TH=0 ret=13, DOWN ret=31); pad=0008
      simply never asserted because the hold span was 0.
    * Corrected s72-right.input (HOLD RIGHT + WAIT 800 + RELEASE): native 0502=8 during
      hold, player X 0222/0224=0517/0677, camera 0698=0527 — EXACTLY web-US (s72wF).
      s73n2 r.png shows scrolled field. Native scroll/jump fidelity confirmed.
    * Scroll behavior: continuous RIGHT stops at the first pit (player X stays 0517);
      crossing requires jumps. RIGHT + repeated PRESS A hops platforms (s73n4) but did
      not die (lives stay x2) ⇒ health/lives not isolated yet.
    * Deferred to s74: health/lives vars, damage/death/level-exit/scroll-limit vs web-US
      (target hazards / force pit death), second-54FC phase compare, pause.
    * Tooling: s73-damage.input, s73-death.input, s73-webdump.ps1 (budget-param ram-dump).
      NO engine change (IO trace reverted); gitlinks stay 9907e77f40/6f705f2.
    * => Next: s74 health/lives + damage/death/level-exit/scroll-limit vs web-US with
      hazard targeting; second-54FC phase compare; pause; then M3 sound RE.
  - **Session 74 (2026-11-27): gameplay-validation boundaries mapped. Native
    input/scroll/jump confirmed (s73); progression past the first screen is
    platforming-gated, and fall-out-of-bounds is a reposition (no life loss).
    health/lives + death/level-exit/scroll-limit need dedicated RE or a solved input
    route (s75); pause = no button pause (s71).**
    * Progression: continuous RIGHT stops at first pit (X=0517); RIGHT + periodic A
      hops (s74-exit.input, 20 hops) do NOT cross — player blocks at the first pit/wall
      (0222/0698 stay 0517/0527). Crossing needs precise platforming, not blind scripts.
    * Forced death attempt: WRITE_RAM16 player Y (0226/0228) below field (s74-kill.input)
      respawns player at start (0228→0148) WITHOUT lives decrement (stay x2) ⇒
      out-of-bounds Y is a reposition, not a death. Player world Y = 0226/0228 confirmed.
    * Enemy-contact damage (s74-hit.input) and pit-jump (s74-death.input) did not
      converge blind ⇒ health/lives vars still not isolated.
    * Pause: no button pause (s71 probes); restated, not a button.
    * second-54FC phase compare deferred (needs PC trace in mode-10) → s75.
    * Tooling: s74-{death,hit,exit,kill}.input. NO engine change; gitlinks stay
      9907e77f40/6f705f2.
    * => Next: s75 RE the death/respawn + HUD routines to pin health/lives addresses (or
      solve a rightward input route), then damage/death/level-exit/scroll-limit vs
      web-US + second-54FC; M3 sound RE.
  - **Session 75 (2026-11-27): health/lives PINNED via HUD + BCD/death RE; native
    object-logic divergence discovered (FF0100-01FF empty vs web live) = root-cause
    lead for damage never converging; death requires the interp-only damage routine.**
    * HUD RE: func_00644C draws lives (022E) + score-mid (0232) BCD digits via
      0066A6/A8 (nibble → tile $86A8); func_006546 renders bars from 023C/023E via ROM
      tables $666A/$6674; gate A65 bit0 clear && 0246!=0.
    * health = 023E (max 0x20): forced 0x10 → half bar, 0 → empty + weakened pose
      (s75n3 m1/k3 PNGs). 023C = twin meter (pickup $003640), not the visible bar.
      lives = 022E BCD ("x2"); score = 0230/32/34.
    * Raw-ROM abs-operand scan (generated-C grep + OBJ-TL see emitted code only)
      located interp-only routines: lives dec $0035A2 / inc $0035C4; score inc
      0035E4/3600/361C; health pickup 003640/003660 (+8 clamp 20); death handler
      $003680 (obj+30=1A3E state 2/3, 024A=FE, 05E2|=1). Object table $FF0AAA stride
      0xE slot=obj+0xC (+0 X screen, +2 Y, +4/6 size, +8 flags).
    * Health=0 alone NEVER dies (web-US keeps forced value; weakened pose only) ⇒
      death only via damage routine (interp-only; candidates $00F2xx/$0123xx) → s76.
    * DIVERGENCE: native FF0100-01FF active-logic table EMPTY vs web live (handler
      ptrs 8D2E/8AF8/83CE; 01B2=1A0E); native player coroutine 1A5A/1A62 out of phase;
      native health write restored-then-zeroed while web retains ⇒ native object
      system diverges (enemy logic absent ⇒ blind damage never converges). s76 root-cause.
    * Web oracle wr= write-schedule hook added (ram-shot/ram-dump; guest byte g at
      buffer g^1 — first attempt hit 023F, fixed). Phase-matched dumps s75wA/B.
    * Tooling: s75-{kill,half,meter,hit2}.input; -Wr on s72-web/s73-webdump. NO engine
      change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s76 root-cause native object-logic divergence (FF0100 allocator gate;
      raw-scan 00FF0100/01B2 refs), then damage/death/respawn + level-exit/scroll-limit
      vs web-US + second-54FC; M3 sound RE.
  - **Session 76 (2026-11-27): object-logic divergence LOCALIZED to the interp-only
    level-object SPAWN (upstream of dispatcher); gate hypotheses ruled out.**
    * Phase-aligned entry dumps (s76n1 e0-e3 vs s76w0 @6184): web mode-10 entry already
      has 22 objects (0180=0016) + handler/ctx entries; native 0180 stays 0 at +0/60/300/800.
      So the level-object spawn NEVER runs natively (not populated-then-cleared).
    * FF0100-01FF layout: (state,handler-ROM-ptr) pairs + long RAM ctx ptrs (FF1A0E player,
      FF220E/FF182E/FF2222 props) + 0180=count/0182; 01F6/01FA/01FE = system-coroutine resume
      PCs (web 0C3E/0BEC/07C2 vs nat 0C3E/48C4/079A at entry).
    * Dispatcher $000BEC gated by FF0A48-0A4E; at +800 0A48=0008 on BOTH yet web 0180=0013,
      nat 0 ⇒ dispatcher runs on both; native simply has NO objects ⇒ root cause is the
      SPAWN/allocator, NOT a dispatcher gate.
    * Ruled out: 0284 (nat =5 at entry decays 5→2→0 by +300; web =0; forcing 0 via
      s76-gate.input did NOT populate table). 0A48-0A4E equal at entry (0) and +800 (8).
    * Spawn is INTERP-ONLY: no emitted-C immediates for handlers 8D2E/8AF8/83CE/8674/81E4;
      no LEA/MOVEA.L #FF01xx base loads; OBJ-TL shows emitted boot writes to 0180/01B2 (=0)
      but never the field count/player-ctx. Raw-scan 00FF01xx = 224 hits (mostly data/HUD
      cursor bound FF01E0 @0072EC/007306 = text renderer, dead end).
    * Guest yield $004970: +4C countdown dec/scheduler-pass, +48 resume JMP; native resume
      chain diverged at boot ⇒ spawn coroutine never resumed. s77 = trace resume chain
      (01F6/01FA/01FE) boot→field + interpreter coverage to locate & promote the spawn block.
    * Tooling: s76-{entry,gate}.input; s76a/b/c-disasm; s76n1/n2, s76w0. NO engine change;
      gitlinks stay 9907e77f40/6f705f2.
    * => Next: s77 locate+promote interp-only level-spawn (trace coroutine resume chain),
      then damage/death/respawn + level-exit/scroll-limit vs web-US + second-54FC; M3 sound RE.
  - **Session 77 (2026-11-27): damage routine + object-create PINNED (interp-only); spawn
    still never invoked natively; no general interp-trace knob exists ⇒ s78 add one.**
    * JSR-target scan of object accessors: object create/position = $011104 (calls 350A X +
      3520 Y, JMP 3450); death-handler callers = $01090E (enemy handler) + $01CB7C.
    * APPLY-DAMAGE = $0037C0 (D0=amount, e.g. 0x50 at 010900); health-setter $003790 (D0=0xBF
      at 01112C). Both + 011104 + 010880 ABSENT from emitted C ⇒ interp-only (confirms s75).
    * Enemy handler 010880: obj+16 type 40/20/01 selects resume D358/D380; on hit calls
      37C0→6F82→3680(death)→3538(deactivate). Damage/death chain now fully mapped.
    * Level-load "idles 579C" = completed VDP-DMA-setup RTS (5784 loads regs BC/BD), NOT a
      wait gate ⇒ parked-coroutine hypothesis not a sound-ack wait at 579C.
    * NO general interpreter trace: GENESIS_CALL_TL/INSN_TL are fixed-watch lists, emitted-only
      (reverse_debug.c). Locating the interp-only spawn caller needs an env-gated interp block
      trace (engine .diff) or static RE of the level-object parser ⇒ s78.
    * Tooling: s77a/b/c/d-disasm. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s78 add env-gated interp block trace (or static RE level-object parser) to locate
      + promote the spawn; then damage/death via 0037C0 + level-exit/scroll-limit vs web-US +
      second-54FC; M3 sound RE.
  - **Session 78 (2026-11-27): s75/s76 "object-logic divergence" RETRACTED (FF0100-01FF is the
    68K stack, not a table); native port confirmed PLAYABLE (move/jump/score/death/respawn).**
    * $FF0100-01FF = supervisor stack: only A7 imm load is 00031C LEA $FF0200,A7. The s75/s76
      "handler ptrs / 0180 count / 01B2 player ctx / spawn never runs" were stack words. The
      real object table $FF0AAA + player ctx $FF1A0E are byte-identical web vs native at
      phase-aligned field entry ⇒ objects spawn and run natively.
    * s76 compare was also phase-mismatched (web 0244=3 crawl vs nat 10 field). Correct
      field-phase web dumps (s78w1/w2/w3) match native e0/e2/e3 on all gameplay vars; +300
      full diff = 207 words, all stack/sound/scroll/sub-frame phase.
    * B = JUMP (isolated s78n1; A/C/UP inert). s74 "can't cross first pit" used A — scripting
      error, not a port bug. With B jumps (s78-route) native shows the full loop: progress,
      score, death→fade→respawn, lives 022E 02→01. Interp damage 0037C0 executes (coverage).
    * s77 003680/0035A2 NOT on the observed death path (register-indirect dec; refine s79);
      00A234 = lives==0 game-over check. Native/web route outcome differs by ~128f entry
      phase (native died, web survived) — mechanics shared.
    * Engine fix (segagenesisrecomp.diff): --exec-coverage-out now dumps on script-EXIT (was
      silently ignored); 7676 interp PCs for the route. Usable interp-visibility knob.
    * Tooling: s78-{jump,route}.input; s78a/b-disasm; s78n1/n2/n3, s78w1-w4; -ExecCov on
      s69-native.ps1. Gitlinks stay 9907e77f40/6f705f2.
    * => Next: s79 pin the register-indirect lives-dec + death/respawn handler on the observed
      path; solve a full level route to the exit/scroll-limit vs web-US; then M3 sound RE.
  - **Session 79 (2026-11-27): death/respawn chain PINNED via write-tap writer PCs (no engine
    change); s75 lives inc/dec labels corrected; tighter jump cadence survives + crosses pit.**
    * Used existing tap GENESIS_OBJ_TL_ADDRS=22e,23e,24a,5e2,1a3e,244 on the s78 death route;
      interp writes go through m68k_write8/16/32 ⇒ real writer PCs. Lives DEC = $0035C4 (SBCD,
      store $0035DC) called by respawn-init $007FA6; lives INC = $0035A2 (s75 had them swapped).
    * Chain: enemy damage $00FA0A (SUBI.B #4,023E)→003790; player-hit handler $003744 (death
      branch $003780 obj+30=1, clear $003734); fade/respawn coroutine $00A0xx (00A062 024A=1,
      00A17E 024A=FFFF, →00A234 lives==0); respawn/reinit $007Fxx (007FA6 dec, 007FBC health=20,
      007FD8 state2). Confirms s77 003680/0035A2 NOT on the observed path.
    * Route (s79n2, B8/WAIT40): SURVIVES (lives2/health32), crosses first pit (cam 0698=0575),
      score increments; end reaches level-card boundary (0244=10,1506=232) = exit/restart
      transition, confirm vs web s80. s78 cadence B6/WAIT90 died on enemy contact ⇒ cadence is
      the survival lever. Full route to exit/scroll-limit + second-54FC still open.
    * Tooling: s79-{death,route}.input; s79a/b/c/d/e-disasm; s79n1/n2. NO engine change;
      gitlinks stay 9907e77f40/6f705f2.
    * => Next: s80 solve full route to exit/scroll-limit vs web-US + confirm end-card transition;
      phase-aligned second-54FC-span compare; then M3 sound RE.
  - **Session 80 (2026-11-27): end-card = death/respawn (NOT exit); forward block at cam 0575;
    full route still open.**
    * Long route (32 jumps B8/WAIT40, s80n1) dumps every 8: g2 alive cam0575/lives2 → g3 respawned
      cam0010/lives1 ⇒ the s79 "end card" is the respawn card (a life is lost; an exit would not
      decrement lives). Web-US same route (s80w1) shows card @8820 then life drop @8933 ⇒ same
      semantics, later phase. Closes the s79 exit/restart question.
    * 1506 = level-card timer: field-entry ramp D1→E8 via 0072CC, hold E8 via 0072D4, re-ramped on
      respawn. 024A fade flag set=1 by 00A062, cleared=FF by 005832. s80n1: 00A062@7137→005832@7596
      →0035DC(lives2→1)@7787 (reconfirms DEC store).
    * Forward block at player X~0565/cam0575 (enemy cluster past first pit): B8 dies, B12 stuck then
      dies (s80n3), A attack inert (s80n2). Cadence alone does not solve the level ⇒ s81.
    * Tooling: s80-{long,atk,jump12}.input; s80n1/n2/n3; s80w1. NO engine change; gitlinks stay
      9907e77f40/6f705f2.
    * => Next: s81 identify the 0575 obstacle / correct attack or jump-on-enemy (or derive a working
      route from web-US) to reach exit/scroll-limit; phase-aligned second-54FC; then M3 sound RE.
  - **Session 81 (2026-11-27): attack buttons RE'd (A=flick/C=burp/DOWN-air=fart boost); blocks 1-2
    solved; route to cam 0CAB; second-54FC span parity confirmed.**
    * Player action dispatcher = interp 0080AE-0092xx (ctx A4=FF1A0E). Idle 008156: A-edge→009EF2
      flick gated 023C>0 (ammo); C-edge→009806 burp charge gated 023E≥4; DOWN→008642; UP→00842E;
      A+B+C→0082AA. Walk 0089C6: A-edge→008F10 flick, no C. Jump: DOWN-air→009168/009180 fart
      boost (vel EF70); A-air→0091E4 flick. s80 "A inert" = A pressed mid-air (no A test there).
    * Block 1 (cam 0575) SOLVED: grounded flick (s81n3 ammo 20→1C, score 600, cam 062C; s81n5
      passes alive lives 2). Obstacle 2 = slope enemy ~065F (flick whiffs uphill): fart boost
      clears it (s81n6 cam 07AD). s81n9 (flick 3→boost) passes both: cam 0C78 @jump35 lives 1;
      dies at obstacle 3 ~0CAB ⇒ full route to exit open (s82). Stomp pinned 003744 (player
      above enemy ⇒ kill; else player death flag 0266=1).
    * Second-54FC span phase-aligned MATCH: native @6224 (mode10+168) bytes C7 C3 C3 03 C3 C0 C8
      00 = web @6354 (mode10+170) high bytes; writers 001440/001476. GOTCHA: OBJ_TL_HI default
      0x2212 filters taps >2212 — raise HI to tap 54FC.
    * Tooling: s81-{probe,atk2,long,stopC,boost,combo,burp,early}.input; s81n1-n9; s81w1;
      s81a-g-disasm. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s82 complete the route to exit/scroll-limit (per-obstacle stomp/flick scripting
      using 003744 stomp condition; obstacle 3 at ~0CAB); then M3 sound RE.
  - **Session 82 (2026-11-27): obstacle map + cam-locked probing method; thorn cluster is the
    true first blocker; death-fade locks input. Route to exit still open (s83).**
    * Cam-locked method: WAIT_RAM16 on cam 0698 (values on the 3-grid, cam steps 3/frame) makes
      each action fire at a stable WORLD position regardless of capture drift. Fixed-count
      cadences are NOT phase-stable: DUMP_RAM/SCREENSHOT consume guest frames, so the same
      script prefix lands at different cam across variants (s81n9 g4=0499 vs s82a m1=03D9).
    * Obstacle map (cam X): (1) THORN-BUSH cluster ~02AF-0350 (green+brown spikes, NOT a pit) —
      kills EVERY cadence at ~f7110 (deathflag 003778); single B8 jump and single boost both
      land in it (boost airtime ~85f covers ~0x100). (2) Slope WALL at 0527 (cannot walk up;
      cam freezes) with yellow slope enemy ~05A0-0780 — needs boost. (3) Bridge over water
      ~0C00-0CAB with red walker (obstacle 3, kills at 0C78). Max scroll reached 0CAB.
    * B=jump VERIFIED on flat (s82g: FF050C pulse→00903A flag 1A16=1→Y arc E8→AE→land). But once
      deathflag 0266=1 (death-fade) input is IGNORED and the corpse slides; cam-locked stages
      are consumed on respawn ⇒ route stalls at the wall. Fixed cadence survives respawn
      (keeps jumping). ⇒ cam-locked alone insufficient; must avoid the thorn contact outright.
    * Score BCD lives at 0237-0239 (written by 0037C0 add routine), NOT 0230-34. lives=0 respawn
      resets cam to 00D7 (level start; grinning tree = start decor), score cleared later.
    * Tooling: s82a-k.input; s82a/b/c/d/e/f/g/h/i/j/k captures. NO engine change; gitlinks stay
      9907e77f40/6f705f2.
    * => Next: s83 clear the thorn cluster (double-boost / stomp / flick-on-thorn test) then
      slope+bridge to exit/scroll-limit; then M3 sound RE.
  - **Session 83 (2026-11-27): WAIT_RAM16_GE opcode; thorns survivable run-through; hurt
    input-ignore windows + knockback break cam-locked world offset; slope staircase/gap map;
    RELEASE-after-landing safe block; route to exit still open (s84).**
    * ENGINE TOOLING: input_script.c gained OP_WAIT_RAM16_GE (>= wait) because cam equality
      waits stall: thorn-hurt knockback makes cam step +1/+2 (f7153-7185) and SKIP grid values
      (032F→0331). GE is monotonic-safe while running right. Rebuilt BoogermanRecomp_us;
      engine work carried in native/segagenesisrecomp.diff (regen base→worktree).
    * s82 "thorn cluster kills every cadence" REFINED: run-through costs ONE hurt (0266 pulse
      003778, cleared 2f later by 00A040), lives stay 02, health bar full; flick kills one bush
      (+50 score 0239). s82 deaths were accumulated jump-landings in the cluster, not run-through.
    * HURT ⇒ ~20-30f INPUT-IGNORE window (ammo 023C taps prove swallowed flicks/B8) AND knockback
      displaces player screen-x ⇒ cam-locked ≠ world-locked after hurt (s83d-m identical guest
      traces despite different post-boost ops). Ammo 023C taps (00F0AC dec) decode flick fires;
      score 0239 taps (0037F2) decode kills.
    * Slope = STAIRCASE: platform 1 top cam 0527-0580 (~80px step; plain hop apex ~40px cannot
      climb; single boost 04E0 lands ON top ~0560), then GAP cam 0580-0630 (walk/hop-short =
      fall death ~7761), platform 2 + enemy 2 ~065F-0680 (higher ground; horizontal flick whiffs).
      Landing contact/projectile hurt at 7337 ⇒ ignore window swallows the gap hop ⇒ fall.
    * Re-boost ALLOWED (vel 1A46=EF70 twice, s83f) but anim-gated ~+64f after boost1 ⇒ tight
      double-boost impossible; double-boost from ≤0480 hits wall side (cam freezes 0527).
    * SAFE BLOCK (s83n): boost 04E0 + WAIT110 + RELEASE ⇒ player ALIVE standing at gap edge
      057C, no death. Walk/release/hop cycles (s83o) execute fully (p1-p4+end dumps) but plain
      hop reach ~0x5A < gap 0x50+edge ⇒ lands IN gap ⇒ death. Gaps need BOOST per crossing.
    * Tooling: s83a-o.input; s83a-o captures. Gitlinks stay 9907e77f40/6f705f2.
    * => Next: s84 cycles with BOOST (B8/W6/DOWN6) per gap/step instead of plain hop (or stomp
      platform-1 enemy then walk); then bridge walker + exit/scroll-limit; then M3 sound RE.
  - **Session 84 (2026-11-27): slope staircase mapped (wall1 0527 / wall2 0587); s83 "safe block /
    gap" RETRACTED (it was a death-freeze); 00372C=death vs 003778=hurt; spitter killed by 3 flicks;
    jump/boost pad mechanics pinned; plat2 enemy cluster blocks route (s85).**
    * s83n "alive at gap edge 057C" was WRONG: 00A1F6 is the DEATH coroutine (zero vel, yield to
      fade, lives check 00A234); 002F4A 1A46=FFFF is the death object-table wipe. The 057C/0587
      "cam freezes" were death-freeze / wall-stop, not a safe ledge. There is NO fall-gap at
      0580-0630; past wall2 the slope is walkable until the plat2 enemy cluster.
    * HIT TYPES: 003778 store = survivable hurt (thorn, knockback 00A0AA, resume); 00372C store =
      FATAL contact → 00A1F6 death-freeze → object wipe → 0035DC lives dec (~+200f). Health 023E
      does NOT decrement on either (death is flag-driven, not HP). s82 "max scroll 0CAB" was wrong;
      no s82 run passed 065F (s82a-k last cam ≤065F). Bridge/exit still UNREACHED natively.
    * SLOPE = 2 walls then plat2: wall1 cam 0527 (boost1 @04E0 clears, lands ~0531); walk to wall2
      cam 0587 (freeze); boost2 at wall2 (after re-boost gate) clears, lands ~05A2; then plat2
      enemy cluster cam ~0620-0680 = enemy3 (small thorn-walker, same height) + crested walker
      (uphill, throws red spike projectiles). Walk contact = 00372C death.
    * SPITTER (slope-base bush ~0510-0530, bubbles arc onto plat1 landing zone) killed by grounded
      flicks at 0480/04A0/04C8 (3 presses; the killing shot fires ~7319 mid-boost1). With it dead,
      boost1 landing is safe and slope walkable. 2 flicks (drop 04C8) ⇒ death 7341.
    * JUMP/BOOST PAD MECHANICS (FF0502/050C taps): B1 (1-frame) is INVISIBLE to the edge register
      (no jump). B≥2 jumps; B-held-in-air OR DOWN-held-in-air ⇒ boost EF70 (009158/009194) at +2-4f.
      So B8/W6/DOWN6 = boost; a "plain hop" is NOT simply B2 (it auto-boosts). 009168 (DOWN-held-at-
      jump, anim CC16) is the no-boost variant but DOWN-held-in-air still boosts. Stomp cadence with
      plain hops not yet achieved; plat2 crossing deferred to s85.
    * Tooling: s84a-j.input; s84a-j captures; s84d1/d2 disasm (00A1C0-280, 002F00-90). NO engine
      change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s85 cross plat2 (measure flick range from stand; boost-from-distance to stomp crested
      walker; or web-oracle-guided cadence), then bridge walker + exit/scroll-limit; then M3 sound RE.
  - **Session 85 (2026-11-27): plat2 enemy cluster CROSSED (flick enemy3 + boost-stomp crested);
    native route advanced 065F→~0B2x into water/bridge area; bridge walker + exit roll to s86.**
    * FLICK RANGE: grounded flick from stand 05C0 whiffs at ~0x7D; at ~0600 (gap ~0x40-0x50) kills
      enemy3 (+50). Flick travels at player height ⇒ misses the higher crested head; uphill enemies
      need BOOST-STOMP. Crested spikes fall short at 05C0 ⇒ standing there is safe.
    * CROSSING RECIPE (s85c/d, alive, score 300): s84 prefix + WAIT24 RELEASE + W10 + HOLD RIGHT W25
      + RELEASE + W4 + A6 (enemy3) + W6 + B8/W6/DOWN6 (boost-stomp crested) + W60 + W90 + HOLD RIGHT
      W60 + W60 ⇒ water/bridge platform cam ~0745. Then A6×2 + HOLD RIGHT W100×2 + boost ⇒ cam ~0A7x.
    * WATER/BRIDGE AREA cam ~0700-0B2x (not 0C00): lower platform over water + plank bridge + left
      spitter; higher right platform nest + spikes bush; fire-walker platform bottom-right. Wall at
      ~0A7x; boost up-right → ~0B2x but descent contacts fire-walker/spike ⇒ death 8455 (s85e).
      Bridge red walker ~0C78 + exit/scroll-limit STILL unreached natively.
    * Tooling: s85a-e.input; s85a-e captures. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s86 water/bridge platforming (kill fire-walker, avoid higher-platform spikes) to
      bridge walker ~0C78 + exit/scroll-limit; then M3 sound RE.
  - **Session 86 (2026-11-28): water/bridge CROSSED and level-1 EXIT/scroll-limit (cam 0CAE) REACHED
    natively; bridge red walker ~0C78 reached; level-complete transition fires. Trunk-wall + ledge
    double-boost cadence pinned; yellow slope-walker boost-stomped; fire-walker bypassed (optional).**
    * The "pit" right of the lower platform at cam 0A75 is a SOLID dark trunk column (screen x~203-244),
      NOT open air: RIGHT held ⇒ no movement and no vert-vel writes; grounded flicks whiff (fire-walker
      sits beyond it and LOWER). Route must go OVER it via the higher ledge, not walk off.
    * Higher ledge: left part = nest (safe landing); right part = green spikes bush = FATAL from above
      (s85e/s86d landing deaths 8455/8495). Double-boost drifts tuned: boost1 HOLD RIGHT W40 lands on
      nest (cam ~0B1x); boost2 (after ~+40f re-boost gate) HOLD RIGHT W50 clears spikes and lands ledge
      right / slope top (cam ~0B6x). W20/W40 too short (land back on lower / trunk); W100 overshoots
      onto spikes (death).
    * Yellow slope-walker (ledge right, patrols down-slope): flick whiffs (it is LOWER than player
      flick height); BOOST-STOMP with HOLD RIGHT W30 drift kills it (+50 @8539). Then walk down-slope.
    * Fire-walker (orange flame, small platform bottom-right at cam ~0A7x) BYPASSED via the ledge; never
      killed (optional objective, not required for the route).
    * BRIDGE reached natively cam ~0C7x-0C9x (plank bridge over water); red walker ~0C78 visible on it
      (not killed); score 750. Scroll-limit/EXIT cam 0CAE @8651 (matches s82 web ~0CAB); reaching it
      triggers level-complete → level-card transition (mode 10 @8869). Level-1 exit REACHED natively.
    * Tooling: s86a-f.input; s86a-f captures. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s87 verify level-complete→level-2 load natively + optional red-walker kill / exit cadence
      polish; then M3 sound/Z80 RE to retire assists.
  - **Session 87 (2026-11-28): s86 "level-1 exit / level-complete" RETRACTED — reaching cam 0CAE was a
    DEATH (bridge red-walker contact), not a level clear; the mode-10 card @8869 is the death→respawn
    re-showing the level-1 intro. Level-2 load still UNVERIFIED; the red walker is the true gate (s88).**
    * s87a extended s86f past the card: 00372C (FATAL) @8635 at cam ~0C6x-0C7x, 0035DC lives 02→01 @9059,
      00508E/005096 mode/0254=10 @8869 + 002F4A object-wipe @8870 = the DEATH coroutine. The
      "FLATULENT SWAMPS LEVEL 1" card is the respawn intro; post-card field (p7-p12) = level-1 START
      (grinning tree, cam reset) with the yellow slope-walker RESPAWNED ⇒ level REPLAY, not level 2.
      cam 0CAE is the corpse-slide / right scroll clamp, not a clear trigger.
    * Bridge geometry (zoom s86f p4): the red/white object at the bridge right is a "B" BONUS box, NOT
      an exit; the plank bridge ends over open water/bush. The red walker (~0C78) guards it; walk
      contact = 00372C fatal ⇒ killing/bypassing it is REQUIRED (s86 "optional" kill is mandatory).
    * TOOLING ANOMALY (s88 resolve): a cam-locked WAIT_RAM16_GE 0698 0x0C00/0x0C20 placed after the
      final bridge walks did NOT fire when cam first crossed it (~8591); the script only advanced on
      the post-respawn replay (~8736), so RELEASE/flick/boost landed in death-freeze and were ignored.
      s87a/b/c all died at the identical f8635. Post-bridge cam-locked stops unreliable until
      understood; use fixed cadence + an early RELEASE before the bridge instead.
    * Tooling: s87a-c.input; s87a-c captures. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s88 resolve the post-bridge cam-wait/RELEASE anomaly, kill/bypass the red walker, reach
      a GENUINE level-1 clear and verify level-2 load; then M3 sound/Z80 RE to retire assists.
  - **Session 88 (2026-11-28): s87 cam-wait "anomaly" ROOT-CAUSED (script ordering, NOT an engine bug);
    bridge red walker KILLED natively (+50 @8635) and bridge crossed alive; route extended over
    trunk-wall 2 to cam ~0EF0 (wall-3) and, blind-chained, to cam ~1005. Genuine level-1 clear /
    level-2 load STILL UNVERIFIED (s89).**
    * ANOMALY RESOLVED: s87c pad/cam reconstruction shows RIGHT held 8576-8735 (= the script's
      HOLD RIGHT W60 + W100); cam crossed 0C00 @8591 AND the red-walker contact death @8635 both
      happened INSIDE those fixed WAITs, before the script ever reached the WAIT_RAM16_GE op. Cam
      then stayed >= 0C00 (corpse stop 0CAE), so the GE fired at its FIRST evaluation @8736 — during
      death-freeze, hence RELEASE/flicks ignored (8736+20 = p1 dump @8756). GE/RELEASE semantics are
      correct; the fix is to place the cam-locked stop BEFORE the fatal walk. s88a did exactly that:
      stop fired ALIVE @8592 (p1 @8602). Also: 0CAE is NOT a scroll clamp — alive cam ran to 0CFA+.
    * RED WALKER KILLED: stand-stop at cam 0C00 + grounded flicks (00F0AC @8615/8643/8671/8731) ⇒
      0037F2 +50 @8635 (the exact frame s87 died). Bridge crossed alive (p5: "B" box reachable),
      score 750→850→1000 (+50 @8815); NO 00372C/003778/0035DC after the thorn hurt @7111 through
      cam 0EF0. The s87 "mandatory gate" is now a solved obstacle, not a death sentence.
    * ROUTE EXTENDED: grass past bridge holds a floating eye + crested walkers (adjacent contact did
      NOT kill here, s88b q1); trunk-wall 2 freezes cam at 0E87, trunk-wall 3 at ~0FAE; s88g chain
      reached cam ~1005 before dying @9621 (00372C; lives dec @10045) just right of wall-3.
    * WALL-CROSSING PATTERN (s88f): VERTICAL boost (B8/W6/DOWN6, no drift) + WAIT 20 + HOLD RIGHT W12
      lands over the trunk. The s86 ledge cadence (drift W40/W50) slams the trunk left face and slides
      down (s88d/e) — wall-2/3 have no left nest pocket.
    * RE-BOOST GATE: s88d B-edge registered @9175 (0058CC) but vert vel stayed 0 ⇒ jump ignored inside
      the post-landing anim gate; a WAIT 60 settle fixes it (s88e boost @9349). Rule: settle >= 60f
      after landing / cam-freeze before boosting.
    * WALK-FLICK INERT: s88c flick cover while HOLD RIGHT fired only once (@9137); stand-flicks are
      the reliable cadence (stop-flick-stop).
    * s88g blind 3-wall chain died @9621 ⇒ crossings must be observed per-wall (s89), not chained blind.
    * Tooling: s88a-g.input; s88a-g captures. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s89 per-wall observed trunk crossings (settle 60 + vertical boost + W12), clear/avoid
      the wall-3-right hazard (death @9621 cam ~100x), reach a GENUINE level-1 clear and verify
      level-2 load; then M3 sound/Z80 RE to retire assists.
  - **Session 89 (2026-11-28): wall-3-right hazard IDENTIFIED (static red leech trap, world ~1094)
    and BYPASSED alive (lunge-whiff); trunk-4 crossed; ledge-climb cadence solved (unpress + early
    drift); toilet exit ledge REACHED alive (score 1100). Genuine level-1 clear / level-2 load STILL
    UNVERIFIED: toilet contact/DOWN/jump-on do not trigger it; next step face blocks the push (s90).**
    * TRAP MECHANICS (s89a-j): the red flat blob right of wall-3 is STATIC (s89b z0/z2/z4 identical
      while cam frozen); apparent motion in s89a was cam catch-up. It LUNGES when the player moves
      within ~46px (telegraph 10-33f) or JUMPS within >=94px, and kills on ANY contact incl. stomp
      (s89c landed on it: trap died AND player died @9749). Grounded flick AND crouch-flick whiff
      (trap sits on the higher slope surface); burp C is INERT here (edges register @9581-9622 but no
      009806 dispatch, no cloud, no health cost). Standing at gap >=94 is safe indefinitely (s89e
      112f, s89h 240f, no death). After a lunge it RETRACTS (s89c/d z5 trap gone) => harmless window.
    * WORKING BYPASS (s89k/m/n, NO death): boost from w2 (X=100B, gap 137 = outside jump-aggro) with
      drift-from-jump; the lunge leaps at the AIRBORNE player and whiffs; trap retracts; walk/boost
      on while retracted. Air-flick (0091E4) fires during descent (ammo dec @9515) and scored +100
      (1000->1100) on a target beyond trunk-4; a second air-flick failed its vert-vel gate.
    * PLAYER WORLD COORDS: FF1A24 = world X (writer 00279C, 2f cadence), FF1A26 = Y. Cam freezes
      while standing => screen-x arithmetic is INVALID; use X taps. Route X: w2 face 100B; trap
      1094; trunk-4 face 10C2 (lunge reach 46 covers the whole "pocket" => no safe pocket exists);
      pit/ledge foot 1137; toilet ledge top ~117x; another step face right of the toilet.
    * PRESSED-EDGE JUMP GATE (s89l): B-edge registers (@9937) but NO Y write while pressed against a
      wall/step face => jump ignored regardless of settle. FIX (s89m): step LEFT W6 to unpress,
      settle 60, then boost. DRIFT TIMING: drift must start while ABOVE the target top (jump+10,
      W40); late drift (jump+32, s89l) is below the top => face block => slide back to foot.
    * EXIT LEDGE (s89m/n): climb lands beside the white TOILET alive; contact, PRESS DOWN and
      jump-on it produce NO 0244 setter / no clear; push right (W60+W100) blocked at the next step
      face (same pressed-edge gate) => s90 repeats the climb cadence per step and hunts the real
      exit trigger. No 0244 setter after @6086 in ANY s89 run.
    * Tooling: s89a-n.input; s89a-n captures. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s90 repeat unpress+early-drift climbs past the toilet ledge, identify the genuine
      level-1 exit trigger, verify level-2 load; then M3 sound/Z80 RE to retire assists.
  - **Session 90 (2026-11-28): club step + canopy crossed ALIVE (score 1250, both club-walkers
    flick-killed); stop-and-flick cadence reached a SECOND toilet alive; level named FLATULENT
    SWAMPS LEVEL 1. Genuine level-1 clear / level-2 load STILL UNVERIFIED (s91). NEW: windowed
    replay launcher (BoogermanReplay-US.bat + tools/replay-best.input) so the user can watch/play
    the best alive route between sessions.**
    * TOILET-TOP HOP (s90a/b): the toilet is a SOLID standable platform (top Y=0x81 vs ledge
      0xA1; span ~11A0-11C4). From ledge right of it: unpress RIGHT W6 + boost drift-LEFT W24
      lands LEFT of it (X=116E); drift-RIGHT W14 lands ON top; W30 overshoots (rides off the
      right edge back to ledge); from the top boost drift-RIGHT W20 lands on the club step
      (X=11E2). Drift speed ~3px/f ⇒ calibrate drift frames to target span, not to feel.
    * CANOPY IS THE ROUTE: the club step's right end holds a leech trap (X~128x; s90b blind push
      died @10561 at X=1283). ANY jump from the club step — plain B8 without DOWN boost too
      (s90f) — rises onto the canopy grass platform above it; landing amid its two patrolling
      club-walkers = contact death (s90c @10625, s90d @10585). Air-flicks whiff at descent
      height (only 1 kill +50); spending ammo on grounded flicks before the hop starves them.
    * CANOPY WALKERS KILLED ALIVE (s90g): short drift W20 lands on the canopy LEFT edge, left of
      the walkers; GROUNDED flicks at same height kill both as they approach (+50 @10543,
      +50 @10615 ⇒ score 1250). The bridge stop-flick recipe generalizes to canopy patrols.
    * STOP-AND-FLICK CADENCE (s90h, NO death): W30 push + stop + 2 flicks, repeated, carried past
      the canopy and down the slope to a SECOND toilet alive (h5/h7). Blind W100 pushes die
      (s90g @10903 on the next walker).
    * SECOND TOILET (s90i): standable top; DOWN beside / jump-on / DOWN-on-top produce NO 0244
      setter / no clear; push right died @11131; the respawn intro card names the level:
      FLATULENT SWAMPS LEVEL 1. No 0244 setter after @6086 in ANY s90 run ⇒ genuine clear /
      level-2 load STILL UNVERIFIED ⇒ s91.
    * USER REPLAY TOOLING: native/BoogermanReplay-US.bat runs the exe with --input-script
      tools/replay-best.input and NO --capture-out/--exit-at-frame ⇒ SDL window SHOWN and paced
      (main.c:3187), sound on; script pads MERGE with live keyboard (main.c:991-1010) so the
      user can grab controls mid-replay or after it ends (no EXIT op ⇒ window stays open).
      replay-best.input now carries the s90h alive route through the second toilet.
    * Tooling: s90a-i.input; s90a-i captures. NO engine change; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s91 continue the stop-and-flick cadence past the second toilet, identify the
      genuine level-1 exit trigger, verify level-2 load; then M3 sound/Z80 RE to retire assists.
  - **Session 91 (2026-11-28): genuine level-1 exit trigger IDENTIFIED and REPRODUCED natively
    (HOLD DOWN >=~30f grounded on the FIRST toilet top => flush coroutine: 00882A increments
    FF0258 level counter, 008832 mode<-[FF0A98]=0x24, 00883C 284|=5, fade to black, mirror
    00508E/005096 @+30f). Confirms the user's manual clear; s90i's 6f press was below the
    hold threshold. Level-2 load STILL UNVERIFIED: clean-config stall root-caused to 3 links,
    2 fixed+verified, 3rd = Z80/SMPS ack handshake (M3). Second toilet is NOT an exit.
    NEW flush-window LOAD-WINDOW ASSIST (BOOT_ASSIST-gated, main-loop + V-int copies).**
    * TRIGGER (s91a): toilet-top u1 ~10275, HOLD DOWN from ~10365, commit @10395 (0258=1,
      0244=0x1024), mirror 0x24 @10425, loader DMA-list init 006704 @10475. 006704 is NOT a
      countdown wait: it writes 20 words of 0180 to FF146E-FF1506 (a DMA/command list whose
      TAIL is 1506 — the s60/s61 "1506 countdown" reading was a misread of this list).
    * STALL CHAIN (s91b/c/e, crash_trail @~20s wall): (a) head work 001440 leaves A65 bit0
      set and 0246=1 since f17 => 644C/6710 HUD staging gate (A65 bit0 && 0246) re-pins
      1506=0160 every 2f, corrupting the loader list tail — FIXED by flush-window A65 bit0
      clear (pinning gone, tap-verified). (b) 098AA0 service retry exit = 052C<2 && 054C==0
      (s91d7 disasm); the flush queues two never-acked commands so 052C stays >=2 — FIXED by
      forcing 052C/054C/0524/0548 idle (098AC6 left the trail, verified). (c) with the gate
      open the service still loops the Z80 cmd/ack handshake 098D24/098D2A/098A10/098D52
      forever; boot completes only because BOOT_ASSIST seeds Z80 $0FAD=$FE/$0FC2 while
      g_snd_frame<4000. Extending that seeding (+FE4/FAC, iff1) into the flush window did
      NOT ack the level-2 init queue => mode-3 commit 0155E4/015606 never fires => M3
      Z80/SMPS driver RE (Next 2). s90i/s91 "no clear" was this stall, not a missing trigger.
    * ASSIST PLACEMENT: the main-loop glue_service_vblank copy alone is inert while the
      service spin occupies frames; the V-int own_deliver_vint copy alone is inert before
      the spin; BOTH copies are needed (s91e trail proved V-int fires during the spin).
      s69 clean config (TITLE_ASSIST off since s68) and the play bat never run the s50-s61
      title assist, so all s88-s91 gameplay probes ran WITHOUT it. tassist post_title phase
      model now also excludes mode 24 (inert in clean config, correct for -TitleAssist).
    * SECOND TOILET (s91d): HOLD DOWN 90f on its top => NO 008832 / no mode 24 => decorative;
      the first toilet is the only exit found. s90h's alive route end stands.
    * TOOLING: s91a-e.input; s91d1-d7 disasm (0087C0/008642 flush gate, 006440 HUD gate,
      0066F4 list init, 015740 chunk loader, 005780, 098A90 retry). crash_trail sampling:
      debug.ini next to exe enables the cmd server (port 4400); s69 capture runs DO listen;
      16000f capture run ~= 25-30s wall, sample ~20s for the ~10.7kf stall window.
      replay-best.input UNCHANGED (s90h remains the best proven alive route; the flush ends
      in the stall). Engine change: glue.c s91 assist; diffs regen base->worktree;
      gitlinks stay 9907e77f40/6f705f2.
    * => Next: s92 = M3 Z80/SMPS ack RE for the flush-load window (098D24/098D52 handshake,
      level-2 init queue) so mode 3 commits natively; verify sewers load, map sewers route;
      audio fidelity in the same pass.
  - **Session 92 (2026-11-28): flush stall RE: the Z80/SMPS handshake is EXONERATED (with the
    s91 assist it returns every frame; Z80 SMPS healthy and idle). Real stall = the mode-24
    handoff parks the MAIN coroutine (ctx FF1A0E, resume long FF1A12) in the fade-wait routine
    008238 (type-2E fade object via 0042F6 + FF0248 gate) forever; boot hands it 0154FC
    instead. NEW fade-wait skip in the LOAD-WINDOW ASSIST (both copies): after >120 parked
    frames, resume := 0154FC. Verified: flush coroutine spawns @10754 (01554A/0212=1) and the
    chunk loader runs — but completion takes the (10,A4)==1 branch @01562E => modes 34/35/36
    = ATTRACT DEMO, not level 2. Sewers load STILL UNVERIFIED; next gate = chunk-loader
    completion / (10,A4) clear (015784/49AA/4AF2) vs the demo branch (s93).**
    * HANDSHAKE DECODED (s92d1/d2, s92a probe): 098D24 = MOVEA (FF051A),A6 (=00A00FAC);
      bus-request 098A10 (poll A11100 bit0) / release 098A30; wait (A6)==0 = Z80 consumed the
      command. Z80 SMPS idle loop: 1009 LD A,(0FC2)/CALL NZ,16E0 (per-frame tick, clears
      0FC2); 1013 CALL NZ,174C (YM write + D+E delay loop); 1017 LD A,(0FAC)/JR Z,1009;
      101D consume+ack (XOR A; LD (0FAC),A); 1001 LD A,(0FAD)/CP FE/CALL Z,10B4 only when a
      command is pending. Mid-stall: iff1=1, irq_pending=0, V-int 0038 every frame (14847
      hits/15k frames), 0FAC=0 => Z80 idle because NO command ever stays queued, NOT stuck.
    * s91 CORRECTION: the "service spins 098D24 forever" trail was PRE-assist; with the s91
      assist the trail shows 098D24 RETURNING (098D52) each frame and the whole sound service
      completing per frame. The stall was always upstream of the handshake.
    * STALL LOCALIZED (s92b/c/e taps + s92d boot RAM diff): boot commit swaps main-ctx resume
      FF1A12 873A->0154FC (load head); flush commit swaps it to 008238 (fade-wait) and it
      never leaves: 008238 waits 0042F6(type 2E)==0 AND FF0248==0, else yields @008156.
      0212 tap: boot 01554A @1739/2778, flush NONE pre-assist. Object count 0624=FFFF during
      loads is NORMAL (plane setup 005666 gate 0A82==4A); free-list 02BC alloc is NOT the gate.
    * FADE-WAIT SKIP (s92f, env-gated BOOT_ASSIST, both assist copies): >120 frames with
      resume==00008238 => write resume 000154FC. Flush coroutine then spawns @10754, chunk
      loader runs, parent exits its yield loop @~10830 but (10,A4)==1 => 01562E writes mode
      34 (demo commit, same pc as boot attract @1816), then 35/36 @12731/14595 (005AD6).
      Captures show demo autoplay (score carries 1250->4025), NOT a sewers intro card.
      Boot level load took 015606 (mode 3) because the chunk-loader completion cleared
      (10,A4); at flush it never clears => s93 gate.
    * SUPPORT DECODED: mode head dispatch 00515A (word table 006EFE, index=mode*2) -> 0013C6
      DECOMPRESSOR into FF0A50 (the s91 "A65 bit0 setter 001440" is decompressed config data);
      0066F4-00695C = HUD DMA-list staging only (006710 gate A65 bit0 && 0246); 006D60 =
      ReadJoypads; 004E4A/4E78/4ECE = V-int scroll + staged-list DMA flush; scheduler 4970
      yield ((0,A4) BMI / (2,A4)<4 / (76,A4) countdown park; JMP (72,A4)), 49AA exit.
    * TOOLING: s92-probe.ps1 = CONNECT-ONLY cmd probe (z80_state, read_z80_ram dec addr,
      read_memory hex-string addr, crash_trail, rdb_get_state, objtable dumps) for an
      already-running runner; s92d.input = boot pre/post-commit DUMP_RAM diff to locate ctxs.
      crash_trail ring = EMITTED blocks only (interp bodies invisible) => absence != not
      executed; OBJ-TL long writes = hi word then lo word (FF1A12 hi / FF1A14 lo).
      s92a-f runs; s92d1-d20 disasm. Engine: glue.c fade-wait skip; diffs regen base->worktree;
      gitlinks stay 9907e77f40/6f705f2. replay-best.input UNCHANGED (flush still ends in demo).
    * => Next: s93 = chunk-loader completion gate: tap (84,A4)=FF1A62 chunk counter and
      (10,A4)=FF1A18 through the flush window; RE 015784/49AA/4AF2 completion vs 015790 idle
      park and the 01557E branch select; make the flush load take 015606 (mode 3) so the
      sewers intro + mode 10 commit; verify sewers gameplay, map its route; audio fidelity
      in the same M3 pass.
  - **Session 93 (2026-11-28): SEWERS LOAD + GAMEPLAY VERIFIED. The s92 "demo branch" was an
    artifact of the assist's own handoff: 0154FC with (16,A4)=FF1A1E expired falls into
    015544, which sets the (10,A4)=FF1A18 demo flag; the genuine level-load entry is 01554A
    (DOWN pad gate). The genuine FLUSH chain never uses 0154FC at all: mode-24 head 008016
    (0258!=0) -> 008848 -> 00CAD0 loads the SEWERS chunks 1EF-213 NATIVELY (@10483-10600) ->
    00AA90 idle park -> 008274 -> 00A4A8 -> 00C6B4 -> main-loop fade-wait 008238 parked on
    FF0248!=0. The fade countdown 0248 (set 0x40, tick at 003724) is never ticked natively.
    NEW assist: after >120 parked frames CLEAR FF0248 (both copies); the guest's own mode-24
    head — which IS the sewers gameplay head — then runs the entry. s93g/h captures: sewers
    bricks/pipes/slime drains, player spawns on the toilet, walks/boosts right past the
    slime pool / grate / tipped bin / pipe walker, no death. The A65 bit0 clear + fade skip
    are now gated to the fade/load window (0248!=0 || 0212!=0) because mode 24 doubles as
    gameplay; the sound-idle seeds stay mode-24-wide (audio = M3).**
    * DEMO-FLAG MECHANISM: 015544 sets (10,A4)=1 => completion 01557E -> 01562E demo;
      01554A leaves 0 => 015588: 0254!=0 && (22,A4)>=0xC0 -> 01561A mode 2 (no stats reset)
      else 0155AC mode 3 + 0258=0. (22,A4)=FF1A24 is a per-frame scroll field (00279C):
      0x98 at flush / 0xB4 at boot, both <0xC0 => an EXTRA 01554A load always mode-3 and
      replays LEVEL 1 (s93c intro card). Hence the extra load was removed in favor of the
      0248 clear; the sewers geometry was already loaded by 00CAD0.
    * SUPPORT DECODED: 4AF2 only marks chunk rows valid (ORI #2,(5870,row)); 49AA FALLS
      THROUGH 49B0 (unwinds the buried return); 31E0/3A14 pop the return into (4,A4)=FF1A12
      (the slot the assist writes) while (72,A4)=FF1A56 is the scheduler resume; 6F82 =
      sound call with INLINE param bytes (the "garbled" 5034 = data 50 34); 00A32C =
      demo-end/title reset (zeroes 0258), type 2E = demo controller, object type at (46,A0);
      0013AC = ROM config table 09CBC4[D0*4]; 003208/3230/3244 = the only (78,A4) writers;
      00A024 = transition/respawn family (re-sets 0248=0x40, resume 00C622).
    * REMAINING (s94): sewers HUD ABSENT — the mode-24 config init never sets A65 bit0
      natively (per-frame config copy writes 0), so the HUD DMA gate 006710 (A65 bit0 &&
      0246) never opens; RE the mode-24 config/decompressor init or mirror the web-oracle
      post-entry A65/0246. Map the sewers route beyond the opening. Audio fidelity M3.
    * TOOLING: s93d1-d16 disasm; s93a/b/e/f write-taps; s93c/g/h runs; s93h.input = flush +
      sewers gameplay probe; replay-best.input UPDATED to the flush->sewers route (window
      stays open, no EXIT). Engine: glue.c 0248-clear + fade-window gate; diffs regen
      base->worktree; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s94 = sewers HUD/config-init (A65 bit0 / 0246 in mode 24) + sewers route map;
      then M3 retire assists / audio fidelity.
  - **Session 94 (2026-11-28): SEWERS HUD RESTORED + ROUTE MAP CORRECTED + REPLAY AUTO-PLAY
    HARDENED.
    * HUD ROOT CAUSE CORRECTED (s93 premise wrong): the mode-24 config decompressor (0013E8
      family, stores 001440/001476) DOES write FF0A65 bit0=1 on its first pass (@10425,
      mode-24 mirror), then a SECOND pass +14f (@10439/10440) overwrites +0x15 with 0, and
      nothing writes A65 again during sewers gameplay (s93h taps: zero A65 writes after
      10440; the per-frame zeros during the fade were the assist's own clears logged at
      ambient guest PCs — OBJ-TL pc is block-granular for interp stores). Hence the HUD DMA
      gate 006710 (bit0 && 0246) never opened. s94 ASSIST: at the fade-skip moment
      (fwait>120, both glue copies) also SET A65 bit0=1 — restoring the bit the guest's own
      first pass wrote, once the load is committed. s94a captures: HUD icons (hand / chili
      / slime blob) render screen-fixed in sewers. M3: RE the second decompress pass source
      (suspect zero-filled DMA source) and retire the mirror.
    * ROUTE MAP CORRECTED — s93 "walks right past the slime pool, no death" RETRACTED: the
      pool right of the concrete ledge is a DEATH hazard. s94a @11700 = player sinking (no
      player on screen); s94b crossing attempt (boost-jump right 60 from the ledge) ends in
      the respawn transition 00A304 @11840 + level intro card @11900 (s87 pattern). PROVEN
      ALIVE STOP = the concrete ledge with the garbage pile (s94c final capture: player
      idle there, HUD on, lives 022E=2, no mode write after the flush). Opening layout:
      spawn toilet between two slime drains -> right walk ~120f -> boost-jump ~40f onto the
      ledge (garbage pile) -> slime pool with grate arch + tipped skull bin + pipe walker
      on the pipe above. Crossing unmapped (s95).
    * REPLAY AUTO-PLAY DIAGNOSIS (user: "no automatic inputs in BoogermanReplay-US.bat"):
      NO hotkey exists; the script runs from boot but the first press is ~35 s in (title
      Start) and every later op is condition-gated. A real-time paced probe (s94rt,
      --measure-runtime) auto-plays identically to turbo (title commit @2345, mode 3 @2854,
      mode 0x10 @6056) => the bat invocation is fine; playing manually FIRST desyncs the
      waits (HOLD START + WAIT 0254=1 parks forever with START stuck once a human committed
      the title). HARDENING: input_script_abort() + main-loop human-takeover (live
      keyboard/pad mask >20f cancels auto-play and releases holds); replay-best Start =
      bounded PRESS START 40; both bats set GENESIS_STDERR_LOG (build\replay-err.log /
      play-err.log) so detached launches leave evidence; bat/input headers document the
      timing + takeover.
    * TOOLING: s94rt.ps1 (real-time paced probe), s94b.input (stop-alive + crossing
      attempts), s94r0/rt/a/b/c runs; s94d1-d4 disasm (0013C6-0014B0 decompressor,
      0015A0-001620, 000C60-000CA0, 0048C0-0048F0). replay-best.input UPDATED: stops alive
      at the ledge, HUD + takeover notes. Engine: glue.c HUD mirror, main.c takeover +
      stderr log, input_script.c/h abort; diffs regen base->worktree; gitlinks stay
      9907e77f40/6f705f2.
    * => Next: s95 = sewers pool-crossing map (pipe above / bin platform / longer boost
      from the ledge edge) + RE the second config decompress pass (A65 zero root cause)
      for M3 mirror retirement; then M3 audio fidelity.
  - **Session 95 (2026-11-28): PLAY-INPUT RECORDER + TRACE BAT SHIPPED; SEWERS HUD GATE
    ROOT CAUSE = 0212 NEVER CLEARS; s94 "HUD ICONS" CLAIM RETRACTED; DEATH IN SEWERS =
    LEVEL-1 REPLAY; USER REACHED LEVELS 2-3 MANUALLY.**
    * USER MILESTONE: manual play via BoogermanRecomp-US.bat cleared level 1 -> first
      toilet -> sewers -> exit toilet at the end -> back to level 1 (second toilet) ->
      level 1 end -> LEVEL 2 -> LEVEL 3. The whole progression chain works natively.
      User observations: HUD disappears in sewers; some attack audio effects stick (M3).
    * CAPTURE TOOLING (user: "can I capture my inputs/logs while playing?"): YES —
      GENESIS_INPUT_RECORD=<path> (main.c record_input_line) logs the sealed P1 pad mask
      on every change as frame-indexed script lines ("<frame> BUTTONS"), the parser's
      replace-at-frame form, so a manual session records a DIRECTLY REPLAYABLE .input.
      BoogermanRecomp-US.bat now writes build\play-input.log; NEW BoogermanTrace-US.bat
      adds GENESIS_OBJ_TL taps (244,248,212,258,22e,a65,246) -> build\trace-err.log +
      trace-input.log for bug reports. ROUND-TRIP VERIFIED: recorded replay-best run
      (150 change events) replayed verbatim as a script -> flush @10361 identical and
      @11400 capture pixel-identical (s95rec vs s95rt).
    * HUD GATE ROOT CAUSE (corrects s94): FF0212 is set 1 by 01554A at EVERY level load
      (f=1739, 2744) and never cleared natively; the flush chain bypasses 01554A, so
      0212=1 carries into the sewers and the fade gate (0248!=0 || 0212!=0) NEVER closes
      => the assist's per-frame A65 bit0 clear ran through ALL sewers gameplay (s95a
      taps: per-frame zeros between the mirror fires @11081/@11620). s95 FIX: clear 0212
      together with 0248 at the fade-skip (both glue copies) + restore bit0 after any
      later fade once committed (sewers flag, reset on mode exit). Verified: bit0 stable
      1 post-entry, per-frame clears gone (s95a2).
    * s94 "HUD ICONS RESTORED" RETRACTED: the top hand / chili / slime blob are WORLD
      objects (pipe-end hand, the walker's thrown chili projectile, wall slime splat) —
      pixel-identical pre/post fix, and the chili flies independently of the walker. The
      REAL HUD = the bottom status bar (lives / score / plunger), ABSENT in sewers even
      with the gate open (0246=1 since boot f=17) and the HUD DMA list FF146E-1506 fully
      populated (s95b DUMP_RAM level1 vs sewers: same 0001-0013 entry shape). => bar
      absence is downstream of gate+list: plane/scroll setup or a mode-gated HUD routine;
      needs a web-oracle phase-matched sewers comparison (s96).
    * DEATH IN SEWERS = LEVEL-1 REPLAY, not a sewers respawn: s95a pool death @~11800 ->
      respawn transition -> level 1 swamp @12500 with lives 2->1 and the guest's own
      level-1 config write A65=1 @11972 (pc=001440).
    * CROSSING: s95b pipe attempt (boost up-right 30 from the ledge + 3 flicks + walk
      right 140) DIED (intro card @12000). Crossing still unmapped; ground truth = the
      user's recorded manual sewers run now that the recorder ships (s96).
    * SECOND-PASS RE (partial): mode dispatch 00515A = ONE BSR 0013C6 per call (table
      006EFE[0244*2], buffer FF0A50); the mode-24 head 008848-0089C2 contains NO
      decompressor call => the +14f second pass is a SECOND dispatch call; caller
      identification = s96. Head decode: 00887E gameplay head; 0266/0268 gates; pad
      050C&10 -> 00902A, 0502&4/8 -> 003310/003304 with cam (54,A4)+=0280; type-28 check
      @0089A8 -> 00A024 when 0248==0.
    * TOOLING: s95a/s95a2/s95b/s95rec/s95rt runs; s95d1/d2 disasm; s95a.input /
      s95b.input (DUMP_RAM idioms). Engine: main.c recorder, glue.c 0212 clear +
      post-fade restore; diffs regen base->worktree; gitlinks stay 9907e77f40/6f705f2.
    * => Next: s96 = (a) map the sewers crossing from the user's recorded play-input.log
      (replay it, extend the alive route past the pool to the exit toilet); (b) HUD
      bottom-bar root cause via web-oracle phase-matched sewers RAM/capture diff
      (plane/scroll vs mode-gated HUD routine); (c) RE the second dispatch caller so the
      A65 mirror can retire; then M3 audio fidelity (stuck attack SFX).
  - **Session 96 (2026-11-28): SEWERS CROSSING SOLVED FROM THE USER'S RECORDING AND
    PROMOTED TO replay-best; HUD BOTTOM-BAR ABSENCE = ORIGINAL DESIGN (NOT A BUG);
    CLEAN-ENV FADE GATE FIXED (ASSIST HANDS-OFF POST-COMMIT); DISPATCH CALL-SITE CENSUS.**
    * USER RECORDING REPLAYED VERBATIM (s96a, bat-matching env): flush #1 @6943, exit
      toilet flush @9225 (back to level 1), level-2 load @10110; ZERO life loss. The
      crossing = jump/boost cadence onto the UPPER PIPE platform, traverse right above
      the slime pool, drop to the exit toilet; short DOWN presses (12-25f) flush when
      grounded on the top (s91's >=30f threshold was position-confounded).
    * SPLICE PROVEN + PROMOTED: replay-best prefix + user ops 6849..9600 rebased +3482
      (s96-splice.ps1) ⇒ flush @10411, exit @12707, stop ALIVE at the level-1 second
      toilet (s96c/s96d). s96-promote.ps1 shipped it as replay-best.input ⇒
      BoogermanReplay-US.bat now auto-plays the whole crossing and returns alive.
    * HUD ROOT CAUSE (retracts s94/s95 "restore" framing): sprite table = VRAM F000;
      sewers RAM list + VRAM hold y=0180 (offscreen park) vs level-1 y=013C/014C. The
      park (00698E, 80 entries) runs at EVERY mode commit via 0050B8; the bar builder
      0071E6 (writes 146E/1470/1472/1474) is called ONLY by intro slide-in / menu
      routines (ROM-wide BSR/JSR census: 005B72/5B8E/5C1E/5C9A/5D78/5DFC) and is silent
      during gameplay. The sewers load path never calls it ⇒ the ORIGINAL game also
      hides the bottom bar in sewers. User observation = authentic behavior.
    * CLEAN-ENV GAP + FIX: clean boots never start the entry fade (0248 stays 0, no
      008238 park) ⇒ s95's fade-skip never fired in the bat env and 0212=1 from boot
      kept the assist gate open (per-frame A65 clear through sewers gameplay). s96:
      commit-detect bookkeeping (mode 24 && 0248==0 && 0258!=0 && >240f) clears 0212 +
      mirrors bit0 in both glue copies; restore made conditional ⇒ assist hands-off
      post-commit (s96z2: last host write @10651; next A65 write = guest @12738;
      flushes/lives/crossing intact).
    * SECOND-PASS CENSUS: only BSR 00515A = 0050A0 in commit tail 005062; 005062 has NO
      direct callers (indirect scheduler dispatch); s95a's double mirror fire = tail
      run twice ⇒ second pass = second 005062 invocation post fade-resume; exact
      indirect edge = M3. Direct 0013C6 sites census in RAM_MAP s96.
    * WEB ORACLE LIMITS: title-ready ~11900 (shift +9557); gpgx drift game-overs the
      tight script route by 19800; harness wr double-XORs addresses (pass odd for low
      byte); s69-web.ps1 gained -Budget/-Wr. Authenticity settled by code census.
    * TOOLING: s96-splice/promote/webtimeline/webshift/dumps/callscan.ps1; s96a-z2
      runs; s96d1-d11 disasm; s96w/v.input dumps; s96c.input probe. Engine: glue.c
      commit-detect + conditional restore; diffs regen base->worktree; gitlinks stay
      9907e77f40/6f705f2.
    * => Next: s97 = M3 audio fidelity (stuck attack SFX via trace-bat frame stamps) +
      assist retirement (Z80 cmd/ack 098D24/098D52, fade tick 003724, second-dispatch
      indirect edge).
  - **Session 97 (2026-11-28): STUCK ATTACK SFX ROOT-CAUSED AND FIXED — THE BOOT_ASSIST
    DAC-REQUEST RE-SEED RESTARTED PLAYING PCM SAMPLES EVERY TICK; SEEDS NOW SELF-RETIRE
    (g_sound_guest_alive); MODE-24 SEEDS WINDOW-GATED; EU CLEAN MODE-34 STALL PROVEN
    PRE-EXISTING BY BISECT.**
    * USER REPRO (BoogermanTrace-US.bat): one burp C @1703-1713 after START@1259;
      trace-input.log replayed verbatim (s97a.input). Measurement chain =
      GENESIS_AUDIO_WRITEDUMP (full-run FM/PSG stream, frame + scanline + Z80 pcz) +
      s97-summarize.ps1 (per-frame $28 key events, non-$80 DAC bytes, PSG writes).
      [AUDIO-Q] psg_count/fm_count are PER-FAME render sample counts, NOT write totals.
    * ROOT CAUSE: BOOT_ASSIST forced z80_ram $0FAD=$FE + $0FC2=$01 (DAC request) every
      V-int frames 16-4000 (glue V-int copy) AND on every Z80 $0FAC=0 ack (genesis_bus
      gbus_z80_write path b). Re-setting the DAC request each tick made the DAC player
      (Z80 PC $1755/$175B) restart the playing sample every frame: burp onset @1716,
      identical ~113-byte window looped forever (s97a f=1716-2612). The music DAC track
      was likewise truncated to ~42 fragment bytes/frame instead of continuous PCM.
    * FIX (engine): g_sound_guest_alive (genesis_bus.c) set when the guest writes its
      own handshake cells (Z80 $0038 handler writes $0FAD; 68K service writes
      $0FAD/$0FC2); both boot seed paths gate on !alive ⇒ permanent retirement once the
      guest driver runs. Mode-24 glue copies (V-int + main loop): all sound seeds +
      iff1 moved inside the fade/load window (0248!=0 || 0212!=0) ⇒ sewers gameplay no
      longer re-seeds either. GENESIS_SOUND_SEED_LEGACY=1 bisect knob keeps the old
      window for attribution.
    * VERIFIED: s97c burp plays through ONCE (DAC bytes evolve f=1716-1732, then idle,
      music resumes; tail f=2560-2612 continuous varied music PCM, no loop); music DAC
      baseline restored (~265 nz bytes/frame). s97d replay-best crossing intact:
      flush→mode 24 @10441, exit flush via 008832 @12707, recommit @12738, alive stop
      at the second toilet with HUD, lives 02. s97e sanity on final binary: commit
      @1260, no game-over.
    * EU BISECT: EU exe was stale (Nov 26, pre --exit-at-frame ⇒ first probe ran
      real-time to timeout); rebuilt. EU clean boot stalls black at mode 0x34
      (cutscene) after fade completes @2569 in BOTH arms (s97eu4 retired vs s97eu5
      legacy window) ⇒ PRE-EXISTING EU clean-config gap, NOT a s97 regression; US
      remains the validated boot path. EU gap queued for s98.
    * TOOLING: s97-summarize.ps1; s97a.input; capture mode (--capture-*) implies
      turbo + no launcher + no audio device (main.c ~2811) — direct exe runs without
      it are real-time windowed; PS 5.1 `2>` redirection writes UTF-16 (read with
      Get-Content -Encoding Unicode).
    * => Next: s98 = assist retirement round 2 (fade tick 003724 RE for the 008238 park
      skip; second-dispatch indirect edge for the A65 mirror; Z80 cmd/ack 098D24/098D52
      RE for the flush-window idle seeds) + EU clean mode-34 cutscene stall.
  - **Session 98 (2026-11-28): LOAD-WINDOW ASSIST FULLY RETIRED — THE GUEST COMPLETES
    THE FLUSH LOAD NATIVELY POST-S97; SEWERS HUD-BAR ABSENCE WAS AN ASSIST ARTIFACT
    (s96 "ORIGINAL DESIGN" RETRACTED); FADE TICK = 000980 (NOT 003724); SECOND
    COMMIT-TAIL EDGE = 006B02 (SOUND-SERVICE COMPLETION); EU STALL LOCALIZED TO THE
    MODE-34 HEAD NEVER REACHING THE 02BA TITLE-INIT.**
    * USER CONFIRMATION: burp stuck-SFX gone; SEGA-logo/menu noise gone. One-off
      <=1 s noise when the START/PASS menu loaded, never reproduced on later
      attempts — documented per user instruction, NOT hunted.
    * FADE TICK CORRECTED: true tick = SUBI.W #1,(FF0248) @ **000980** (identical in
      US+EU), single caller = V-int BSR @0007F6 (fade service 000964, palette writes
      FF2324/26). s93's "003724" was a TST gate inside object-kill routines
      0036F4/003744 (block-granular pc misattribution).
    * SECOND-DISPATCH EDGE: commit tail 005062 has NO long-immediate users anywhere
      in the ROM (s98-writers -Long); entries = BRA 005CBA/005E38 (menu) + **006B02**
      (s98-brascan) = sound-service completion, gate **05D4==1 && 0284&1** (006A82).
      The second decompress pass (A65 bit0 zero, s94) fires only while the flush SFX
      stays un-acked — the assist's own idle seeds caused that pre-s98.
    * RETIREMENT: GENESIS_LOAD_ASSIST_OFF bisect (s98c) ⇒ guest completes the sewers
      load with ZERO mode-24 assist: crossing frame-identical to assisted runs
      (flush 10411 / mode-24 10441 / exit 12707 / recommit 12738, lives 2). Both
      LOAD-WINDOW copies (V-int + main loop) DELETED: sound seeds, A65 bit0
      clear/mirror, 0248/0212 fade bookkeeping, 008238 park skip, commit-detect.
      Post-s97 the healthy guest Z80 driver acks the flush SFX ⇒ 098AA0 retry and
      098D24 handshake complete natively ⇒ the s91-s96 "stall" was assist-era.
    * HUD BAR RETRACTION (s96): native runs show the sewers BOTTOM BAR (lives/score/
      plunger) + all world sprites; assisted runs hid them. RAM list identical in
      both (146E=013C @10491 via 0067D8); divergence downstream in sprite VRAM
      upload, perturbed by the assist's per-frame seeds (mechanism detail = s99).
      User's s95 "HUD disappears in sewers" = assist artifact, not original behavior.
    * VERIFIED on final binary: s98j (probe env) + s98m (bat env, -NoSplashAssist)
      crossing + bar + lives 2; s98k burp plays once (DAC evolves f1716-1732, ends).
    * EU STALL LOCALIZED (s98eu6): EU exits mode 34 @3138 → mode 2 (00A302) then
      BLACK; **02BA never set**. 02BA=1 setter (US 0055EA / EU 0055F6, routine
      0055C6) is gated by **A65 bit1** and runs in US DURING mode 34 (@2049, A65=3);
      EU's mode-34 head never reaches it (cutscene re-fades @2766/3168 instead of
      completing); EU mode-2 commit decompress writes A65=0. EU fade-object
      lifecycle / mode-34 head gate = s99. Sound service itself healthy (05D4=0F @89).
    * TOOLING: s98-writers.ps1 (absolute-word writer / long-immediate ROM scan,
      US+EU), s98-brascan.ps1 (BRA.W/S + JMP.L census). PITFALL: s69 -InputScript
      needs the .input extension — a bare name logs "cannot open" and silently runs
      NO-INPUT (s98a/b first passes were attract-demo observations, invalidated).
    * => Next: s99 = EU cutscene completion (mode-34 head → 0055C6 02BA init;
      fade-object lifecycle) + sewers bar sprite-DMA mechanism detail + SPLASH
      s54/s65 probe-env retirement.
  - **Session 99 (2026-11-28): A65 = DECOMPRESSED LEVEL-HEADER BYTE (NO LOGIC
    SETTER); TITLE-INIT VRAM UPLOAD IS 005AE2 GATED BY A65 BIT0; TITLE-DISPATCHER
    02BA/0284 GATE POLARITY CORRECTED (s98 BACKWARDS); EU DOES SET 02BA THEN THE
    MODE-2 COMMIT CLEARS IT; EU BLACK = BOOT-INTRO COROUTINE 00A302 COMMITS TITLE
    AFTER THE FIRST CUTSCENE (ATTRACT-LOOP SELECTOR DIVERGENCE) WITH HEADER BIT0=0
    ⇒ 005AE2 SKIPS VRAM INIT; SPLASH s54/s65 RETIRED (CROSSING FRAME-IDENTICAL).**
    * USER CONFIRMATION: sewers status bar present via BoogermanRecomp-US.bat —
      closes the s96 retraction loop on the final binary.
    * A65 SOURCE: FF0A65 = level-header byte 0x15 (header base FF0A50), written
      ONLY by the decompressor copy loop 001440 (MOVE.B D1,(A1)+). No logic
      setter exists — s98-writers "op=0001" hits were BTST #1 immediates.
      Decompressor VERIFIED correct: native-EU mode-34 header byte-identical to
      web-EU (0A62=0035 next-mode, 0A65=03; s99n vs s99w1).
    * COMMIT TAIL 005062 = mode-init dispatcher: 00515A decompresses the per-mode
      level header (table 006EFE) into FF0A50; @50AC BSR **005AE2** = load/title
      VRAM init GATED by A65 bit0 (MOVE.B (0A65),D0; ANDI #1; BEQ 005BAA skip).
      bit0=1 ⇒ pad setup + VRAM clear FF2322 + DMA 6C96 + tile decompress 1496 +
      mode re-assert 5B54. @5108 BSR 0055C6 (02BA init: clears 2B4/2B6/2BA, then
      02BA=1 iff A65 bit1).
    * TITLE DISPATCHER 005960 POLARITY CORRECTED: proceeds iff 05D4==0F AND A65
      bit0==1 AND **02BA==0** (TST; BNE→RTS) AND **0284&9==0** AND START edge
      (050C&80) ⇒ JSR 6F82. s98's "02BA!=0 gate" was inverted; 02BA=0 / 0284&9=0
      are the NORMAL interactive-title state.
    * EU CORRECTION (s98 wrong): EU sets 02BA=1 @2024 DURING mode 34 (0055F2),
      exactly like US @2049; mode-34 header byte=03 both. The mode-2 commit
      @3138-3186 then CLEARS 02BA (title header bit1=0) — correct, not the bug.
    * EU BLACK MECHANISM: boot-intro coroutine 00A2E2 yields (4970/31E0/3A14)
      until ctx+16==1, then **00A302 MOVE.W #2,(0244)** hardcoded title commit +
      0284|=5. Title header byte 0A65=0 ⇒ 005AE2 skips the VRAM init ⇒ black.
    * ATTRACT-LOOP SELECTOR DIVERGENCE: web-EU AND native-US no-input cycle
      cutscenes 34→35→36→37(→0) and never commit mode 2 without input; native-EU
      commits mode 2 after the FIRST cutscene (premature re-fade completes @2766
      → 00A302). Cutscene-end has two paths: 005AD6 MOVE (0A62),(0244) (next
      attract) vs 00A302 #2 (title). native-EU takes the title path early — the
      selector / fade-object lifecycle is the s100 fix.
    * SPLASH s54/s65 RETIRED (glue.c): 028A timeout hold, 0FE4/0FAC ack seeds,
      054C/0524/0548 idle force, iff1=1, sound_ack_note + both call sites deleted.
      Post-s97 the guest Z80 acks natively. Regression s99p: crossing
      frame-identical (flush 10411 / mode-24 10441 / exit 12707 / recommit 12738,
      lives 2) + sewers bar present; EU s99r stall unchanged. TITLE-ASSIST is now
      the ONLY env-gated boot accommodation (OFF by default since s68).
    * BAR VRAM MECHANISM: load/title VRAM init = 005AE2 (bit0-gated) → 6C96 DMA /
      1496 decompress + 0067D8 HUD staging; the assist's un-acked SFX triggered
      the 006B02 second decompress pass that perturbed the upload (RAM list
      identical native vs assisted; divergence downstream in VRAM).
    * TOOLING: s69-native.ps1 -Rom US|EU; s70-disasm.ps1/.html -Rom EU
      (web/rom/boogerman.gen.js); s99-web.ps1 (web-EU oracle dump + title flags);
      s99-noinput.input. PITFALL: web-EU no-input cycles attract indefinitely and
      the mode-2 title window is narrow/flaky under headless virtual time —
      phase-match by 0244/05D4, don't blind-sweep frames.
    * => Next: s100 = EU attract-loop selector / cutscene-end fade lifecycle (why
      native-EU takes the 00A302 title path after the first cutscene while
      web-EU/native-US cycle via 005AD6/0A62), then the title VRAM init.
  - **Session 100 (2026-11-28): EU ATTRACT SELECTOR FULLY RE'd — EARLY-EXIT =
    DEMO-PLAYER EXIT-TRIGGER COLLISION (0042F6) → 00A070 END-PHASE → C658/C69A
    HANDLER → LIVES==0 FALLTHROUGH 00A280 TITLE COROUTINE → 00A302; NORMAL END =
    DEMO STREAM EXHAUSTION (02B4==FFFF) → 005AC0/005ADE NEXT-ATTRACT. NATIVE-EU
    BLACK = DEMO MISPLAYS THE RECORDING (per-tick fidelity gap, idx 0x20-0x40) AND
    WALKS INTO THE TRIGGER; NOT lockstep/Z80-sync/edge/lives. NO ENGINE CHANGE.**
    * SELECTOR: demo feed 005A3E plays a (time,pad) recording from FFFE00[02B6]
      against the 0286 V-int counter (02B4 = next-entry schedule; 02B8 = pad →
      0502 @005A92). Stream end 02B4==FFFF → 005AC0 (02BA=FFFF, 0284|=5, 0244=
      (0A62)) = next attract (native-US 35 @3842 via 005AD6; web-EU cycles).
      Early-exit: fade-idle + 0042F6 collision (player type 0x28 overlaps trigger)
      → 00A070 (0248=0x40 re-fade, 024A) → 00A0C4 C658 → 00A1C8 → 00A23E C69A →
      00A26A lives(022E): !=0 → 00A316 commit (0256); ==0 → 00A280 spawn (150f
      countdown) → 00A302 #2 + 0284|=5 @3138.
    * ROOT CAUSE: native-EU demo player deviates from web-EU between idx 0x20
      (X=0x331 @2319, equal) and idx 0x40 (native X=0x2A6 @2415 vs web X=0x284
      @2440 at the SAME idx and SAME 0286≈0xC6) → grounded player collides with
      the exit trigger @2440 → premature title over cutscene VRAM (header bit0=0
      skips 005AE2) → black. web-EU/native-US play the full recording → 005AC0.
    * REJECTED: lives branch (022E=0 in web-EU and native-US too); -NoLockstep
      (s100u) and -NoZ80Sync (s100v) reproduce the identical premature title;
      missed pad edge (050C forms B-edges @2329/2364/2415, s100x). The ~25f
      web-vs-native offset is boot-phase jitter; counters phase-match at equal
      idx. Residual = genuine per-tick demo-playback fidelity gap.
    * TITLE-VRAM: authentic EU mode-2 header bit0=0 too ⇒ 005AE2 skip is authentic;
      the rendered title comes from a title-tile upload path (intro-scroll commit
      015650 / title-object upload), not the post-cutscene 00A302 over cutscene
      VRAM. s101 to confirm which upload renders the web title and restore it.
    * TOOLING: s98-brascan.ps1 / s96-callscan.ps1 -Rom US|EU; s69-native.ps1
      -NoLockstep / -NoZ80Sync / -NoBootAssist bisect switches. s100a-x taps/disasm.
    * => Next: s101 = per-V-int pad/physics cosim of the EU demo idx 0x20-0x40
      window (cosim.c infra) to find the divergent action, then engine fix (A) or
      env-gated EU attract/title assist (B); confirm the authentic title upload.
  - **Session 101 (2026-11-28): PER-TICK COSIM LOCALIZES THE EU DEMO GAP TO A ~2x
    PLAYER-INTEGRATION RATE PER V-INT (moving entries idx 0x20-0x40); SCHEDULE +
    PAD DATA BYTE-IDENTICAL. ENV-GATED BACKUP B (GENESIS_EU_ATTRACT_ASSIST, OFF
    DEFAULT) REDIRECTS THE PREMATURE 00A302 TITLE COMMIT TO NEXT-ATTRACT —
    RESTORES THE MODE CYCLE BUT NOT THE RENDERED IMAGE (early-exit teardown
    persists). US REGRESSION CLEAN.**
    * METHOD: web/test/ram-trace.html (per-frame guest-word sampler) + s101-web.ps1
      vs native OBJ-TL (s101a), aligned by stream idx (02B6) with s101-diff.ps1.
      X = word FF1A32 (1A34 = X+24 collision edge); Y = FF1A2E.
    * FINDING: 02B4-vs-0286 entry schedule and 02B8 pad identical native/web at
      every idx. But during MOVING entries native 0286 advances +1/tick while web
      +1/2 ticks (idle idx1c both +1/2) => native integrates player motion ~2x per
      V-int, overshooting to X=02a9 and stalling into the exit trigger (web stays
      0284/025e). Early-exit 00A070 then zeroes 0266/0240/0241 + re-fade 0248=40,
      tearing down cutscene state => black even when the commit is redirected.
    * BACKUP B (glue.c m68k_write16, env-gated OFF): PC==00A302 && addr==0244 &&
      val==2 && 02BA!=0 => val=(0A62). s101b: premature commit now writes 35, cycle
      34->35->..->37 via 005ADE; NO mode-2. But frames stay black (cutscene bit0=0
      skips 005AE2 VRAM init after teardown) => render fix still open.
    * US REGRESSION s101us (assist OFF): flush 10411 / mode-24 10441 / lives 2,
      sewers HUD bar present. No change to the playable path.
    * TOOLING: web/test/ram-trace.html; native/tools/s101-web.ps1, s101-diff.ps1;
      s69-native.ps1 -EuAttractAssist.
    * => Next: s102 = correct the ~2x demo-player per-V-int pacing (A) OR prevent
      the early-exit teardown so the EU attract cycle RENDERS (not just commits);
      confirm the authentic title-tile upload.
  - **Session 102 (2026-11-28): CORRECTS s101 — THE 0286 ENTRY TIMER RATE IS
    IDENTICAL NATIVE/WEB; THE MISPLAY IS A 2x HORIZONTAL INTEGRATION (0027DC add +
    0045F0 adjust) PLUS A MISSED VELOCITY RESET. RENDER BLACK IS UPSTREAM CUTSCENE
    UPLOAD/DISPLAY (present MID-demo, pre-exit), NOT THE TEARDOWN — B+ TEARDOWN
    NO-OP TESTED AND REVERTED. NO NET ENGINE CHANGE. US REGRESSION CLEAN.**
    * METHOD: extended-word cosim (s102c native OBJ-TL + s102w web trace adding
      FF1A40/44/48/4A velocity words) + disasm 000760-000860 / 0026D4-002800.
    * CORRECTION: 0286 is ADDI #1 at 0007E6 inside the main loop, which completes
      once per TWO V-ints (two 0516 phase waits at 000786/0007C2). Its rate matches
      web (+1/2 V-int) everywhere; s101's "0286 +1/tick" was a t-column artifact.
    * FINDING: 002752 loops object ctxs; 0026D4 clamps X-vel (54)=FF1A44 by
      (58)=FF1A48 and feeds X-impulse (50)=FF1A40; 002752 ASR#8 adds to X
      (36)=FF1A32, then 0045F0 (collision/adjust) snaps X back. During idx08
      c286>=0x12 native nets -3/iteration vs web -1.5/iteration (2x horizontal);
      native also misses web's X-vel reset 0600->0480 at c286=0x18. Net: persistent
      ~7px Y offset + X path diff -> native stalls X=02a9 into the exit trigger at
      idx40 while web passes at 0284. Root = EU demo-player physics/adjust fidelity
      (0026D4/002752/0045F0 + object routine 008xxx), engine/recomp-side.
    * RENDER: s102f mid-demo frame (f2150, BEFORE early-exit) is BLACK => the attract
      scene never uploads/displays natively; black is upstream cutscene VRAM/VDP
      display, not the 00A070 teardown. s102e tested a B+ no-op of the teardown
      re-fade (00A0A0 MOVE #40,(0248)): ineffective, REVERTED. Backup B (cycle
      redirect) remains the only assist; glue.c net-unchanged from s101.
    * US REGRESSION s102us (assist OFF): flush 10411 / mode-24 10441 / exit 12707 /
      recommit 12738 / lives 2; sewers HUD bar present (score 001730).
    * => Next: s103 = (a) fix the 2x horizontal adjust + missed vel reset fidelity;
      (b) probe upstream cutscene upload / VDP display-enable (native DUMP_VRAM
      mid-demo) to make the EU attract scene render.
  Next experiments (anticipated, in order):
  1. EU attract fidelity + render (s103): s102 corrected the gap to a 2x horizontal
     integration (0027DC+0045F0) and a missed X-vel reset at c286=0x18, and showed
     the render black is upstream cutscene upload/display (mid-demo black), not the
     teardown. (a) Single-step the EU demo-player adjust (0045F0 / object 008xxx) to
     fix the 2x + reset; (b) DUMP_VRAM mid-demo native vs web to locate the missing
     cutscene tile upload / VDP display-enable so the attract scene renders.
  2. M3 sound/Z80 RE to retire assists: A65 status source block (143C copy), 284
     service tick/acks (2B6 pad history wrap), 054C/0524/0548, Z80 iff1/$0038
     handler; retire the s59/s60/s61/s62 emulations; audio fidelity.
  3. M3 RAM map: identify `player_object`/`level_modes` from gameplay-phase RAM diffs.
  4. M4 polish; M5 Linux/Steam Deck build (gcc/ninja/SDL2, gamescope), controller map.
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

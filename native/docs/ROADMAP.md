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
  Next experiments (anticipated, in order):
  1. Resolve the boot main-loop wait-for-$FF0516 (label_000786): identify the V-int
     write that first sets mode non-zero and its Z80 gate (sound-started flag, e.g.
     $0FE4), or correct 68K/V-int read ordering; re-test Start→game. (dedicated effort)
  2. Once interactive: input-script route validation (Start → level 1) vs web oracle.
  3. M3 RAM map: `player_object`/`level_modes` from gameplay RAM diffs.
  4. M4 polish; M5 Linux/Steam Deck build (gcc/ninja/SDL2, gamescope), controller map.
  2. Once interactive: input-script route validation (Start → level 1) vs web oracle;
     verify scrolling/collision/transitions; audio check.
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

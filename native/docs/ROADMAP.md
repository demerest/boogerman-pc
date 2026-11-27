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
  Next experiments (anticipated, in order):
  1. Level-world load (s63): identify the 143C copy source buffer and the stager
     that fills it (jsr/b sr callers of 142C; level-header decompress 1496 family,
     sound-ack gated). Fix the ack (M3) OR env-gated assist-seed the header/spawn
     params (0A58=b4/0A5A=91/0A5C=2e) so obj0=5452; then validate mode-10 scroll,
     player object, collision, transitions vs web (Start route, phase-matched).
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

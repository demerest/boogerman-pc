/* Boogerman (U) game adapter — NTSC profile.
 *
 * Vectors from the US ROM header: reset PC $000210, IRQ6 (VBlank) $004DF0,
 * IRQ4 (HBlank) $006BDE. Identity: CRC32 1A7A2BEC, size 3145728,
 * SHA-1 bb1d23ca4c48d37bf3170d320cc30bfbc2acdfff, header checksum 8BD9.
 * RAM layout starts from the EU map (same reset/VBlank addresses);
 * gameplay addresses to be re-verified in M3.
 */
#include "game_spec.h"
#include "genesis_runtime.h"
#include "genesis_machine.h"
#include "boogerman_us_decls.h"

/* Entry/IRQ must go through recomp_call_addr: it owns a dispatch frame,
 * without which any recompiled tail call (JMP) aborts (exit 2). */
static void boogerman_entry(void)  { recomp_call_addr(0x000210u); }
static void boogerman_vblank(void) { recomp_call_addr(0x004DF0u); }
static void boogerman_hblank(void) { recomp_call_addr(0x006BDEu); }

/* Mirror Sonic 1's on_post_reset sound seed: the boot sound-init handshake
 * needs the Z80 vblank/DAC flags before the first V-int; seed them at reset so
 * the boot main loop completes title init instead of stalling. */
static void boogerman_post_reset(void) {
    extern GenesisMachine g_machine;
    g_machine.bus.z80_ram[0x0FAD] = 0xFE;
    g_machine.bus.z80_ram[0x0FC2] = 0x01;
}

const GameSpec g_game_spec = {
    .video = NULL,
    .video_default = NULL,
    .logical_players = 1,
    .display_name = "Boogerman: A Pick and Flick Adventure (US)",
    .short_name = "BoogermanUS",
    .boxart = NULL,
    .expected_rom_crc32 = 0x1A7A2BECu,
    .expected_rom_size = 3145728u,
    .rom_aliases = NULL,
    .num_rom_aliases = 0,
    .tier3_floor_default = 1,
    .z80_step = NULL,
    .sram_start = 0,
    .sram_end = 0,
    .call_entry_point = boogerman_entry,
    .call_vblank = boogerman_vblank,
    .call_hblank = boogerman_hblank,
    .resume_main_loop_pc = 0,
    .dispatch_main_loop_pc = 0,
    .on_post_reset = boogerman_post_reset,
};

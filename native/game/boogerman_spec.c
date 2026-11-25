/* Boogerman (EU) game adapter — minimal GameSpec for first native boot.
 *
 * Entry/IRQ addresses from the ROM vector table:
 *   reset PC $000210, IRQ6 (VBlank) $004DF0, IRQ4 (HBlank) $006C14.
 * RAM layout (see game.toml): VBlank counter word $FF0288, VBlank routine
 * index word $FF0516, stack $FF0200.
 *
 * tier3_floor_default=1: unresolved dynamic dispatch executes on the
 * clean-room interpreter and feeds coverage leads back for the next regen.
 */
#include "game_spec.h"
#include "genesis_runtime.h"
#include "boogerman_decls.h"

static void boogerman_entry(void)  { func_000210(); }
static void boogerman_vblank(void) { func_004DF0(); }
static void boogerman_hblank(void) { func_006C14(); }

const GameSpec g_game_spec = {
    .video = NULL,                  /* native VDP presentation only */
    .video_default = NULL,
    .logical_players = 1,
    .display_name = "Boogerman: A Pick and Flick Adventure",
    .short_name = "Boogerman",
    .boxart = NULL,
    .expected_rom_crc32 = 0xDBC4340Cu,
    .expected_rom_size = 3145728u,
    .rom_aliases = NULL,
    .num_rom_aliases = 0,
    .tier3_floor_default = 1,
    .z80_step = NULL,               /* shared SuperZazu Z80 backend */
    .sram_start = 0,
    .sram_end = 0,
    .call_entry_point = boogerman_entry,
    .call_vblank = boogerman_vblank,
    .call_hblank = boogerman_hblank,
    .resume_main_loop_pc = 0,
    .dispatch_main_loop_pc = 0,
};

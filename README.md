# boogerman-pc

Two ports of the same owned cartridge dump (`Boogerman (E) [!].gen`, EU/PAL):

| Directory | What | Status |
|---|---|---|
| [`web/`](web/README.md) | Browser port framework: Genesis Plus GX WASM core + enhancement shell (shaders, mods, cheats, states, RAM workbench). Double-click `web/index.html`. | Complete, 53/53 tests pass |
| [`native/`](native/README.md) | **Native PC / Steam Deck port** via static recompilation (segagenesisrecomp): 68000 → C → native executable, clean-room hardware runtime. | Exploring: first codegen pass done (245 native functions); roadmap in `native/docs/ROADMAP.md` |

The web port doubles as the validation oracle for the native port.

**Legal:** personal use of your own dump only. Core/framework licenses are
non-commercial; the game is © Interplay. Never redistribute ROMs or generated
game code. See `web/LICENSES.md` and `native/README.md`.

# 02 — DKEU Integration (macro layer only)

**What**: layer [Demon Klipper Essentials Unified](https://github.com/3DPrintDemon/Demon_Klipper_Essentials_Unified)
onto the mainline install — his START_PRINT orchestration (heat soak, QGL, adaptive
mesh, purge), tuning menus, and quality-of-life macros.
**Why here in the sequence**: after the 01 smoke test (so a regression has an obvious
suspect: this integration) and before the full validation battery (so doc 03 tests
the FINAL macro stack once, not twice).
**Why DKEU at all**: three years of community-tested print orchestration we'd
otherwise reinvent badly; its own docs target exactly our current state (SV08 MAX,
mainline, eddy-ng, stock toolhead); active Discord support.
**Changes**: config/macros only. No firmware, no hardware. Rollback = remove the
includes.

## Prerequisites

- [ ] Doc 01 complete including smoke test
- [ ] Skim DKEU's install docs + the SV08 MAX extra-instructions page (they evolve;
      the repo is authoritative over this doc)

## A. Install

1. [ ] Follow DKEU's installer/README for the base install (clone into config,
       add its includes and the moonraker `update_manager` entry so it stays
       current).
2. [ ] Per Demon's mainline-MAX guide: **disable the obsolete macro in the DKEU
       custom_expansion file** (his guide links it; it exists for the stock Sovol
       vir-contact stack we don't run).

## B. Resolve the macro collisions (verified map, 2026-07-08)

*Why this matters: Klipper errors on duplicate macro names, and both stacks define
some of the same ones. The rule of thumb: DKEU owns ORCHESTRATION, we own the
FEEDER and PLR.*

| Macro | Owner | What to do |
|---|---|---|
| `PAUSE` / `RESUME` / `CANCEL_PRINT` | ours | Nothing — DKEU doesn't define them. Our feeder-aware versions (MANUAL_FEED on resume, LED/flag handling, filament-change unload) stay. |
| `M106` / `M107` | ours | Nothing — no DKEU definitions. Stock dual-fan mapping stays (this stage still has two part-cooling fans). |
| `PRINT_START` / `START_PRINT` | **DKEU** | Their orchestration wins. Move our hooks out of `plr.cfg`'s PRINT_START into DKEU's user-hook files (`Demon_User_Files`): `save_last_file`, `SAVE_VARIABLE VARIABLE=was_interrupted VALUE=True`, `BUFFER_SYNC` (synced variant), `UPDATE_DELAYED_GCODE ID=plr_journal DURATION=5`. Then neuter our `[gcode_macro PRINT_START]` (or rename it `_OUR_PRINT_START_HOOKS` and call it from the DKEU hook). |
| `PRINT_END` | **DKEU** | Same: journal stop, `was_interrupted=False`, `BUFFER_DESYNC`, `plr_clear`, `clear_last_file` into their end-hooks. |
| `LOAD_FILAMENT` / `UNLOAD_FILAMENT` | **ours** | Buffer choreography must win (paired feeder moves / sync-unload). Disable or rename DKEU's versions — check whether DKEU offers a config switch first; otherwise comment their definitions out of its includes (note it for DKEU updates). |
| `M600` | **ours** | The 1100mm runout tail chain (`CONTINUE_PRINT_D` → `M600` → filament-change pause) depends on our version. Disable DKEU's. |

3. [ ] Apply the table. Restart klippy after each change; a duplicate-section error
       names the exact collision you missed.
4. [ ] **Slicer start/end gcode switches to DKEU's calls** (their documented
       parameters for bed/hotend temps etc.). *Our PLR slicer contract rode on
       PRINT_START/PRINT_END names — the hooks moved in step B, so DKEU's call IS
       the contract now.*

## C. Smoke (gate to doc 03)

- [ ] One small print via DKEU's full START_PRINT flow completes
- [ ] `saved_variables.cfg` shows a fresh `plr_state` during the print and
      `was_interrupted = False` after it (*proves the hooks moved correctly*)
- [ ] Feeder synced/fed during the print; LEDs behaved
- [ ] `UNLOAD_FILAMENT` runs OUR choreography (feeder moves visibly paired)

## Known follow-up

After the toolhead swap (doc 04): a DKEU re-tune pass — purge/park coordinates and
any probe-adjacent settings move with the new geometry. Also drop the `M106`/`M107`
mapping when the single-`[fan]` toolhead config takes over.

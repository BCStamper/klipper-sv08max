# 02 — DKEU Integration (macro layer only)

**What**: layer [Demon Klipper Essentials Unified](https://github.com/3DPrintDemon/Demon_Klipper_Essentials_Unified)
onto the mainline install — his START_PRINT orchestration (heat soak, QGL, adaptive
mesh, purge), tuning menus, and quality-of-life macros.
**Why here in the sequence**: after the 01 smoke test (so a regression has an obvious
suspect: this integration) and before the full validation battery (so doc 03 tests
the FINAL macro stack once, not twice).
**Why DKEU at all**: three years of community-tested print orchestration we'd
otherwise reinvent badly; its own docs target our exact printer (SV08 MAX,
mainline, stock toolhead); active Discord support. **One real deviation from
DKEU's own SV08 MAX guide: we run `probe_eddy_current` (object name `eddy`), not
eddy-ng.** Confirmed via direct source read (not the doc's own description of
itself) that nothing in DKEU hard-depends on eddy-ng — `demon_mesh_builder`
explicitly recognizes `probe_eddy_current eddy` as first-class, `demon_z_calibration`
already branches correctly for it too. Full finding in `01-DIVERGENCES.md`.
**Changes**: config/macros only. No firmware, no hardware. Rollback = remove the
includes.

## Prerequisites

- [ ] Doc 01 complete including smoke test
- [ ] Skim DKEU's install docs + the SV08 MAX extra-instructions page (they evolve;
      the repo is authoritative over this doc) — but read **section B below**
      first, several of that page's steps don't apply to us or need reconciling,
      not pasting
- [ ] Skim `01-DIVERGENCES.md` for the eddy-ng/probe_eddy_current context above

## A. Install

1. [ ] Follow DKEU's installer/README for the base install (clone into config,
       add its includes and the moonraker `update_manager` entry so it stays
       current).
2. [ ] Per Demon's mainline-MAX guide: **disable the obsolete macro in the DKEU
       custom_expansion file** (his guide links it; it exists for the stock Sovol
       vir-contact stack we don't run).

## B. SV08 MAX-specific reconciliation (read before touching Demon's guide)

*Why this section exists: Demon's SV08 MAX extra-instructions page is written for
someone starting from stock Sovol firmware. We're not that — doc 01 already made
several deliberate changes his guide assumes haven't happened yet. Diff his
suggested blocks against what's already in `printer-stock-toolhead.cfg` before
pasting anything from his page; don't apply it verbatim.*

- [ ] **Skip the entire "Use Your SV08 Max WITH/WITHOUT The Sovol Filament
      Buffer/Feeder" + "THE TRICKY SSH BIT" sections of his guide.** They walk
      you through replacing `buffer_stepper.py`, `filament_switch_sensor.py`, and
      `z_offset_calibration.py` with his versions — files from a module
      (`buffer_stepper.py`) we deliberately don't run at all (doc 01: pure-config
      `buffer-synced.cfg`, an `[extruder_stepper filament_buffer]`, not
      `[buffer_stepper filament_buffer]`). Confirmed via source read (2026-07-27):
      DKEU's own buffer-aware macros (`demon_clean_load.cfg` etc.) all gate on
      `'buffer_stepper filament_buffer' in printer.configfile.config` — a
      different config section type than ours, so that check evaluates False for
      us and DKEU's buffer logic safely no-ops. Our `LOAD_FILAMENT`/
      `UNLOAD_FILAMENT`/buffer choreography (section C below) is the only buffer
      logic that runs — no conflict, but also none of DKEU's buffer conveniences
      (e.g. the auto-grab-on-insert feature his guide describes) without
      building that ourselves against our own architecture later. Also skip his
      `z_offset_calibration.py` swap and the `center_xy_position` comment-out
      step entirely — we don't run that module (switched to
      `PROBE_EDDY_CURRENT_CALIBRATE` in doc 01), so nothing there applies.
- [ ] **`[stepper_z]` `position_min` is currently `-10`**, inherited verbatim
      from Sovol stock. Demon's guide flags this exact value as unsafe and
      recommends `-1.5` — it's the software floor limiting how far a bad-homing
      event can drive the nozzle into the bed (directly relevant to the
      2026-07-26 Z-crash). **Not resolved here — size the right value with Ben
      first** (needs to leave room for real babystepping/offset range), then
      edit deliberately. Tracked, not gating doc 02.
- [ ] **Fan/LED sections**: Demon's guide suggests merging front+back
      part-cooling into one `[fan]` via `multi_pin` plus a `[led]` object. We
      already deliberately kept them as separate `fan_generic fan0`/`fan1` (see
      the `M106`/`M107` row below) — don't paste his fan/LED blocks over ours.
- [ ] **`[printer]` acceleration**: Demon's guide sets `max_accel: 5500` for this
      exact stock toolhead. Ours is currently `20000` (doc 01's comment notes
      this is provisional — "start at 20k on mainline, raise after shakedown").
      A 3.6x gap on the same hardware is worth a real look, but it's a
      print-quality/reliability tuning question for doc 03's shakedown, not
      something to silently overwrite by pasting his `[printer]` block here.
- [ ] `[resonance_tester]` already matches his recommended full-range settings
      (`lis2dw`, no artificial frequency cutoffs) — no change needed.

## C. Resolve the macro collisions (verified map, 2026-07-08)

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

1. [ ] Apply the table. Restart klippy after each change; a duplicate-section error
       names the exact collision you missed.
2. [ ] **Slicer start/end gcode switches to DKEU's calls** (their documented
       parameters for bed/hotend temps etc.). *Our PLR slicer contract rode on
       PRINT_START/PRINT_END names — the hooks moved in the table above, so
       DKEU's call IS the contract now.*

## D. Smoke (gate to doc 03)

- [ ] One small print via DKEU's full START_PRINT flow completes
- [ ] `saved_variables.cfg` shows a fresh `plr_state` during the print and
      `was_interrupted = False` after it (*proves the hooks moved correctly*)
- [ ] Feeder synced/fed during the print; LEDs behaved
- [ ] `UNLOAD_FILAMENT` runs OUR choreography (feeder moves visibly paired)
- [ ] **Check whether DKEU's post-homing offset correction actually fires for us.**
      `demon_homing_control`'s finishing branch after `G28 Z` only checks for
      object name `probe_eddy_current btt_eddy` — not `eddy`, which is what ours
      is actually named (`demon_z_calibration` checks both names; this file only
      checks one — looks like an oversight, not intentional). If it doesn't fire,
      we silently fall through to a plain park with no extra `PROBE` +
      `SET_Z_FROM_PROBE` sample. Watch Z repeatability/first-layer consistency
      across a few homes; if it looks off, either rename our object to `btt_eddy`
      or patch `demon_homing_control`'s condition to also check
      `probe_eddy_current eddy`, matching `demon_z_calibration`'s pattern.

## Known follow-up

After the toolhead swap (doc 04): a DKEU re-tune pass — purge/park coordinates and
any probe-adjacent settings move with the new geometry. Also drop the `M106`/`M107`
mapping when the single-`[fan]` toolhead config takes over.

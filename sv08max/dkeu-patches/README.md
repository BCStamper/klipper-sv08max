# DKEU patch backups

These are reference copies of files inside `Demon_Klipper_Essentials_Unified` and
`Demon_User_Files` that were patched directly on the live printer. **They are not
auto-deployed anywhere** — DKEU is its own separate git clone under
`~/printer_data/config/Demon_Klipper_Essentials_Unified/` on the printer, entirely
outside this repo's tracked files. If that clone is ever updated or reset (a
manual `git pull`, a fresh KIAUH install, etc.), these patches are silently lost
with no record anywhere but here — reapply them by hand from this reference.

**Confirmed twice now, not hypothetical.** A full DKEU v3.2.2 reinstall (fresh
`git clone` of `Demon_Klipper_Essentials_Unified`, `Demon_User_Files`
archived-then-replaced rather than diff-merged) has now silently wiped local
patches on **two separate occasions** (2026-08-19 alone saw the
`demon_homing_control` patch wiped and reapplied within the same day — first
originally on 2026-07-27, wiped by that day's reinstall, reapplied same day).
Files inside `Demon_Klipper_Essentials_Unified` proper are not preserved in any
form; files inside `Demon_User_Files` at least get archived to
`Previous_Versions/` first, so they're recoverable, but the live copy still
resets to template defaults. **After any future DKEU reinstall or update, diff
every file below against the live copy before trusting anything.** Full incident
account for the 2026-08-19 reinstall (and everything it triggered downstream):
`sv08max/docs/02-DIVERGENCES.md`.

## `demon_homing_control_v2.1.2.cfg` — ACTIVE, reapplied 2026-08-19
Two patches, both in the `probe_eddy_current` homing branch:
1. Widened the post-G28 offset-correction condition to also check object name
   `eddy` (upstream only checked `btt_eddy`, which isn't our object's name) —
   without this, the `SET_Z_FROM_PROBE` refinement step is silently skipped
   entirely, falling through to a bare `_Z_PARK` with no additional Z read.
2. Removed a redundant bare `PROBE` call that duplicated `SET_Z_FROM_PROBE`'s
   own internal probe — the two ran back-to-back with no retract between them,
   causing "Probe triggered prior to movement" on every homing pass.
3. The post-`G28 Z` clearance lift before `SET_Z_FROM_PROBE` (`G0 Z10` →
   `G0 Z3` + `M400` + a short dwell) — 10mm exceeded the eddy probe's actual
   calibrated range (0.05–4.05mm); see `02-DIVERGENCES.md`.
See the in-file comments (patches 1–2 dated 2026-07-27, reapply note and patch 3
added 2026-08-19). Wiped by the 2026-08-19 reinstall, reapplied same day after it
caused a missing-refinement regression on the first real post-reinstall print
attempt. This tracked copy also had temporary diagnostic `RESPOND` instrumentation
added and removed within the same 2026-08-19 session — the version here is
already clean (diagnostics-free); only the live printer copy needed the same
cleanup afterward.

## `demon_clean_load_v2.1.2.cfg` — RETIRED 2026-08-19, do not reapply
Historical patch: both `LOAD_FILAMENT` and `UNLOAD_FILAMENT` sections were
commented out (2026-08-03) because DKEU's versions had no awareness of our old
extruder_stepper-based filament buffer and would grind cold filament in its
gears. **The buffer was shelved entirely on 2026-08-19** (junction-velocity
problem in Klipper's lookahead planner, unfixable via config — see project
memory) — that risk no longer exists. The 2026-08-19 reinstall wiped this patch
too (restoring DKEU's stock LOAD_FILAMENT/UNLOAD_FILAMENT), but this time
correctly: DKEU's stock macros are now the right thing to run. Kept here for
history only.

## `demon_custom_expansion_v2.0.0.cfg` — ACTIVE, rebuilt 2026-08-19
Lives in `Demon_User_Files`, so the 2026-08-19 reinstall archived the prior
version to `Previous_Versions/` rather than silently discarding it — but still
reset the live file to the pristine template, dropping real customizations.
Two patches, both from the same day:
1. `_CUSTOM_PRE_START` and `_CUSTOM_POST_END` carry the PLR (power-loss
   recovery) integration hooks that `sv08max/plr.cfg`'s own header documents as
   its required contract (`save_last_file`/`was_interrupted`/`plr_journal` on
   start, matching stop/clear on end) — restored after the reinstall wiped
   them, along with `ceal_master_enable`/`pre_start`/`post_end` all having
   reverted to `False` (which would have silently disabled the hooks even with
   the gcode restored). The old BUFFER_SYNC/BUFFER_DESYNC-era history in this
   section (2026-08-04) is moot now that the buffer is gone entirely — no
   buffer-related code remains in this file's custom hooks.
2. `_CUSTOM_PRE_LEVEL`'s `_OFFSET_FORCE_OVERLAY` call — added per DKEU's SV08
   MAX doc (marked "REQUIRED" there), then **reverted the same day**: it
   unconditionally calls `RUN_PROBE_VIR_CONTACT` (a Sovol-vendor
   eddy-ng-fork-specific command, confirmed not to exist in mainline
   `probe_eddy_current`) and `CLEAN_NOZZLE` (unconditional, no
   `hardware_vars.nozzle_cleaner` guard). `variable_pre_level` set back to
   `False`. Full reasoning in `02-DIVERGENCES.md`.

## `demon_core_assets_v2.3.5.cfg` — STALE, superseded by the 2026-08-19 reinstall
Historical patches (both now moot, kept for history only — **do not reapply**):
1. `[gcode_macro M600]` comment-out (2026-08-16) — was shadowing our own M600
   in `sv08max/macros.cfg`. `macros.cfg` is no longer included at all as of
   2026-08-19 (buffer shelved, clean DKEU baseline decision), so there's
   nothing left for DKEU's own M600 to shadow.
2. `_DEMON_START_WATCHER` missing `{% set svv = ... %}` line (2026-08-17) —
   confirmed independently fixed upstream in the current release
   (`demon_core_assets_v2.3.7.cfg`, checked 2026-08-19 before the reinstall).
The live file is now tracked as `demon_core_assets_v2.3.7.cfg` (below), with its
own, unrelated set of active patches.

## `demon_core_assets_v2.3.7.cfg` — ACTIVE, added 2026-08-19
Three patches, all part of the same eddy-probe-range mismatch documented in full
in `02-DIVERGENCES.md`:
1. `_QGL`'s three `horizontal_move_z` overrides — coarse round (10mm), fine
   round (6mm), and the eddy-ng-specific branch (8mm, not our actual code path
   but fixed for consistency) — all lowered to 3mm.
2. `_SET_Z_PARK`'s `probe_eddy_current`/`mcu eddy` branch — `z_park` lowered
   from 15mm to 3mm.
3. `_CORE_VARS`' raw `variable_z_park` file-level default — lowered from 30mm
   to 3mm. This is the value anything reads if it queries `core_vars.z_park`
   before `_SET_Z_PARK` has run once in a session, which is exactly what
   `demon_bed_checker_heat_soak`'s heat-soak/ref_point monitoring does (it runs
   before the main Z-homing sequence).
All three were hitting the same wall: mainline `probe_eddy_current`'s
calibration table only covers 0.05–4.05mm, and any of these heights sent the
toolhead's commanded Z outside that window during a probe operation.

## `demon_user_settings_v3.1.2.cfg` — ACTIVE, added 2026-08-19
Two patches:
1. `variable_runout_sensor` was left `True` from before the buffer removal
   (which took the bundled `[filament_switch_sensor filament_sensor]` with it)
   and never updated to match. `_RUNOUT_SENSOR_CHECK` itself is correctly
   guarded on this flag — the crash only happens because the flag no longer
   matches reality, not because the macro is broken. Flip back to `True` once
   the Orbiter sensor is installed and a real `[filament_switch_sensor
   filament_sensor]` section exists again.
2. `variable_pre_home_lift` lowered from 20mm to 3mm — same eddy-probe-range
   mismatch as the `demon_core_assets_v2.3.7.cfg` patches above. At 20mm,
   `G28 Z`'s homing search started its descent from well outside the
   calibrated window and hard-failed with "probe_eddy_current sensor not in
   valid range" on every attempt.

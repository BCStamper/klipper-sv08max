# DKEU patch backups

These are reference copies of files inside `Demon_Klipper_Essentials_Unified` and
`Demon_User_Files` that were patched directly on the live printer. **They are not
auto-deployed anywhere** — DKEU is its own separate git clone under
`~/printer_data/config/Demon_Klipper_Essentials_Unified/` on the printer, entirely
outside this repo's tracked files. If that clone is ever updated or reset (a
manual `git pull`, a fresh KIAUH install, etc.), these patches are silently lost
with no record anywhere but here — reapply them by hand from this reference.

**Confirmed 2026-08-19: this isn't hypothetical.** A full DKEU v3.2.2 reinstall
(fresh `git clone` of `Demon_Klipper_Essentials_Unified`, `Demon_User_Files`
archived-then-replaced rather than diff-merged) silently wiped every patch below
that lived inside `Demon_Klipper_Essentials_Unified` proper — same version
numbers, patches just gone. Files inside `Demon_User_Files` at least get archived
to `Previous_Versions/` first, so they're recoverable; files directly inside
`Demon_Klipper_Essentials_Unified` are not preserved in any form. **After any
future DKEU reinstall or update, diff every file below against the live copy
before trusting anything.**

## `demon_homing_control_v2.1.2.cfg` — ACTIVE, reapplied 2026-08-19
Two patches, both in the `probe_eddy_current` homing branch:
1. Widened the post-G28 offset-correction condition to also check object name
   `eddy` (upstream only checked `btt_eddy`, which isn't our object's name) —
   without this, the `SET_Z_FROM_PROBE` refinement step is silently skipped
   entirely, falling through to a bare `_Z_PARK` with no additional Z read.
2. Removed a redundant bare `PROBE` call that duplicated `SET_Z_FROM_PROBE`'s
   own internal probe — the two ran back-to-back with no retract between them,
   causing "Probe triggered prior to movement" on every homing pass.
See the in-file comments (dated 2026-07-27, reapply note added 2026-08-19).
Wiped by the 2026-08-19 reinstall, reapplied same day after it caused a
missing-refinement regression on the first real post-reinstall print attempt.

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
Current patch: `_CUSTOM_PRE_START` and `_CUSTOM_POST_END` carry the PLR
(power-loss recovery) integration hooks that `sv08max/plr.cfg`'s own header
documents as its required contract (`save_last_file`/`was_interrupted`/
`plr_journal` on start, matching stop/clear on end) — restored after the
reinstall wiped them, along with `ceal_master_enable`/`pre_start`/`post_end`
all having reverted to `False` (which would have silently disabled the hooks
even with the gcode restored). The old BUFFER_SYNC/BUFFER_DESYNC-era history in
this section (2026-08-04) is moot now that the buffer is gone entirely — no
buffer-related code remains in this file's custom hooks.

## `demon_core_assets_v2.3.5.cfg` — STALE, superseded by the 2026-08-19 reinstall
Historical patches (both now moot, kept for history only — **do not reapply**):
1. `[gcode_macro M600]` comment-out (2026-08-16) — was shadowing our own M600
   in `sv08max/macros.cfg`. `macros.cfg` is no longer included at all as of
   2026-08-19 (buffer shelved, clean DKEU baseline decision), so there's
   nothing left for DKEU's own M600 to shadow.
2. `_DEMON_START_WATCHER` missing `{% set svv = ... %}` line (2026-08-17) —
   confirmed independently fixed upstream in the current release
   (`demon_core_assets_v2.3.7.cfg`, checked 2026-08-19 before the reinstall).
The live file is now `demon_core_assets_v2.3.7.cfg`, untouched/unpatched.

## `demon_user_settings_v3.1.2.cfg` — ACTIVE, added 2026-08-19
`variable_runout_sensor` was left `True` from before the buffer removal (which
took the bundled `[filament_switch_sensor filament_sensor]` with it) and never
updated to match. `_RUNOUT_SENSOR_CHECK` itself is correctly guarded on this
flag — the crash only happens because the flag no longer matches reality, not
because the macro is broken. Flip back to `True` once the Orbiter sensor is
installed and a real `[filament_switch_sensor filament_sensor]` section exists
again.

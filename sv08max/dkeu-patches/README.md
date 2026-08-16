# DKEU patch backups

These are reference copies of files inside `Demon_Klipper_Essentials_Unified` and
`Demon_User_Files` that were patched directly on the live printer. **They are not
auto-deployed anywhere** — DKEU is its own separate git clone under
`~/printer_data/config/Demon_Klipper_Essentials_Unified/` on the printer, entirely
outside this repo's tracked files. If that clone is ever updated or reset (a
manual `git pull`, a fresh KIAUH install, etc.), these patches are silently lost
with no record anywhere but here — reapply them by hand from this reference.

## `demon_homing_control_v2.1.2.cfg`
Two patches, both in the `probe_eddy_current` homing branch:
1. Widened the post-G28 offset-correction condition to also check object name
   `eddy` (upstream only checked `btt_eddy`) — see the in-file comment dated
   2026-07-27.
2. Removed a redundant bare `PROBE` call that duplicated `SET_Z_FROM_PROBE`'s
   own internal probe — the two ran back-to-back with no retract between them,
   causing "Probe triggered prior to movement" on every homing pass. See the
   in-file comment dated 2026-07-27.

## `demon_clean_load_v2.1.2.cfg`
Both `LOAD_FILAMENT` and `UNLOAD_FILAMENT` sections commented out (search
"DISABLED 2026-08-03"). Both were silently shadowing our own versions in
`sv08max/buffer-synced.cfg` and `sv08max/macros.cfg` — same last-file-wins class
as the `PRINT_START` shadow, just never verified for this pair. DKEU's versions
have no buffer awareness at all (gate on a config section type we don't use).

## `demon_custom_expansion_v2.0.0.cfg`
`_CUSTOM_PRE_START` and `_CUSTOM_POST_END` had their `BUFFER_SYNC`/`BUFFER_DESYNC`
calls removed (search "removed 2026-08-04"). These were correct when
`BUFFER_SYNC` didn't exist at all (their `is defined` guards no-op'd safely),
but once `BUFFER_SYNC` was restored for `LOAD_FILAMENT`/`UNLOAD_FILAMENT`'s own
use, the same guards started firing again and synced the buffer to the extruder
motion queue for entire prints — the exact bug the discrete-push redesign in
`sv08max/buffer-synced.cfg` exists to eliminate.

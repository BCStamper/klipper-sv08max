# 02 — Divergences: What Actually Happened vs. The Plan

**What this is**: doc 02 (`02-DKEU-INTEGRATION.md`) has already been corrected
with the two or three lessons here that belong in the instructions themselves
(the reinstall-wipes-patches warning, the eddy-naming fix now marked resolved).
This doc is the narrative behind those corrections and everything else that
doesn't belong in a checklist: what actually happened during a live, together,
SSH-driven DKEU v3.2.2 reinstall, and the long chain of debugging that followed
before an actual print came out the other side. Read it when you want the
reasoning, not just the instruction.

Everything below happened in a single (very long) session: install DKEU fresh,
work the post-install checklist against both DKEU's general docs and its
SV08-MAX-specific doc, then discover that "checklist complete" was nowhere near
"will actually print." Getting from one to the other took root-causing roughly a
dozen distinct bugs. Most of them turned out to be the same underlying mismatch
wearing different clothes — which is the real story here, and the reason this
doc exists rather than just a list of one-line fixes.

---

## The reinstall and its blast radius

**Planned**: run DKEU's official installer, get a clean current copy, reapply
anything documented in `sv08max/dkeu-patches/`.

**Actual**: the installer (`Demon_Klipper_Essentials_Installer.sh`) pulled
v3.2.2 (`v3.2.2-16-ga7fd49d`) cleanly. But it does a fresh `git clone` of
`Demon_Klipper_Essentials_Unified` on every run — confirmed zero preservation of
local patches inside that directory. Both tracked patches living there
(`demon_homing_control`'s eddy-naming fix, `demon_core_assets`'s historical
M600/svv patches) were silently gone. `Demon_User_Files` is a separate,
customization-preserving directory that fared better — the installer archives it
to `Previous_Versions/` before replacing it with a pristine copy — but "better"
still meant every live customization reset to template defaults:
`demon_custom_expansion`'s PLR hooks (`save_last_file`/`was_interrupted`/
`plr_journal` calls in `_CUSTOM_PRE_START`/`_CUSTOM_POST_END`) were gone, and the
master switches that gate them (`ceal_master_enable`, `pre_start`, `post_end`)
had reverted to `False`. This is now a standing warning in doc 02 itself, not
just here — see its Section A.

**Landed in doc 02**: the reinstall warning box after step A.1, and
`sv08max/dkeu-patches/README.md` restructured to assume this will happen again.

## Post-install checklist work

Reconciling DKEU's general post-install checklist and its SV08-MAX-specific
extra-instructions doc against what was already live turned up a normal set of
integration work, nothing dramatic on its own:

- **Mainsail's `client.cfg` was silently winning the pause/resume/cancel macros.**
  `mainsail.cfg` defines its own generic `PAUSE`/`RESUME`/`CANCEL_PRINT` via
  `rename_existing`, and by include order it loaded after DKEU's own — later
  include wins in Klipper. DKEU's docs (`Set_Up_Your_Mainsail.cfg.md`) document
  the intended fix: a separate `My_Macros.cfg` defining an active
  `[gcode_macro _CLIENT_VARIABLE]` (client.cfg's own copy ships fully commented
  out) with `variable_user_pause_macro: "_DEMON_PAUSE"` etc., wiring client.cfg's
  generic hooks into DKEU's actual macros. Added `My_Macros.cfg`, included right
  after `mainsail.cfg`. Worth knowing for next time: all of client.cfg's own
  variable lookups are defensively guarded
  (`printer['gcode_macro _CLIENT_VARIABLE']|default({})`), so an unconfigured
  `_CLIENT_VARIABLE` doesn't crash anything — it just silently no-ops DKEU's
  hooks, which is exactly what had been happening and is easy to miss.
- **KAMP_LiTE clutter** left over from a manual troubleshooting detour (a stray
  git clone + copy attempt mid-session, chasing a restart that looked hung but
  was actually just a bed-temp-wait timeout) — cleaned up.
- **The rest of the checklist** — `[idle_timeout]` gcode hook + timeout raised
  to 3600, `[firmware_retraction]` added (paired with `My_Macros.cfg`'s
  `use_fw_retract: True`), moonraker's `[file_manager] enable_object_processing`
  and the DKEU `update_manager` entry, `save_variables` reconciliation, the
  `[stepper_z] position_min` safety fix (`-10` → `-1.5`, per DKEU's own explicit
  warning that stock's value risks driving the nozzle through the bed on a
  homing error) — all landed without incident.

None of this predicted what came next.

## The road to an actual print

The first real test print attempt failed. So did the second. So did the third.
Each failure looked different on the surface — a runout-sensor crash, a
communication timeout, "Probe triggered prior to movement," "probe_eddy_current
sensor not in valid range" — which is exactly why this took so long to root
-cause: it looked like a series of unrelated bugs instead of one systemic
mismatch.

### The pattern, stated once up front

**DKEU's SV08-MAX-oriented defaults assume a probe range wider than mainline
`probe_eddy_current` actually provides.** Mainline's `probe_eddy_current.py`
hardcodes `max_z = 4.0` inside `EddyGatherCalibrate.do_calibration_moves()` —
`PROBE_EDDY_CURRENT_CALIBRATE` always sweeps exactly 0–4.0mm (40µm steps), on
any machine, with no config option to widen it. (Checked whether Sovol's stock
firmware calibrates a wider range and could explain a difference — it does not;
`sovol-stock-fork`'s own `probe_eddy_current.py` has the identical hardcoded
`max_z = 4.0`.) Our saved calibration curve is real data from 0.05mm to 4.05mm.
Any macro-level height — a pre-home lift, a park position, a QGL horizontal
clearance — that sends the toolhead's Z commands through the eddy probe outside
roughly that window doesn't get a wrong reading, it gets a hard error, because
the calibration table simply has no entry to look up out there.

Six separate config values turned out to violate this, independently, each
requiring its own discovery:

| Value | Was | Fixed to | Where |
|---|---|---|---|
| `pre_home_lift` | 20mm | 3mm | `demon_user_settings_v3.1.2.cfg` |
| Post-`G28 Z` lift before `SET_Z_FROM_PROBE` | 10mm | 3mm | `demon_homing_control_v2.1.2.cfg` |
| `_QGL` coarse round | 10mm | 3mm | `demon_core_assets` |
| `_QGL` fine round | 6mm | 3mm | `demon_core_assets` |
| `_QGL` eddy-ng branch (not our path, fixed for consistency) | 8mm | 3mm | `demon_core_assets` |
| `[quad_gantry_level]` config default | 15mm | 3mm | `printer-stock-toolhead.cfg` (user's own fix) |
| `_SET_Z_PARK`'s eddy branch | 15mm | 3mm | `demon_core_assets` |
| `_CORE_VARS`' raw `z_park` default | 30mm | 3mm | `demon_core_assets` |

That's the "roughly a dozen bugs" — most of this table found and fixed one at a
time, each one clearing the previous error and immediately hitting the next
value that had the same problem. In order, roughly:

1. **`_RUNOUT_SENSOR_CHECK` crash** ("extruder below minimum temp" cancellation)
   — unrelated to the range issue, a leftover: `variable_runout_sensor: True`
   from before the filament buffer (and its bundled sensor) was shelved. The
   macro itself was correctly guarded; the flag just no longer matched reality.
   Flipped to `False`.
2. **A communication-timeout failure during homing**, then the same failure
   again on retry — this is where `pre_home_lift` (20mm) and the post-`G28 Z`
   lift in `demon_homing_control` (10mm) were found and fixed.
3. **QGL's coarse round succeeded, the fine round then failed** with "Probe
   triggered prior to movement." This is the point where the user, watching the
   pattern of one config value after another turning out to be wrong, correctly
   called it: *"This is absolutely config related... our QGL range is very very
   tight... I think there's some instruction or config difference between
   mainline and stock Sovol klipper that is hanging us up here."* Rather than
   keep patching individual heights one at a time (the approach up to that
   point), the fix was to zoom out and apply DKEU's entire dedicated
   **"Mainline Your Max"** doc
   (`Documentation/INSTALL_INSTRUCTIONS/SOVOL_SV08_MAX_SETUP/Mainline_Your_SV08_MAX.md`)
   in one pass — a more complete `[probe_eddy_current eddy]` block than the
   stock/Sovol-oriented one this project had started with (adds
   `max_sensor_hz`, renames `z_offset` → `descend_z`, adds `speed`,
   `sample_retract_dist`, `samples_tolerance*`). This is also where the QGL
   heights (coarse/fine/eddy-ng branches, plus `[quad_gantry_level]`'s own
   config default) all got set to 3mm together, and where the
   `_OFFSET_FORCE_OVERLAY` call (added per that same doc, marked "REQUIRED")
   was first added — see its own section below for why it was reverted the same
   day.
4. **Two more heights in the same family**, found after the mainline block
   landed: `_SET_Z_PARK`'s `probe_eddy_current`/`mcu eddy` branch (15mm) and
   `_CORE_VARS`' own raw `variable_z_park` default (30mm, used by anything that
   reads `core_vars.z_park` before `_SET_Z_PARK` has run once in a session —
   which is exactly what `demon_bed_checker_heat_soak`'s heat-soak/ref_point
   monitoring does, since it runs before the main Z-homing sequence). Both set
   to 3mm.

### The one that hid in plain sight: `max_sensor_hz`

`ldc1612.py`'s `max_sensor_hz` config option (default 5,000,000 Hz) isn't just a
sanity bound — it directly sets the sensor's hardware frequency divider and
conversion math (`sensor_div`, `freq_conv`). There's a built-in check for this
exact mistake: `ldc1612.py` logs a `runtime_warning` if any calibrated frequency
exceeds the configured max. Our own calibration's peak frequency (closest to the
bed) is 5,950,944.740 Hz — past the unset 5MHz default. **Klipper had been
logging `ldc1612 eddy: Should set 'max_sensor_hz' to at least 5950945` on every
single restart, all night**, and it was missed for hours because it's a
`runtime_warning`, not one of the error/traceback patterns the log greps were
filtering for (`Traceback|Internal error|is not a valid|Unknown command|is
undefined` — no plain "warning" search in the mix). Once found, fixed by the
mainline block's `max_sensor_hz: 6031173`. Worth remembering next time
something looks like a valid-range or homing error with no obvious cause: grep
klippy.log for "warning" too, not just tracebacks.

### The actual last bug: `descend_z` vs `z_park`

After every height above was fixed, the exact same "Probe triggered prior to
movement" error kept recurring on `demon_bed_checker_heat_soak`'s `_BC_PROBE`
bare `PROBE` call — at Z=3.000, confirmed via diagnostic `RESPOND` output to be
comfortably inside the calibrated 0.05–4.05mm range. That ruled out every
"height beyond calibration range" theory at once and forced an actual read of
`homing.py` instead of another guess.

Two things, read directly from source, explain it:

- `homing.py`'s `probing_move()` runs the full homing move, *then* checks
  `check_no_movement()` — **"Probe triggered prior to movement" is a
  post-move check, not a pre-check.** It fires when the toolhead traveled
  essentially zero distance before the endstop registered triggered, i.e. the
  probe was already reading triggered at its *starting* height. (This had been
  misread earlier in the session as a pre-check — "is the probe already
  triggered before starting" — which led to a wrong fix attempt, adding a lift
  between QGL rounds, that didn't touch the real cause.)
- `descend_z` is not a physical offset, despite living next to `x_offset`/
  `y_offset` in the config block — it's the actual **home-mode trigger height**.
  `probe_eddy_current.py`'s `EddyEndstopWrapper.__init__` computes
  `trigger_freq = self._calibration.height_to_freq(self._descend_z)`. A bare
  `PROBE` command (no `METHOD=`) defaults to `method = 'automatic'`, which
  `start_probe_session()` dispatches straight to the descend/home session — so
  *any* bare `PROBE` call uses `descend_z` as its trigger threshold, not
  scan-mode's frequency table.

Our `descend_z` was `3.50`. `z_park` — this same session's own fix, three
paragraphs up — was `3`. `z_park` sat *below* `descend_z`'s trigger height, so
any bare `PROBE` call starting from `z_park` (exactly what
`demon_bed_checker_heat_soak`'s `_BC_MOVE`/`_BC_PROBE` does) found the sensor
already reading triggered before it had moved at all — zero travel before
trigger, exactly matching `check_no_movement()`'s condition. Lowered
`descend_z` to `2.0`: below `z_park` (room for a descend-mode probe to
actually travel) and below the 4.05mm calibrated ceiling (room for scan-mode
reads to stay valid) at the same time. This also affects real `G28 Z` homing,
not just the bed-checker — flagged to Ben before applying, since it changes
where the machine considers itself homed relative to the bed.

**This was the fix that made the test print actually succeed.**

## A separate, unrelated bug found along the way: `plr_journal`'s quoting

Not part of the eddy-range family at all — this one lived in `sv08max/plr.cfg`,
our own power-loss-recovery journal, and surfaced as a parse error on every 5s
journal tick (`Unable to parse ... as a literal`). Klipper's own gcode argument
parser strips exactly one outer layer of single-quotes from a `KEY=value` token
before the receiving macro ever sees it. `save_last_file` in the same file
already handles this correctly (`VALUE='"{ ... }"'` — single quotes for
Klipper's parser to strip, double quotes surviving as the actual Python string
delimiter). `plr_journal` instead embedded single-quoted dict keys directly with
no outer wrapping, so the parser stripped those instead, leaving bare unquoted
keys (`{fp:10813,...}`) that `ast.literal_eval()` correctly rejected as invalid
Python. Fixed to match `save_last_file`'s already-proven pattern
(double-quoted keys, single-quote outer wrapping) and verified with an isolated
manual `SAVE_VARIABLE` test using the exact previously-broken value before
trusting it live.

## `_OFFSET_FORCE_OVERLAY`: added, then reverted same day

Added to `_CUSTOM_PRE_LEVEL` per the "Mainline Your Max" doc (marked
"REQUIRED" there) during the same pass that applied the rest of that doc's
eddy config block. Reverted the same day once actually exercised: it
unconditionally calls `RUN_PROBE_VIR_CONTACT`, a Sovol-vendor eddy-ng-fork
command that doesn't exist in mainline `probe_eddy_current` ("Unknown command"
live), and `CLEAN_NOZZLE` with no `hardware_vars.nozzle_cleaner` guard (we have
no nozzle cleaner configured). Same class of gap as `sovol_plr`
(`_SYSTEM_VARIABLES`' `variable_sovol_plr`) elsewhere in DKEU — written for
Sovol's factory firmware + hardware combination, not mainline. Not needed
anyway: the `G28 Z` + `SET_Z_FROM_PROBE` sequence already gives a freshly
eddy-probe-calibrated Z reference on this setup; the overlay macro exists for
setups where Z-homing comes from something else and this is a separate
cross-check, which isn't our situation. `pre_level` set back to `False`.

## Why this doesn't threaten the rest of the plan

Every fix above was a config value, not a code patch to Klipper or a sign that
mainline `probe_eddy_current` is unreliable — the underlying pattern (DKEU's
SV08-MAX defaults assuming Sovol's stock, wider-range firmware) is exactly the
kind of thing `01-DIVERGENCES.md` already flagged as a recurring theme for this
whole migration: **community docs and macro packs default to assumptions from
stock Sovol firmware, and mainline needs its own read of the actual source
before trusting them.** Once the actual mismatch was found, every fix was a
single config line. Doc 02's own instructions now carry the two pieces of this
that matter for next time (the reinstall warning, the eddy-naming resolution);
everything else is the reasoning trail here.

## Still open, going into doc 03

- **Full eddy probe calibration** — explicitly deferred by design, not an
  oversight. The current calibration curve is real and got a real print out
  the other side, but a proper recalibration is planned after the Stage 2
  toolhead (in progress, nearly finished) is physically mounted — no point
  calibrating twice.
- **Diagnostic `RESPOND` instrumentation** added to `demon_homing_control`,
  `demon_bed_checker_heat_soak`, and `demon_print_start_end` during the
  "Probe triggered prior to movement" hunt is still live on the printer as of
  this doc (marked "temporary... remove once root-caused" in its own
  comments). Root-caused now — remove on the next safe restart window (i.e.
  not mid-print). None of it is tracked in `dkeu-patches/`: the
  `demon_bed_checker_heat_soak` and `demon_print_start_end` copies had no
  functional patch once the diagnostics are stripped back out, so there's
  nothing to preserve there. `demon_homing_control`'s tracked copy already has
  the diagnostics removed — only the live printer still needs the cleanup.
- **`dkeu-patches/demon_core_assets_v2.3.5.cfg`** is retained for history
  (its own two patches are independently obsolete — see its README entry) but
  the live file is now `v2.3.7`. The new file's own patches (the `z_park` and
  QGL-height fixes from this session) are tracked separately as
  `demon_core_assets_v2.3.7.cfg`, not merged into the stale one.
- Doc 03's buffer-variant-selection section (A) still describes choosing
  between `buffer-synced.cfg`/`buffer-pushed.cfg` — stale as of the buffer
  being shelved entirely (see project notes / `printer-stock-toolhead.cfg`'s
  own header comment). Not fixed here; flagged for whoever picks doc 03 up
  next.

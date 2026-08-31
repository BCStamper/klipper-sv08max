# 04 — New Toolhead Changeover

**What**: retire the stock toolhead; install the Yavoth Demon Remix carriage
(custom adapter, Sovol steel-plate mount retained — X belts untouched) with EBB36
CAN v1.2 (MAX31865 + onboard ADXL345), BTT Eddy Duo (CAN), Rapido 2 UHF Plus
(PT100), Orbiter v2.5, new X endstop switch.
**Why last**: everything beneath it — mainline, DKEU macros, PLR, the probe
stack — was proven in 01–02. (The filament buffer was tried, in depth, and
deliberately shelved rather than carried forward — see the
`sv08-max-mainline-klipper` skill's `filament-buffer.md` if "why isn't the
buffer part of this" comes up.) Every anomaly in this session should be the
new hardware or its config, not a leftover software question.
**Changes**: hardware + 2 new CAN MCUs + `printer.cfg` rebuild + calibration.
**Before starting**: this doc was last substantively updated 2026-07-08 —
older than the entire DKEU integration and the eddy-probe-range debugging arc
that followed. It's been reconciled against what's been learned since
(2026-08-3x pass); the deep technical detail behind every correction below
lives in the `sv08-max-mainline-klipper` skill (personal, global — should be
available to Claude regardless of which directory a session runs from) and
`sv08max/docs/02-DIVERGENCES.md`. If something here seems to contradict
either of those, trust the skill/divergences doc — they're the more
frequently-updated source.

## Prerequisites

- [ ] ~~Doc 03 exit criteria all passed~~ — **doc 03 as originally scoped was
      never actually run as its own gated session**, and part of it no longer
      applies: buffer-variant selection (03-A) is moot now that the buffer is
      shelved outright rather than chosen between variants. Screen evaluation
      (03-C) has been covered piecemeal through other investigation over the
      life of the project. **The one real, still-open gap worth knowing
      about**: a genuine PLR power-cut test (03-B) — actually killing mains
      mid-print and confirming resume — has never been run end-to-end; the
      journal/save-state mechanism is verified correct via manual tests, but
      not the real power-cut path. Given the stated workload (30hr+
      unattended prints, no UPS), this is worth doing at some point — doesn't
      block the toolhead swap itself, your call on timing.
- [ ] Carriage adapter printed/machined; **coil mounted ~2.95mm above nozzle
      tip** (tap's sweet spot — a physical/mechanical spec that doesn't
      depend on which software drives it, still applies now that tap comes
      from mainline's own driver rather than eddy-ng, see step A.3 — this was
      a CAD input, verify it made it into the final part)
- [ ] X endstop switch mounted on the toolhead, wired to the EBB36 endstop header
- [ ] All parts + the literal nuts and bolts on hand

## A. Bench prep (new boards, USB — printer still printing)

1. [ ] **EBB36 jumper checklist**: MAX31865 wire-count → **2-wire** (Rapido PT100
       cartridge; 430Ω reference assumed in config); CAN termination jumper —
       decided in step C; VIN/fan voltage sanity (24V fans confirmed at purchase).
2. [ ] Flash EBB36 over USB (BOOT button; no printer needed): Katapult
       (STM32G0B1, 8MHz crystal, CAN PB0/PB1 @1M), then plain Klipper **from
       this fork's tree, same as every other MCU on this printer** — no extra
       driver install step (see step 3 for why).
3. [ ] Eddy Duo: DIP switch → **CAN**; flash per BTT's docs, plain Klipper
       from the same fork tree. **Do not install eddy-ng.** Verified
       2026-08-3x, directly against source rather than assumed: mainline
       Klipper's own `probe_eddy_current` gained native **tap** support
       (nozzle-contact Z sensing that self-corrects for CF-filament-induced
       nozzle wear — the entire reason eddy-ng was ever on the table for this
       project) between 2026-03 and 2026-07-29
       (`PROBE_EDDY_CURRENT_TAP_CALIBRATE`, `METHOD=tap`, `tap_threshold`,
       `tap_z_offset`). It's a host-side addition only —
       `klippy/extras/probe_eddy_current.py` — confirmed zero MCU-firmware
       (`src/sensor_ldc1612.c`) changes were needed or made alongside it, and
       confirmed **this fork's `sv08max-master` branch already carries the
       tap code** (its last sync with upstream master, 2026-06-14, landed
       after the core tap commits). Net result: no eddy-ng install, on
       either MCU, needed anywhere in this build. eddy-ng's own
       Z-homing-circularity bug
       ([vvuk/eddy-ng#146](https://github.com/vvuk/eddy-ng/issues/146)) is
       **still open** as of this check — unofficial community patches exist
       with mixed success reports, no merged upstream fix — so this isn't
       just "tap is available another way now," it's "the thing that used to
       force a hard choice between tap and reliable homing no longer forces
       that choice at all." Full driver history: `01-DIVERGENCES.md` and the
       skill's `eddy-probe.md`.

## B. The swap

1. [ ] Power off. Remove stock toolhead (label its harness — it's the fallback).
2. [ ] Mount the new toolhead; route CAN + power. Mount the Orbiter Smart Sensor
       on the extruder now too (easiest while it's already apart) — its Klipper
       wiring/config is deliberately deferred past this doc, see
       `04-ORBITER-SMART-SENSOR.md`.

## C. ⚠ CAN TERMINATION — the standing reminder lands here

*Why here and not earlier: docs 01–02 never changed the bus. This step adds two
nodes and re-shapes the topology.*

- [ ] Exactly TWO 120Ω terminators at the two physical ENDS of the bus (EBB36 and
      Eddy Duo both have jumpers; mainboard is already on it — buffer MCU's bus
      presence depends on whether its housing stays physically inline, still an
      open mechanical question, not a Klipper config one)
- [ ] Power off, measure CANH↔CANL at any node: **~60Ω = correct**
      (~40Ω = three terminators; ~120Ω = one)

## D. Config + UUIDs

1. [ ] **`sv08max/printer.cfg` (the repo's new-toolhead draft) needs a real
       rebuild before deploying — flagged 2026-08-3x, not yet done as of this
       doc update.** Checked directly: it hasn't been touched since
       2026-07-08, the same commit that first adopted eddy-ng for both
       stages — before literally any of the DKEU integration or the
       eddy-probe-range debugging arc happened. Concretely it's missing: any
       DKEU includes at all (`Demon_Klipper_Essentials_Unified`,
       `Demon_User_Files`, `mainsail.cfg`, `My_Macros.cfg`, `KAMP_LiTE`,
       `Heat_Soak.cfg`); the `position_min`/`firmware_retraction`/
       `idle_timeout` safety fixes; the proven `[probe_eddy_current]` block
       shape (`max_sensor_hz`, `descend_z`, sampling/tolerance settings); and
       it still treats the buffer as an active variant choice
       (`[include buffer-synced.cfg]`) rather than shelved. **Don't deploy it
       as-is or patch it piecemeal** — rebuild starting from
       `printer-stock-toolhead.cfg`'s current, proven structure (it already
       has every fix this project has earned) and adapt the MCU/pin sections
       for the new hardware, rather than trying to bring this old draft up to
       date line by line. (*The fallback file stays deployed alongside,
       untouched, either way — this doesn't need to happen before cable
       management or the physical mount, only before first power-on with the
       new config.*)
2. [ ] No buffer variant to carry over from doc 03 — **the buffer is
       shelved**, not a synced-vs-pushed choice still pending. Don't include
       either `buffer-*.cfg` file in the rebuilt config. See the skill's
       `filament-buffer.md` for why a revival, if it ever happens, needs new
       Klipper source work or an independent-MCU redesign, not a config
       choice between two existing variants.
3. [ ] Power on; `canbus_query.py can0` → fill the EBB36 + Eddy Duo UUIDs
       (plus the buffer's, only if it's still physically on the bus per step C)
4. [ ] `FIRMWARE_RESTART` → klippy connects to every MCU actually configured

## E. First-boot sanity (new electronics only)

- [ ] PT100 reads plausible room temp; unplug it briefly → MAX31865 must FAULT
      (*a wiring/jumper error reads as garbage temps — fault-on-open proves the
      chain*)
- [ ] `ACCELEROMETER_QUERY` (onboard ADXL) + shake test → fix `axes_map` if needed
- [ ] `STEPPER_BUZZ STEPPER=extruder` → flip `dir_pin` if reversed
- [ ] `M106` spins both 4010 blowers; 2510 hotend fan kicks in >50°C; NeoPixels up
- [ ] `QUERY_ENDSTOPS`: new X switch on `EBBCan:PB6` toggles (*sensorless was ruled
      out — no DIAG routing on the mainboard; PD6 spare port is the documented
      fallback if PB6 misbehaves*)

## F. Geometry: datum + travel (the toolhead moved the nozzle!)

1. [ ] Set `homing_speed: 60` for bring-up; home X, then Y
2. [ ] Jog the nozzle exactly over the bed's front-left corner; adjust
       `position_endstop` (X and Y) by the observed delta so the bed spans 0–500
3. [ ] Re-find `position_min`/`position_max`: jog to ~1mm short of each physical
       limit; update config; verify all four corners reachable
4. [ ] Restore `homing_speed: 120` once trusted

## G. Probe: offsets + `probe_eddy_current` calibration + tap

*Driver: `probe_eddy_current`, object name **`eddy`** — same driver and same
object name as Stage 1, deliberately. DKEU's homing macros check specifically
for the object name `eddy` (a Stage-1 fix, itself already wiped and reapplied
once by a DKEU reinstall — see `dkeu-integration.md` in the skill); naming
this object `btt_eddy` instead would reintroduce that exact bug class for no
benefit. No eddy-ng anywhere — see step A.3.*

1. [ ] Measure coil-center → nozzle-tip offsets mechanically (CAD or calipers);
       `offset = coil_pos − nozzle_pos`; ±1mm is fine (*XY offset only shifts
       sample locations — zero effect on Z accuracy*) → `[probe_eddy_current eddy]`
2. [ ] Calibrate the scan/descend curve (bed at 60°C, same flow as doc 01-D:
       `SET_KINEMATIC_POSITION` immediately before, nothing else in between,
       then `LDC_CALIBRATE_DRIVE_CURRENT CHIP=eddy` and
       `PROBE_EDDY_CURRENT_CALIBRATE CHIP=eddy`, paper-touch test, `SAVE_CONFIG`).
       **Remember the hardcoded 4.0mm calibration ceiling** — `PROBE_EDDY_CURRENT_CALIBRATE`
       only ever sweeps ~0–4.0mm, on any hardware, no config override. Any
       macro/config height that commands the probe outside that window
       during a probe operation hard-fails — this cost Stage 1 six separate
       bugs before it was fully understood; don't relearn it the slow way a
       second time. Full story: skill's `eddy-probe.md`. **Set
       `max_sensor_hz`** from this calibration's peak frequency before
       trusting anything — Klipper only warns about a too-low value via a
       `runtime_warning` log line (not an error), easy to miss across a busy
       bring-up session's restarts.
3. [ ] Calibrate tap: `PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=guess`, then
       `TAP=refine`/`TAP=verify` to settle on a real `tap_threshold`, per the
       in-tree
       [Eddy_Probe.md](https://github.com/Klipper3d/klipper/blob/master/docs/Eddy_Probe.md)
       docs. Set `tap_z_offset` once stable. Expect real retuning for this
       specific coil + mount — first-time tap setup on new hardware, same as
       any probe.
4. [ ] From measured offsets: recompute `[bed_mesh]` bounds
       (`mesh_min ≥ position_min + offset`, `mesh_max ≤ position_max + offset`,
       clamped to the bed; enable `scan_overshoot` if X travel allows), confirm
       all four QGL points land ON the bed. **No `[safe_z_home]` section** —
       Stage 1 homes via DKEU's `[homing_override]` + `_SET_Z_PARK`
       machinery, not `safe_z_home`; carry that same approach forward in the
       rebuilt config (see D.1) rather than the old draft's `[safe_z_home]`
       block, which predates the DKEU integration entirely.
5. [ ] Babysat `QUAD_GANTRY_LEVEL`, then a test mesh — shape sane. Set
       `horizontal_move_z` conservatively to start (3mm is what Stage 1's
       identical calibration-ceiling constraint required across several
       different macros — `_QGL`'s own branches, `[quad_gantry_level]`'s
       config default, `z_park`'s several layers, all independently) — verify
       against Stage 2's own calibrated range once step 2 is actually done
       rather than assuming the exact same number carries over unchanged.

## H. Systems re-verify (quick — they didn't change, their neighbor did)

- [ ] One runout dry-run, one short power-cut resume (the buffer's own jam
      poke no longer applies — see D.2)

*(Orbiter Smart Sensor re-verify intentionally not here — see
`04-ORBITER-SMART-SENSOR.md`, wired in as its own deliberate follow-up.)*

## I. Recalibration cascade

*Order matters: heaters before extrusion, extrusion before motion tuning.*

1. [ ] `PID_CALIBRATE HEATER=extruder TARGET=250` (PT100/Rapido at working temp),
       then bed
2. [ ] Orbiter `rotation_distance`: mark, extrude 100mm hot, measure, scale 4.637
3. [ ] `SHAPER_CALIBRATE` (new toolhead mass → new peaks)
4. [ ] Pressure advance for PETG-CF (start 0.03–0.05 — CF blunts PA)
5. [ ] DKEU re-tune pass: purge/park coordinates, probe-adjacent settings; drop the
       `M106`/`M107` dual-fan mapping (single `[fan]` now — native M106 takes over)
6. [ ] Only now walk `max_accel` up from 20000 toward stock's 40000, watching for
       "Timer too close" (*mainline reports what Sovol's firmware hid*)

## Done

First tap-referenced PETG-CF print. The stock toolhead + its fallback config go on
the shelf as a complete, tested rollback unit — which was the point of doing this
in stages.

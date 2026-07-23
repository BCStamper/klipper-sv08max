# 04 — New Toolhead Changeover

**What**: retire the stock toolhead; install the Yavoth Demon Remix carriage
(custom adapter, Sovol steel-plate mount retained — X belts untouched) with EBB36
CAN v1.2 (MAX31865 + onboard ADXL345), BTT Eddy Duo (CAN), Rapido 2 UHF Plus
(PT100), Orbiter v2.5, new X endstop switch.
**Why last**: everything beneath it — mainline, macros, feeder, PLR, probe stack —
was proven in 01–03. Every anomaly in this session is the new hardware or its
config. Rollback is bolting the stock toolhead back on and one `cp` of the fallback
config (its firmware is already mainline from doc 01).
**Changes**: hardware + 2 new CAN MCUs + `printer.cfg` swap + calibration.

## Prerequisites

- [ ] Doc 03 exit criteria all passed
- [ ] Carriage adapter printed/machined; **coil mounted ~2.95mm above nozzle tip**
      (*eddy-ng tap's sweet spot — this was a CAD input, verify it made it in*)
- [ ] X endstop switch mounted on the toolhead, wired to the EBB36 endstop header
- [ ] All parts + the literal nuts and bolts on hand

## A. Bench prep (new boards, USB — printer still printing)

1. [ ] **EBB36 jumper checklist**: MAX31865 wire-count → **2-wire** (Rapido PT100
       cartridge; 430Ω reference assumed in config); CAN termination jumper —
       decided in step C; VIN/fan voltage sanity (24V fans confirmed at purchase).
2. [ ] Flash EBB36 over USB (BOOT button; no printer needed): Katapult
       (STM32G0B1, 8MHz crystal, CAN PB0/PB1 @1M), then Klipper **from this fork
       with eddy-ng installed** (*same reason as doc 01 — though the EBB36 hosts no
       LDC1612, building everything from one tree keeps versions uniform*).
3. [ ] Eddy Duo: DIP switch → **CAN**; flash per BTT's docs from the fork tree
       **with eddy-ng installed** (*this one DOES host the LDC1612 — eddy-ng's MCU
       code is mandatory here*).

## B. The swap

1. [ ] Power off. Remove stock toolhead (label its harness — it's the fallback).
2. [ ] Mount the new toolhead; route CAN + power; Orbiter filament sensor to the
       EBB36 headers if wiring it now.

## C. ⚠ CAN TERMINATION — the standing reminder lands here

*Why here and not earlier: docs 01–03 never changed the bus. This step adds two
nodes and re-shapes the topology.*

- [ ] Exactly TWO 120Ω terminators at the two physical ENDS of the bus (EBB36 and
      Eddy Duo both have jumpers; mainboard + buffer are already on it)
- [ ] Power off, measure CANH↔CANL at any node: **~60Ω = correct**
      (~40Ω = three terminators; ~120Ω = one)

## D. Config + UUIDs

1. [ ] Deploy the repo's **`printer.cfg`** (new-toolhead config) over the Stage-A
       copy (*the fallback file stays deployed alongside, untouched*)
2. [ ] Carry over the buffer-variant include chosen in doc 03
3. [ ] Power on; `canbus_query.py can0` → fill the EBB36 + Eddy Duo UUIDs
4. [ ] `FIRMWARE_RESTART` → klippy connects to all five MCUs (bridge, toolhead,
       buffer, Duo, host)

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

## G. Probe: offsets + eddy-ng calibration #2

1. [ ] Measure coil-center → nozzle-tip offsets mechanically (CAD or calipers);
       `offset = coil_pos − nozzle_pos`; ±1mm is fine (*XY offset only shifts
       sample locations — zero effect on Z accuracy*) → `[probe_eddy_ng btt_eddy]`
2. [ ] Calibrate (bed at 60°C, same flow as doc 01-D); expect to retune
       `tap_threshold`/`tap_target_z` for the Duo coil + new mount
3. [ ] From measured offsets: recompute `[bed_mesh]` bounds
       (`mesh_min ≥ position_min + offset`, `mesh_max ≤ position_max + offset`,
       clamped to the bed; enable `scan_overshoot` if X travel allows), set
       `[safe_z_home] home_xy_position = (250 − x_offset, 250 − y_offset)`, confirm
       all four QGL points land ON the bed
4. [ ] Babysat `QUAD_GANTRY_LEVEL`, then a test mesh — shape sane

## H. Systems re-verify (quick — they didn't change, their neighbor did)

- [ ] One jam poke, one runout dry-run, one short power-cut resume
- [ ] Orbiter filament sensor sections uncommented + pins verified, runout pauses

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

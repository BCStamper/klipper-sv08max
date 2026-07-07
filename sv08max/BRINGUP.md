# SV08 MAX Mainline Bring-Up & Offset Calibration Plan

New toolhead: Yavoth Demon Remix / EBB36 CAN v1.2 (MAX31865, PT100) / BTT Eddy Duo (CAN) /
Rapido 2 UHF Plus / Orbiter v2.5. Klipper: `sv08max-mainline` branch (v0.13.0 base).

Safety nets before starting: stock eMMC/config backup;
[Moffy97/sovol-sv08max-toolhead-recovery](https://github.com/Moffy97/sovol-sv08max-toolhead-recovery)
(SBC-as-SWD unbrick for toolhead/buffer MCUs).

---

## Phase 0 — Bench prep (printer still stock and printing)

1. Flash Katapult + Klipper (from `sv08max-mainline`) on EBB36 (STM32G0B1, 8MHz crystal,
   CAN PB0/PB1, 1M) and Eddy Duo (per BTT docs, DIP switch → CAN) on the bench via USB.
2. **⚠️ CAN TERMINATION — check before FIRST plug-in of the new toolhead** (you asked to be
   reminded): exactly two 120Ω terminators at the two physical ends of the bus. EBB36 and
   Eddy Duo both have termination jumpers; the mainboard bridge and buffer board are already
   on the bus. Power off, measure across CANH/CANL: **~60Ω = correct**. ~40Ω = three
   terminators; ~120Ω = one.
3. Cutover weekend only: flash buffer F103 and mainboard H750 (128KiB bootloader option —
   already patched in the branch; build configs mirror Sovol's `.config*` files).
4. `~/klipper/scripts/canbus_query.py can0` → fill all four `TODO_*_UUID` in printer.cfg.
   Expect NEW UUIDs everywhere (stock firmware hardcoded them).

### Phase 0.5 — EBB36 jumper checklist (before closing up the toolhead)

- **MAX31865 wire-count jumpers → 2-wire** (Rapido PT100 cartridge is 2-wire). The board
  supports PT100/PT1000 and 2/4-wire via jumpers — config assumes PT100 2-wire, 430Ω ref.
- **CAN termination jumper**: set per the Phase 0 topology decision (exactly two 120Ω on
  the whole bus — EBB36 and Eddy Duo both have jumpers).
- **Endstop header**: identify the pin for the new X-endstop switch against the BTT EBB36
  v1.2 pinout PDF (draft assumes PB6) — a physical switch mount needs designing into the
  Demon Remix carriage anyway.
- ADXL345 is onboard this variant (PB12/spi2 in the draft) — no external unit.
- Orbiter filament sensor: wire to the endstop/I2C expansion headers; uncomment the
  `toolhead_filament`/`toolhead_motion` sections in printer.cfg and verify pins.

## Phase 1 — First-boot sanity (nothing hot, nothing homed)

In order: `QUERY_ENDSTOPS` (toggle each by hand) → PT100 reads plausible room temp (a
short/open MAX31865 fault must appear as an error, not a bogus temp) → bed thermistor sane →
`ACCELEROMETER_QUERY` (ADXL) → eddy responds (`PROBE_EDDY_CURRENT_CALIBRATE` will error
cleanly if the LDC1612 is unreachable — do not run it yet, just check for i2c errors in the
log) → `STEPPER_BUZZ STEPPER=stepper_x` (and y, z, z1–z3, extruder) for direction — flip
`dir_pin` polarity where wrong → fans: `M106 S128`, hotend_fan kicks in above 50°C later.

## Phase 2 — Travel limits & nozzle datum (geometry changed with the toolhead!)

The Demon Remix moves the nozzle relative to the carriage, so endstop positions and travel
limits from stock are stale.

1. **X endstop decision**: physical microswitch wired to EBB36 (draft assumes `EBBCan:PB6` —
   verify against the BTT pinout) or TMC5160 sensorless (mainboard DIAG pin needed — check
   `Motherboard/Mcu_Pin_definition.pdf`). Do this before homing X.
2. Home X and Y at the reduced `homing_speed: 60`.
3. **Datum**: jog the nozzle until it is exactly over the bed's front-left corner (bed is a
   fixed 500×500 datum). The commanded position at that point tells you the offset between
   the current coordinate system and the bed: adjust `position_endstop` (X and Y) by that
   delta so the bed spans 0–500 in both axes.
4. Re-find true `position_min`/`position_max`: jog slowly toward each physical limit,
   stop ~1mm short, record. Update the config. Re-home and verify the nozzle can reach all
   four bed corners.

## Phase 3 — Eddy XY offset (coil vs nozzle)

Key insight: **XY offset needs only ~±1mm accuracy.** It only determines where the coil sits
when Klipper "probes at" a point — it shifts sample locations, it does not affect Z accuracy.

1. Primary method: measure mechanically. From the Demon Remix CAD (or calipers on the mounted
   head): coil **center** to nozzle **tip**, X and Y separately. Sign convention:
   `offset = coil_pos − nozzle_pos` in bed coordinates.
2. Optional refinement: park ~3mm above an isolated metal feature with a crisp edge (a bed
   screw head near the bed edge works), and slowly jog X across it while watching the probe
   frequency/height output; the response is symmetric around the feature center. Repeat in Y.
   Compare the found center against the nozzle-over-feature position.
3. Enter `x_offset`/`y_offset` in `[probe_eddy_current btt_eddy]`.

## Phase 4 — Eddy Z calibration chain (order matters)

1. `LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy` — toolhead centered, ~20mm above bed, cold.
   `SAVE_CONFIG`.
2. `PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy` — paper-drag procedure at bed center maps
   frequency↔height. `SAVE_CONFIG`.
3. `G28 Z` now works (probe is the virtual Z endstop). Then `PROBE_ACCURACY` — expect
   single-digit-micron stddev from the LDC1612 at fixed temperature.
4. `QUAD_GANTRY_LEVEL` — babysit the first run (hand on the power switch); verify all four
   probe points land ON the bed with the new offsets before trusting it.
5. Temperature drift: `TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy TARGET=<temp>` per Klipper
   docs — heat-soak the bed to ~100°C during the procedure so the probe sees a full thermal
   range. This matters on a 500×500 heated chamber-adjacent bed.
6. `BED_MESH_CALIBRATE METHOD=rapid_scan` — sanity-check the mesh shape (no cliff at edges =
   offsets and bounds are right).

## Phase 5 — First-layer Z offset

`z_offset` for eddy probes is the **trigger height** (~2.5mm), not the first-layer squish.
Dial the real first layer with a test print + `SET_GCODE_OFFSET Z_ADJUST=` (babystepping),
then persist the result. If you later want nozzle-contact accuracy like Sovol's
"virtual contact" gave you, evaluate `probe_eddy_ng`'s tap mode as a drop-in upgrade.

## Phase 6 — Dependent recalibrations

- Recompute `[bed_mesh]` bounds from measured offsets:
  `mesh_min ≥ (position_min + offset, …)` and `≥` bed edge; `mesh_max ≤ (position_max +
  offset, …)` and `≤ 500`. Enable `scan_overshoot` if X travel allows.
- `[safe_z_home] home_xy_position = (250 − x_offset, 250 − y_offset)`.
- `PID_CALIBRATE HEATER=extruder TARGET=250` (Rapido at working temp), then bed.
- Verify Orbiter `rotation_distance`: mark filament, extrude 100mm at 150°C+, measure,
  scale 4.637 accordingly.
- `SHAPER_CALIBRATE` with the ADXL; expect different peaks than stock (new toolhead mass).
- Pressure advance tower for the Rapido UHF (start 0.02–0.03).
- Only now consider raising `max_accel` from 20000 toward stock's 40000 — watch for
  "Timer too close" errors, which Sovol's firmware masked but mainline reports honestly.

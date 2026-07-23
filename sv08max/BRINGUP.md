# SV08 MAX Mainline Bring-Up — Two-Stage Runbook

**Strategy (decided 2026-07-08): staged migration.** Stage 1 puts mainline on the
printer with the STOCK toolhead and ends with a printing printer. Stage 2 swaps in the
new toolhead on a proven foundation. Rationale: every failure in Stage 1 is software;
every failure in Stage 2 is the new hardware — no coupled debugging. The Stage 1
config (`printer-stock-toolhead.cfg`) is also the permanent fallback if the stock
toolhead ever goes back on.

New toolhead (Stage 2): Yavoth Demon Remix (custom carriage adapter, Sovol steel-plate
mount retained) / EBB36 CAN v1.2 (MAX31865, PT100, onboard ADXL345) / BTT Eddy Duo
(CAN) / Rapido 2 UHF Plus / Orbiter v2.5. Workload: long PETG-CF prints — reliability
over features.

**Probe stack: eddy-ng, both stages** (stock coil in Stage 1, Eddy Duo in Stage 2).
Tap gives nozzle-contact Z that self-corrects for CF-induced nozzle wear.
⚠ eddy-ng includes MCU-side sensor code: **install vvuk/eddy-ng on the host BEFORE
building ANY MCU firmware** that hosts an LDC1612 (stock toolhead F103 in Stage 1,
Eddy Duo in Stage 2).

**One-shot flashing policy (per stage)**: no pre-baked binaries — each stage's MCUs
are flashed within that stage's session, in document order.

Safety nets: spare pre-flashed Sovol eMMC (factory rollback, on hand); ST-Link V2 +
STM32CubeProgrammer (on hand); live config backed up 2026-07-08 (`live-backup/`
locally — contains the Obico token, never push unscrubbed);
[Moffy97/sovol-sv08max-toolhead-recovery](https://github.com/Moffy97/sovol-sv08max-toolhead-recovery)
(SBC-as-SWD unbrick). Install method: 3DPrintDemon's "Mainline Your MAX" flow with
KIAUH pointed at this fork (his guide lives in `Demon_Klipper_Essentials_Unified` —
consider supporting his Patreon).

---

# STAGE 1 — Mainline cutover, stock toolhead on

## 1.0 Host conversion

1. Confirm backup exists (done 2026-07-08). Keep the spare eMMC sealed.
2. KIAUH: `cd kiauh && git pull`, run `~/kiauh/kiauh.sh`.
3. **Point KIAUH at the fork** (Settings `S`): repo
   `https://github.com/BCStamper/klipper-sv08max`, branch `sv08max-master`.
   (Makes the Demon guide's manual Kconfig edit unnecessary — upstream master already
   allows the H750's 128KiB bootloader.)
4. Remove Sovol Klipper (`3 Remove → 1 Klipper`), install from the fork
   (`1 Install → 1 Klipper`).
5. Extras: `4 Advanced → 5 Input Shaper` packages: YES. `E Extensions → 1 G-Code
   Shell Command → Install` (example: NO; the fork already ships the module —
   harmless either way).
6. **Install eddy-ng** (required BEFORE firmware builds):
   `cd ~ && git clone https://github.com/vvuk/eddy-ng && cd eddy-ng && ./install.sh`
7. Deploy configs into `~/printer_data/config/`: `buffer-synced.cfg` (or pushed),
   `plr.cfg`, `macros.cfg`, `plr.sh`, and **`printer-stock-toolhead.cfg` copied AS
   `printer.cfg`**. (The repo's `printer.cfg` is the Stage 2 / new-toolhead config —
   it deploys in Stage 2.)
8. `sudo reboot`. Expect the big red MCU-version error — that's the cue for 1.1.

## 1.1 Flash the three existing MCUs over CAN

Katapult is CONFIRMED as Sovol's own update mechanism (their `~/printer_data/build/`
ships Katapult's `flash_can.py` + jump scripts; verified on this unit 2026-07-07).
Mechanics ([canbus.esoterical.online](https://canbus.esoterical.online) for the
generic walkthrough):

- **Mainboard H750 first** (menuconfig: STM32H750, 128KiB bootloader, 25MHz crystal
  per the Demon guide, USB-to-CAN bridge PA11/PA12, CAN PB8/PB9 @1M). Optional GPIO
  init `!PB0,!PE11,!PE14` keeps the fans quiet at boot (mirrors Sovol's firmware; no
  chamber heater on this machine so boot-cooling is moot). After the bootloader jump
  the H750's Katapult appears as **USB serial** (`usb-katapult_stm32h750xx_*`) —
  flash via `flash_can.py -f <bin> -d <that device>`.
- **Stock toolhead F103** (CAN PB8/PB9 @1M; build INCLUDES eddy-ng MCU code).
- **Buffer F103 LAST** — it has no vendor update script anywhere (confirmed on-unit):
  Katapult is inferred, unproven until this jump. If it never appears in bootloader
  mode, STOP for that node — Moffy97 SBC-SWD is its recovery path.
- **CAN nodes report a DIFFERENT UUID in Katapult mode** (real chip ID vs Sovol's
  hardcoded app UUIDs): after each jump, re-query
  (`~/klippy-env/bin/python ~/klipper/scripts/canbus_query.py can0`) and flash the
  newly detected UUID — exactly what Sovol's own scripts do.
- Fill the `TODO_*_UUID`s in printer.cfg + buffer cfg as you go. Expected Stage 1
  nodes: mainboard bridge, stock toolhead, buffer.
- Host MCU (optional): `make menuconfig` → Linux process → `make flash`; enable
  `klipper-mcu.service`.

## 1.2 First-boot sanity (stock geometry — no re-measurement needed)

`QUERY_ENDSTOPS` (toggle X on the toolhead, Y by hand) → extruder thermistor and bed
read plausible room temp → `ACCELEROMETER_QUERY` (stock LIS2DW) → no i2c errors in
klippy.log (eddy-ng on software i2c) → `STEPPER_BUZZ` every stepper → fans respond
(`M106 S128` drives BOTH part-cooling fans via the mapping macro; `M107` stops them).

## 1.3 eddy-ng calibration on the stock coil

Per the Demon guide (his tested flow for exactly this hardware):

```
SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET=60
TEMPERATURE_WAIT SENSOR=heater_bed MINIMUM=58 MAXIMUM=62
G28 X Y
PROBE_EDDY_NG_CALIBRATE DRIVE_CURRENT=15
SAVE_CONFIG
```

Then `G28 Z` works. Follow with `PROBE_ACCURACY`, a babysat `QUAD_GANTRY_LEVEL`
(stock points are known-good), tap setup per
https://github.com/vvuk/eddy-ng/wiki/Calibration, and a
`BED_MESH_CALIBRATE METHOD=rapid_scan` sanity check.

## 1.4 Buffer variant bench-pick (real feeder, real filament)

1. Start with `buffer-synced.cfg`: long extrude → feeder follows, push switch toggles
   the trim, slack bounded over several meters.
2. Jam simulation (pinch the reverse-Bowden at the spool): PAUSE +
   `winding_status=True` + blue LED within ~5s.
3. Runout chain: withdraw filament at the inlet → `CONTINUE_PRINT_D` counts down
   1100mm → M600 → tail spit-out (with the 50s dwell).
4. Verify `FORCE_MOVE STEPPER="extruder_stepper filament_buffer"` (quoted name) works.
5. If feed quality disappoints, swap the include to `buffer-pushed.cfg`; verify a
   mid-print push does NOT stutter XY.

## 1.5 PLR power-cut test

Sacrificial print to ~10mm, kill mains, power on → Mainsail prompt offers
Resume/Discard → resume: XY homes (Z must NOT), temps restore, seam ≤ one layer + 5s.
Test absolute-E and M83 files. Slicer start/end gcode must call
`PRINT_START`/`PRINT_END`. Highest-value test on this list for 30-hour prints.

## 1.6 Screen observation (makerbase-client STAYS — decided 2026-07-08)

The vendor client keeps running: it's a Moonraker API client, our config preserves
the object names it reads (`variables` flags, `filament_sensor`, standard macros),
and it's a future integration hook (custom features/displays). Watch for
client-induced errors in klippy/moonraker logs during 1.2–1.5; the eddy/Z-offset
screens will error (no `Z_OFFSET_CALIBRATION`) — a shim macro mapping that to
eddy-ng tap is a possible later nicety. Only `systemctl disable --now
makerbase-client` if it actively misbehaves. ⚠ Never tap update/OTA on the screen:
the endpoint serves a test manifest for a different printer (post-cutover the
version check fails safely, but don't tempt it).

## STAGE 1 EXIT CRITERIA

- [ ] Prints reliably on mainline with the stock toolhead
- [ ] Buffer variant chosen and passing jam/runout tests
- [ ] PLR power-cut test passed
- [ ] QGL + mesh + eddy-ng tap working on the stock coil
- [ ] Screen behavior documented (works / partially / errors)

Print big things here as long as you like — Stage 2 waits until you're bored.

---

# STAGE 1.5 (optional, future) — DKEU macro pack

[Demon Klipper Essentials Unified](https://github.com/3DPrintDemon/Demon_Klipper_Essentials_Unified)
layers on AFTER Stage 1 exit criteria pass and BEFORE Stage 2 — macro-integration
bugs stay isolated from hardware bugs, and this is the config state DKEU's own
SV08 MAX docs target. (Support his Patreon — we're standing on his flash guide too.)

**Collision map (verified against the repo 2026-07-08):**

| Macro | Owner | Action |
|---|---|---|
| `PAUSE` / `RESUME` / `CANCEL_PRINT` | **ours** | No conflict — DKEU doesn't define them; feeder-aware versions stay |
| `M106` / `M107` | **ours** (stage-1 dual-fan map) | No conflict |
| `PRINT_START` / `START_PRINT` | **DKEU** | Their orchestration wins (heat soak, QGL, adaptive mesh, purge). Move our hooks — PLR journal start, `was_interrupted`, `save_last_file`, `BUFFER_SYNC` — into DKEU's user-hook files (`Demon_User_Files`); slicer start-gcode switches to DKEU's call |
| `PRINT_END` | **DKEU** + hooks | Same treatment: journal stop, flag clear, `BUFFER_DESYNC`, plr_clear |
| `LOAD_FILAMENT` / `UNLOAD_FILAMENT` | **ours** | Buffer choreography must win — disable/rename DKEU's or wire theirs to call ours |
| `M600` | **ours** | The `CONTINUE_PRINT_D` 1100mm tail chain depends on it — keep ours; disable DKEU's |

Also per the Demon mainline guide: disable the obsolete macro in the DKEU
custom_expansion file (his instructions link). After Stage 2, expect a small DKEU
re-tune pass — purge/park coordinates and probe-adjacent settings move with the
new toolhead geometry. Re-run the Stage 1 buffer/PLR tests after integrating
(the macro layer changed under them).

---

# STAGE 2 — New toolhead swap (proven foundation underneath)

## 2.0 Pre-swap bench + bus work

1. **EBB36 jumper checklist**: MAX31865 wire-count → **2-wire** (Rapido PT100
   cartridge; 430Ω ref assumed); CAN termination jumper per step 3; ADXL345 is
   onboard; Orbiter filament sensor → endstop/I2C headers (uncomment
   `toolhead_filament`/`toolhead_motion` in printer.cfg, verify pins).
2. USB-flash the new boards from the fork (WITH eddy-ng installed): EBB36 via BOOT
   button (Katapult, then Klipper: STM32G0B1, 8MHz crystal, CAN PB0/PB1 @1M);
   Eddy Duo per BTT docs, DIP switch → CAN.
3. **⚠ CAN TERMINATION — the standing reminder lands HERE** (the bus changes now):
   exactly two 120Ω terminators at the physical ends; EBB36 and Eddy Duo both have
   jumpers; mainboard + buffer are already on the bus. Power off, measure CANH↔CANL:
   **~60Ω correct** (~40Ω = three, ~120Ω = one).
4. Swap the toolhead hardware. Deploy the repo's `printer.cfg` (new-toolhead config)
   over the Stage 1 copy. `canbus_query.py` → fill the EBB36 + Eddy Duo UUIDs.

## 2.1 First-boot sanity (new electronics)

PT100 reads plausible room temp (a shorted/open MAX31865 must FAULT, not read
garbage) → `ACCELEROMETER_QUERY` (onboard ADXL; verify axes_map with a shake test) →
`STEPPER_BUZZ STEPPER=extruder` (flip `dir_pin` if backwards) → both 4010 blowers on
`M106`, 2510 kicks above 50°C → NeoPixels light.

## 2.2 X endstop + travel + nozzle datum (geometry changed!)

X endstop = new switch on EBB36 `PB6` (verify against BTT pinout; sensorless is
impossible — no TMC5160 DIAG routing; mainboard `PD6` spare port is the documented
alternative). Then: home X/Y at reduced speed (set `homing_speed: 60` for bring-up),
jog the nozzle over the bed's front-left corner, shift `position_endstop` (X and Y)
so the bed spans 0–500, re-find true `position_min`/`position_max` (~1mm short of
physical limits), verify all four corners reachable.

## 2.3 Eddy Duo offsets

Measure mechanically (CAD or calipers): coil CENTER to nozzle TIP, per axis;
`offset = coil_pos − nozzle_pos`. ±1mm is fine — XY offset shifts sample locations,
it does not affect Z accuracy. Enter in `[probe_eddy_ng btt_eddy]`.
Reminder from the mount design: tap wants the coil **~2.95mm above the nozzle tip**.

## 2.4 eddy-ng calibration #2 (Duo) + downstream geometry

Same calibrate flow as 1.3 (bed at 60°C). Expect to retune tap
threshold/`tap_target_z` for the Duo coil + new mount. Then, from the measured
offsets: recompute `[bed_mesh]` bounds (`mesh_min ≥ position_min + offset` etc.,
within 0–500; enable `scan_overshoot` if X travel allows), set
`[safe_z_home] home_xy_position = (250 − x_offset, 250 − y_offset)`, verify all four
QGL probe points land ON the bed, then a babysat `QUAD_GANTRY_LEVEL` and a test mesh.

## 2.5 Buffer + PLR re-verify (quick)

One jam poke, one runout dry-run, one short power-cut resume — the systems didn't
change, but the toolhead they feed did.

## 2.6 Recalibration cascade

`PID_CALIBRATE HEATER=extruder TARGET=250+` (PT100/Rapido) → bed PID → verify
Orbiter `rotation_distance` (100mm mark test against 4.637) → `SHAPER_CALIBRATE`
(new toolhead mass, onboard ADXL) → pressure advance for PETG-CF (start 0.03–0.05;
CF blunts it) → only then raise `max_accel` from 20000 toward stock's 40000,
watching for "Timer too close" (Sovol masked it; mainline reports honestly).

---

# Recovery (any stage)

- Klipper app reflash via ST-Link: correct build at `0x08020000` (H750).
- Overwritten bootloader: rebuild Katapult with `|| MACH_STM32H750` added to its
  `src/stm32/Kconfig` (128KiB section AND the flash-settings block), full chip erase,
  Katapult at `0x08000000`, Klipper at `0x08020000` (Demon guide recovery section).
- Toolhead/buffer F103s: Moffy97 SBC-as-SWD, no ST-Link needed.
- Nuclear: swap in the spare pre-flashed Sovol eMMC (full factory state).

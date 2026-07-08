# SV08 MAX Mainline Bring-Up & Offset Calibration Plan

New toolhead: Yavoth Demon Remix (custom carriage adapter keeping the Sovol steel-plate
mount + belt clamps) / EBB36 CAN v1.2 (MAX31865, PT100, onboard ADXL345) / BTT Eddy Duo
(CAN) / Rapido 2 UHF Plus / Orbiter v2.5. Klipper: `sv08max-master` branch.
Workload target: long PETG-CF prints — reliability over features.

Flash strategy: **3DPrintDemon's "Mainline Your MAX" method** — keep the stock Sovol
eMMC image, swap only Klipper via KIAUH, flash MCUs over CAN. No eMMC reimage.
Guide: 3DPrintDemon/Demon_Klipper_Essentials_Unified →
`Documentation/INSTALL_INSTRUCTIONS/SOVOL_SV08_MAX_SETUP/Mainline_Your_SV08_MAX.md`
(consider supporting his Patreon if this saves your bacon).

Safety nets: spare pre-flashed Sovol eMMC (full factory rollback, on hand); ST-Link V2 +
STM32CubeProgrammer (on hand); config backup untouched;
[Moffy97/sovol-sv08max-toolhead-recovery](https://github.com/Moffy97/sovol-sv08max-toolhead-recovery)
(SBC-as-SWD unbrick, no ST-Link needed).

---

## Phase 0 — Host conversion (stock image, Demon method)

1. **Backup**: download `/config` untouched; keep the spare eMMC sealed.
2. KIAUH: `cd kiauh && git pull`, run `~/kiauh/kiauh.sh`.
3. **Point KIAUH at OUR fork** (Settings `S`): repo
   `https://github.com/BCStamper/klipper-sv08max`, branch `sv08max-master`.
   This replaces the Demon guide's `Klipper3d/klipper` master AND makes his manual
   Kconfig `nano` step unnecessary — upstream master (which we track) already allows
   the 128KiB bootloader on STM32H750.
4. Remove Sovol Klipper (`3 Remove → 1 Klipper`), install Klipper from the fork
   (`1 Install → 1 Klipper`).
5. Extras: `4 Advanced → 5 Input Shaper` packages: YES. `E Extensions → 1 G-Code Shell
   Command → Install` (example command: NO). NOTE: our fork already ships
   `gcode_shell_command.py`; installing the KIAUH extension is harmless either way.
6. Optional (eddy-ng path, see Phase 4 alternative): `git clone
   https://github.com/vvuk/eddy-ng && cd eddy-ng && ./install.sh`.
7. Deploy the `sv08max/` overlay configs into `~/printer_data/config/`; `sudo reboot`.
8. Expect the big red MCU-version error — that's the cue for Phase 0.75.

## Phase 0.75 — MCU flashing over CAN (no ST-Link happy path)

**CONFIRMED — Katapult is Sovol's own update mechanism.** The stock image ships
`~/printer_data/build/` containing Katapult's `flash_can.py` plus per-MCU update
scripts that jump each MCU into its bootloader and flash it (this is how Sovol OTA
works). H750 app lives at `0x08020000` (128KiB offset); flashing follows the standard
flow ([canbus.esoterical.online](https://canbus.esoterical.online) mainboard +
toolhead pages). Details learned from those vendor scripts:

- The **H750's Katapult presents as USB serial** (`/dev/serial/by-id/usb-katapult_stm32h750xx_*`)
  after the jump — flash the mainboard over USB with `flash_can.py -f <bin> -d <that device>`.
- **CAN nodes get a DIFFERENT UUID in Katapult mode** (bootloader uses the real chip ID;
  Sovol's app hardcodes fake ones). After jumping a node, re-query and flash the
  *newly detected* UUID — exactly what Sovol's own scripts do.
- The vendor bundle has scripts for the mainboard + two CAN nodes but **none for the
  buffer MCU** — same factory process almost certainly applies, but it's the one node
  without vendor-tooling proof. It's also the node Moffy97's SBC-SWD recovery covers.
- Sovol's shipped `.config` files (on `sovol-stock-fork`) say `FLASH_START_0000` —
  stale factory-direct builds; production firmware is offset-linked. Ignore them for
  offsets; mirror them only for pin/feature selections.

> Residual sanity check on the real machine before first flash: confirm
> `~/printer_data/build/flash_can.py` and the `*_update_fw.sh` scripts exist on YOUR
> unit (SSH checklist). If that directory is missing, stop and reassess.

1. Flash order: mainboard H750 first (menuconfig: STM32H750, 128KiB bootloader,
   25MHz crystal per Demon guide's screenshots, USB-to-CAN bridge on PA11/PA12, CAN
   PB8/PB9, 1M). Optional GPIO init pins `!PB0,!PE11,!PE14` keep the aux/exhaust/bed
   fans from blasting at boot — matches Sovol's firmware behavior we reverse-engineered
   from their `stm32h7.c`; skip if you ever add a chamber heater (boot cooling).
2. Buffer F103: same flow (F103, CAN PB8/PB9 @1M, Katapult offset per esoterical F103
   guidance).
3. **UUIDs change after every flash** (stock firmware hardcoded them; mainline derives
   real chip IDs): re-run `canbus_query.py` after each node and fill the `TODO_*_UUID`s.
   Expected nodes: mainboard bridge, buffer, EBB36, Eddy Duo. (No chamber-heater
   `hot_mcu` on this machine.)
4. Host MCU (optional, for input-shaper-adjacent features): `make menuconfig` → Linux
   process → `make flash`; enable `klipper-mcu.service` per the Demon guide.
5. New toolhead boards flash over USB first (no printer needed): EBB36 via BOOT button
   (Katapult then Klipper from this fork), Eddy Duo per BTT docs with DIP switch → CAN.

### ⚠️ CAN TERMINATION — before FIRST plug-in of the new toolhead (standing reminder)

Exactly two 120Ω terminators at the two physical bus ends. EBB36 and Eddy Duo both have
termination jumpers; mainboard + buffer are already on the bus. Power off, measure
CANH↔CANL: **~60Ω correct**; ~40Ω = three terminators; ~120Ω = one.

### Phase 0.9 — EBB36 jumper checklist (before closing up the toolhead)

- MAX31865 wire-count jumpers → **2-wire** (Rapido PT100 cartridge). Config assumes
  PT100, 430Ω reference.
- CAN termination jumper per the topology above.
- ADXL345 is onboard (PB12/spi2 in the draft) — no external unit.
- Orbiter filament sensor → endstop/I2C headers; uncomment `toolhead_filament` /
  `toolhead_motion` sections and verify pins.

## Phase 1 — First-boot sanity (nothing hot, nothing homed)

`QUERY_ENDSTOPS` (toggle each by hand) → PT100 reads plausible room temp (a shorted/open
MAX31865 must fault, not read garbage) → bed thermistor sane → `ACCELEROMETER_QUERY` →
eddy responds (no i2c errors in log; don't calibrate yet) → `STEPPER_BUZZ` every stepper
for direction (flip `dir_pin` where wrong) → fans respond to `M106 S128`.

## Phase 2 — X endstop, travel limits & nozzle datum

**Sensorless X is OFF the table**: the mainboard pin definition routes no TMC5160 DIAG
pin to the H750 (verified from `Motherboard/Mcu_Pin_definition.pdf` — only PD1 (Y) and
one spare endstop port exist). Physical switch required; **DECIDED: EBB36 endstop
header (`^EBBCan:PB6`, verify against BTT pinout)** — switch rides the toolhead
(ordered), mount designed into the Demon Remix adapter, keeps toolhead sensors on the
toolhead board. Documented alternative if the mount gets crowded: mainboard `PD6`
(the spare endstop port, PD1's unused twin) with a stationary switch at the gantry's
X-min end.

Then re-establish geometry (the Demon Remix moves the nozzle relative to the carriage):

1. Home X and Y at reduced `homing_speed: 60`.
2. **Datum**: jog the nozzle exactly over the bed's front-left corner; shift
   `position_endstop` (X and Y) by the observed delta so the bed spans 0–500.
3. Re-find `position_min`/`position_max` by jogging to ~1mm short of each physical
   limit. Update config; verify all four corners reachable.

## Phase 3 — Eddy XY offset (coil vs nozzle)

XY offset needs only ~±1mm accuracy (it shifts sample locations; zero effect on Z
accuracy). Measure mechanically from the Demon Remix CAD or calipers: coil center to
nozzle tip, per axis; `offset = coil_pos − nozzle_pos`. Optional refinement: scan across
a bed-screw head watching the frequency response; the response is symmetric around
center. Enter in `[probe_eddy_current btt_eddy]`.

## Phase 4 — Eddy Z calibration chain (order matters)

Primary path (mainline `probe_eddy_current`):
1. `LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy` (centered, ~20mm up, cold) → `SAVE_CONFIG`.
2. `PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy` (paper drag) → `SAVE_CONFIG`.
3. `G28 Z`, then `PROBE_ACCURACY` — expect single-digit-micron stddev at steady temp.
4. `QUAD_GANTRY_LEVEL` — babysit the first run; confirm all four probe points land on
   the bed with the new offsets.
5. `TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy TARGET=<temp>` with the bed heat-soaked
   (~100°C) for drift compensation.
6. `BED_MESH_CALIBRATE METHOD=rapid_scan` — sanity-check the mesh shape.

Alternative path (eddy-ng, as in the Demon guide): install vvuk/eddy-ng (Phase 0 step 6),
use the commented `[probe_eddy_ng btt_eddy]` block in printer.cfg instead of
`[probe_eddy_current]`, and follow https://github.com/vvuk/eddy-ng/wiki/Calibration.
Gains tap (nozzle-contact Z offset — the successor to Sovol's "virtual contact").
Note the Demon guide's eddy-ng block targets the STOCK toolhead coil on `extra_mcu`
(software i2c PB10/PB11 to dodge F103 i2c errata) — with the Eddy Duo those workarounds
don't apply; use the Duo's own MCU/i2c settings.

## Phase 4.5 — Buffer variant bench test (feeder MCU on mainline firmware)

1. Start with `buffer-synced.cfg`: long extrude → feeder follows, push switch toggles
   the trim, slack stays bounded over several meters.
2. Jam simulation (pinch the reverse-Bowden at the spool): PAUSE + `winding_status=True`
   + blue LED within ~5s.
3. Runout chain: withdraw filament at the inlet sensor → `CONTINUE_PRINT_D` counts down
   1100mm → M600 → tail spit-out.
4. If feed quality disappoints, swap the include to `buffer-pushed.cfg`; verify a
   mid-print push does NOT stutter XY.
5. Verify `FORCE_MOVE STEPPER="extruder_stepper filament_buffer"` (quoted name) works
   on this build — used by manual feed and unload in the synced variant.

## Phase 5 — First-layer Z offset

Eddy `z_offset` is trigger height (~2.5mm), not squish. Dial the first layer with a test
print + babystepping (`SET_GCODE_OFFSET Z_ADJUST=`), persist. On the eddy-ng path, tap
replaces most of this.

## Phase 5.5 — PLR power-cut test

1. Slicer start/end gcode must call `PRINT_START` / `PRINT_END`.
2. Sacrificial print to ~10mm, kill mains.
3. On boot: Mainsail prompt offers Resume/Discard; check `plr_state` is fresh first.
4. Resume: XY homes (Z must NOT), temps restore, nozzle returns to journaled XY/Z, seam
   ≤ one layer + 5s. Test absolute-E and M83 files. For 30-hour PETG-CF jobs this is
   the highest-value test on the list.

## Phase 6 — Dependent recalibrations

- Recompute `[bed_mesh]` bounds from measured offsets; enable `scan_overshoot` if X
  travel allows. `[safe_z_home] home_xy_position = (250 − x_offset, 250 − y_offset)`.
- `PID_CALIBRATE` hotend (target 250+ for PETG-CF) then bed.
- Verify Orbiter `rotation_distance` (100mm mark test), `SHAPER_CALIBRATE` (new toolhead
  mass), pressure advance for PETG-CF (start ~0.03–0.05; CF blunts it).
- Only then raise `max_accel` from 20000 toward stock's 40000 — watch for "Timer too
  close" (Sovol masked it; mainline reports honestly).

## Recovery (if a flash goes wrong)

- Klipper app reflash via ST-Link: correct build at start address `0x08020000` (H750).
- Overwritten bootloader: rebuild Katapult with `|| MACH_STM32H750` added to its
  `src/stm32/Kconfig` (128KiB section AND the flash-settings block at the bottom),
  full chip erase, Katapult at `0x08000000`, then Klipper at `0x08020000` — per the
  Demon guide's recovery section.
- Toolhead/buffer F103s: Moffy97 SBC-as-SWD method, no ST-Link needed.
- Nuclear option: swap in the spare pre-flashed Sovol eMMC.

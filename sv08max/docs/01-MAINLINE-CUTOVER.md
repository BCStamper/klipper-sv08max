# 01 — Mainline Cutover (stock toolhead stays on)

**What**: replace Sovol's Klipper with this fork on the existing host image, flash
the three existing MCUs, bring the printer back up on the stock toolhead.
**Why this shape**: the host image is kept (Demon method — no eMMC reimage risk);
the stock toolhead stays so every problem in this session is *software by
definition*. The config used here (`printer-stock-toolhead.cfg`) is also the
permanent fallback whenever the stock toolhead goes back on.
**Ends with**: a smoke-tested mainline printer. Full validation is doc 03.

## Prerequisites

- [ ] Live config backup exists (taken 2026-07-08; re-take if configs changed since)
- [ ] Spare eMMC sealed and on the shelf; ST-Link in the drawer
- [ ] An evening where a dead printer overnight is acceptable

## A. Host conversion

1. [ ] SSH in. Update KIAUH: `cd ~/kiauh && git pull`, run `~/kiauh/kiauh.sh`.
2. [ ] **Point KIAUH at the fork** (Settings `S`):
       `https://github.com/BCStamper/klipper-sv08max`, branch `sv08max-master`.
       *Why: installs our exact tree; also makes the Demon guide's hand-edit of
       src/stm32/Kconfig unnecessary — upstream master already allows the H750's
       128KiB bootloader.*
3. [ ] Remove Sovol Klipper (`3 Remove → 1 Klipper`), install from the fork
       (`1 Install → 1 Klipper`).
4. [ ] Extras: `4 Advanced → 5 Input Shaper` deps YES; `E Extensions → G-Code Shell
       Command → Install` (example: NO). *The fork already ships the module; the
       KIAUH extension is harmless duplication insurance.*
5. [ ] **Install eddy-ng NOW, before any firmware is built**:
       `cd ~ && git clone https://github.com/vvuk/eddy-ng && cd eddy-ng && ./install.sh`
       *Why the ordering: eddy-ng adds MCU-side sensor code to the Klipper tree.
       Firmware built without it cannot do eddy-ng probing — and the stock toolhead
       F103 hosts the probe coil in this stage.*
6. [ ] Deploy configs into `~/printer_data/config/`: `buffer-synced.cfg`,
       `buffer-pushed.cfg`, `plr.cfg`, `macros.cfg`, `plr.sh`, and
       **`printer-stock-toolhead.cfg` copied AS `printer.cfg`**.
       *Why a copy, not an include: the fallback must be restorable in one `cp` six
       months from now with zero archaeology. The repo's `printer.cfg` (new
       toolhead) deploys in doc 04.*
7. [ ] `sudo reboot`. A big red MCU-protocol error is EXPECTED — mainline klippy is
       now talking to Sovol-era MCU firmware. That's the cue for section B.

## B. Flash the three existing MCUs over CAN

*Why this works with no ST-Link: Katapult is already on every MCU — it's literally
Sovol's own update mechanism (doc 00, Hardware facts). Generic walkthrough:
[canbus.esoterical.online](https://canbus.esoterical.online).*

*Why this order: mainboard first (it's the CAN bridge — nothing else is reachable
until it runs current firmware); buffer LAST (only node where Katapult is inferred,
not vendor-proven — if its jump fails, everything else is already done and Moffy97
SBC-SWD is its dedicated recovery).*

1. [ ] Build mainboard firmware: `cd ~/klipper && make menuconfig` → STM32H750,
       **128KiB bootloader**, 25MHz crystal, **USB-to-CAN bridge (USB on
       PA11/PA12)**, CAN PB8/PB9, 1M. Optional GPIO init `!PB0,!PE11,!PE14`
       (*keeps aux/exhaust/bed fans silent at boot — mirrors Sovol's firmware
       behavior; no chamber heater fitted so boot-cooling is moot*). `make`.
2. [ ] Jump the mainboard:
       `~/klippy-env/bin/python ~/printer_data/build/flash_can.py -f ~/klipper/out/klipper.bin -u <current mainboard UUID>`
       — after ~5s it will appear as **USB serial** `/dev/serial/by-id/usb-katapult_stm32h750xx_*`
       (*the bridge personality drops in bootloader mode; this device existing IS
       the confirmation Katapult is real*). Flash:
       `flash_can.py -f ~/klipper/out/klipper.bin -d /dev/serial/by-id/usb-katapult_stm32h750xx_*`
3. [ ] Re-query: `~/klippy-env/bin/python ~/klipper/scripts/canbus_query.py can0`.
       *Why UUIDs change: Sovol's app firmware hardcoded fake UUIDs; Katapult and
       mainline report the real chip ID. Every flash in this project ends with a
       re-query.* Record the new mainboard UUID.
4. [ ] Stock toolhead F103: `make menuconfig` → STM32F103, Katapult offset (8KiB —
       confirm against what the jump reports), CAN PB8/PB9 @1M → build → jump by
       its current UUID → re-query → flash the NEW UUID (*CAN nodes rejoin the bus
       in Katapult mode under the real-chip-ID UUID — Sovol's own scripts re-query
       exactly like this*).
5. [ ] **Buffer F103 last**, same flow. If it never appears in Katapult mode after
       the jump command: STOP for this node, leave it, finish the session — recover
       it later via Moffy97. Everything else still works.
6. [ ] Optional host MCU: `make menuconfig` → Linux process → `make flash`; enable
       `klipper-mcu.service`.
7. [ ] Fill every `TODO_*_UUID` in the deployed configs (mainboard + stock toolhead
       in `printer.cfg`, buffer in the buffer variant file). `FIRMWARE_RESTART`.
       Expected: klippy connects to all three MCUs, no config errors.

## C. First-boot sanity (nothing hot, nothing homed)

*Stock geometry is known-good — no travel re-measurement in this stage. This list
is about wiring/firmware sanity only.*

- [ ] `QUERY_ENDSTOPS` — toggle X (switch on the toolhead) and Y by hand
- [ ] Extruder + bed thermistors read plausible room temp
- [ ] `ACCELEROMETER_QUERY` (stock LIS2DW)
- [ ] No i2c errors in `klippy.log` (*eddy-ng runs the coil on software i2c
      PB10/PB11 precisely to dodge the F103 hardware-i2c errata*)
- [ ] `STEPPER_BUZZ` each stepper (X, Y, Z×4, extruder)
- [ ] `M106 S128` spins BOTH part-cooling fans (the mapping macro), `M107` stops

## D. eddy-ng calibration on the stock coil

*Demon's tested flow for exactly this hardware; bed at temp because the coil's
response is temperature-sensitive and 60°C is the realistic printing state.*

```
SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET=60
TEMPERATURE_WAIT SENSOR=heater_bed MINIMUM=58 MAXIMUM=62
G28 X Y
PROBE_EDDY_NG_CALIBRATE DRIVE_CURRENT=15
SAVE_CONFIG
```

- [ ] `G28 Z` homes on the probe
- [ ] `PROBE_ACCURACY` — expect single-digit-micron stddev at steady temp
- [ ] Babysat `QUAD_GANTRY_LEVEL` (stock points, known-good)
- [ ] Tap setup per https://github.com/vvuk/eddy-ng/wiki/Calibration
- [ ] `BED_MESH_CALIBRATE METHOD=rapid_scan` — mesh shape sane, no edge cliffs

## E. Smoke test (gate to doc 02)

*Why only a smoke test here: the full battery (doc 03) runs after DKEU so it
exercises the final macro stack once. This gate just proves the software conversion
before the macro layer changes.*

- [ ] One small print (~30 min) completes: first layer good, no MCU errors, no
      "Timer too close" (*mainline reports these honestly; Sovol's firmware hid
      them — see doc 00*)
- [ ] Feeder followed filament demand during the print (green LED behavior normal)
- [ ] Screen observed: note what the panel shows against mainline (doc 03 does the
      full evaluation; `makerbase-client` stays running either way)

## Rollback (if the evening goes sideways)

Any single MCU bricked → its recovery path (doc 00, Safety nets). Whole-stage
rollback → swap the spare eMMC and reflash MCUs with Sovol firmware via the vendor
scripts... which is why the spare eMMC stays sealed until this doc is complete.

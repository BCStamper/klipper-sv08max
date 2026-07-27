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
- [ ] `df -h /` on the printer shows ≥1.5GB free. *Why: the eMMC root partition is
      only ~6.9GB total; KIAUH's repo-switch backup step alone can exhaust it,
      aborting mid-switch. If it's tight: `rm -rf ~/kiauh_backups`, clear apt/pip
      caches, and consider moving the print gcode library off root (it mounts a USB
      stick at `gcodes/sda1` for exactly this).*

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
5. [ ] **Skip eddy-ng.** Originally this step installed it before any firmware
       build. As of this writing eddy-ng's `start_probe_session()` has a confirmed
       upstream bug (vvuk/eddy-ng#146) that makes first-time Z homing on current
       Klipper master impossible — full root-cause writeup in
       `01-DIVERGENCES.md`. This stage uses mainline's own `probe_eddy_current`
       instead (section D), which needs nothing installed beyond the fork itself.
       *If you're revisiting this after #146 is fixed upstream and want tap back:
       `cd ~ && git clone https://github.com/vvuk/eddy-ng && cd eddy-ng &&
       ./install.sh`, done before any firmware build (it adds MCU-side sensor
       code), then swap the probe section per `01-DIVERGENCES.md`'s notes.*
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
2. [ ] Confirm `python3-serial` is installed (`sudo apt-get install python3-serial`)
       — needed for the `-d` serial flash below; easy to miss since the CAN-based
       flashes elsewhere in this doc don't need it.
3. [ ] Jump the mainboard:
       `~/klippy-env/bin/python ~/printer_data/build/flash_can.py -f ~/klipper/out/klipper.bin -u <current mainboard UUID>`
       — after ~5s it will appear as **USB serial** `/dev/serial/by-id/usb-katapult_stm32h750xx_*`
       (*the bridge personality drops in bootloader mode; this device existing IS
       the confirmation Katapult is real*). Flash:
       `flash_can.py -f ~/klipper/out/klipper.bin -d /dev/serial/by-id/usb-katapult_stm32h750xx_*`
       *Single-shot only for this MCU specifically — it's a CAN bridge, so it drops
       off `can0` the moment it jumps. If you instead run the plain `-u` one-shot
       form (jump+flash combined) on the mainboard, it'll fail trying to reconnect
       over a bus it just left; the jump still succeeded, just finish with `-d` as
       shown. The toolhead and buffer MCUs below are plain CAN nodes and the
       combined `-u` one-shot form works fine on them.*
4. [ ] Re-query: `~/klippy-env/bin/python ~/klipper/scripts/canbus_query.py can0`.
       *Why UUIDs change: Sovol's app firmware hardcoded fake UUIDs; Katapult and
       mainline report the real chip ID. Every flash in this project ends with a
       re-query.* Record the new mainboard UUID.
5. [ ] Stock toolhead F103: `make menuconfig` → STM32F103, **8KiB bootloader**,
       CAN PB8/PB9 @1M → build → jump by its current UUID → re-query → flash the
       NEW UUID (*CAN nodes rejoin the bus in Katapult mode under the real-chip-ID
       UUID — Sovol's own scripts re-query exactly like this*). 8KiB confirmed
       correct via this exact printer's toolhead flash (its own Katapult connect
       banner reported `Application Start: 0x8002000` = 8KiB).
6. [ ] **Buffer F103 last**, same flow. If it never appears in Katapult mode after
       the jump command: STOP for this node, leave it, finish the session — recover
       it later via Moffy97. Everything else still works. (On this printer it
       worked fine, same 8KiB offset, confirmed the same way — but it remains the
       one node with no vendor-script proof, so keep the caution.)
7. [ ] Optional host MCU: `make menuconfig` → Linux process → `make flash`; enable
       `klipper-mcu.service`.
8. [ ] Fill every `TODO_*_UUID` in the deployed configs (mainboard + stock toolhead
       in `printer.cfg`, buffer in the buffer variant file). `FIRMWARE_RESTART`.
       Expected: klippy connects to all three MCUs, no config errors.

> ⚠️ **If `canbus_query.py` ever reports 0 nodes after a restart** (host reboot,
> `sudo service klipper restart`, or a `SAVE_CONFIG`-triggered restart) — this does
> NOT mean the flash failed. CAN-connected MCUs that stay powered through a host-only
> restart remember their previous session's node-ID binding and won't respond to a
> fresh discovery broadcast. **Full power cycle (mains switch, not just a reboot)**
> resets them to unbound/discoverable state. This bit us hard during this project's
> own first attempt — don't waste time re-flashing a node that's actually fine.

## C. First-boot sanity (nothing hot, nothing homed)

*Stock geometry is known-good — no travel re-measurement in this stage. This list
is about wiring/firmware sanity only.*

- [ ] `QUERY_ENDSTOPS` — toggle X (switch on the toolhead) and Y by hand
- [ ] Extruder + bed thermistors read plausible room temp
- [ ] `ACCELEROMETER_QUERY` (stock LIS2DW)
- [ ] No i2c errors in `klippy.log` (*the probe runs the coil on software i2c
      PB10/PB11 precisely to dodge the F103 hardware-i2c errata — this is a
      Klipper-core `bus.py` capability, not tied to any specific probe driver,
      so it applies the same way regardless of which probe section is active*)
- [ ] `STEPPER_BUZZ` each stepper (X, Y, Z×4, extruder)
- [ ] `M106 S128` spins BOTH part-cooling fans (the mapping macro), `M107` stops

## D. probe_eddy_current calibration on the stock coil

*Why `probe_eddy_current` and not eddy-ng: confirmed via direct source read that
eddy-ng's `start_probe_session()` unconditionally uses a scan-only session that
requires Z already homed — circular, blocks first-time homing entirely. Matches
the open, unresolved vvuk/eddy-ng#146. Verified neither `main` nor `eng-work`
fixes it. `probe_eddy_current` is mainline, stable, and DKEU (doc 02) has
first-class support for it under this exact object name (`eddy`) — the only real
loss is tap. Full story in `01-DIVERGENCES.md`.*

Bed at temp because the coil's response is temperature-sensitive and 60°C is the
realistic printing state:

```
SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET=60
TEMPERATURE_WAIT SENSOR=heater_bed MINIMUM=58 MAXIMUM=62
G28 X Y
G90
G1 X250 Y250 F6000
```

> ⚠️ **Never skip that last travel line.** `G28 X Y` alone leaves the toolhead at
> whatever corner the endstops physically are (X≈-11, Y≈505 on this printer) — off
> the bed entirely. Skipping this step is exactly what caused a real Z-into-bed
> collision during this project's own first attempt at this doc. See
> `01-DIVERGENCES.md` if you want the full incident report. If any Z collision
> ever does happen, check the gantry didn't rack before trusting further
> calibration — same doc has the manual shim-and-push leveling check that fixed it.

Z isn't homed yet. Raise it to a comfortable height with small watched `FORCE_MOVE`
steps (all four Z steppers together — see `00-OVERVIEW.md` if this is unfamiliar),
then tell Klipper to trust that position:

```
SET_KINEMATIC_POSITION
```

> ⚠️ **This step is required, not optional, for `probe_eddy_current`.** `TESTZ`
> (the manual paper-touch jogging used below) moves through the exact same
> per-axis "is this trustworthy" check as any other move. `FORCE_MOVE` updates
> Klipper's tracked position but never sets that flag — only real homing or
> `SET_KINEMATIC_POSITION` does. Skip this and calibration fails with "Z axis must
> be homed before probing" / "Must home axis first", which looks like a bug but
> isn't — it's `corexy.py` correctly enforcing a check with a missing prerequisite.
> Do this move *immediately* before the calibration commands below, with nothing
> else in between — repeated `G28 X Y` calls have been observed to nudge Z up a
> couple mm each time (client-side Mainsail dashboard behavior, not this repo's
> config, but it means a Z value trusted several homing-attempts ago may be stale;
> re-verify clearance visually if in doubt before trusting it).

```
LDC_CALIBRATE_DRIVE_CURRENT CHIP=eddy
PROBE_EDDY_CURRENT_CALIBRATE CHIP=eddy
```

Paper-touch test when the manual-probe prompt appears, `ACCEPT` once the paper
just catches. Then:

```
SAVE_CONFIG
```

- [ ] `G28 X Y` then `G28 Z` homes cleanly on the probe (the `SAVE_CONFIG` restart
      wiped the `SET_KINEMATIC_POSITION` bootstrap — this is now a real homing
      attempt using persisted calibration data, not a workaround)
- [ ] `PROBE_ACCURACY` — expect single-digit-micron stddev at steady temp
- [ ] Babysat `QUAD_GANTRY_LEVEL` (stock points, known-good)
- [ ] `BED_MESH_CALIBRATE METHOD=rapid_scan` — mesh shape sane, no edge cliffs.
      **If you see sharp spikes (order of 1mm+) concentrated on one edge/row,
      check the removable bed plate is fully seated before suspecting the probe,
      offsets, or mesh bounds** — this exact symptom, on this exact printer, was
      the plate resting on its own rear retention stops, not a sensing or config
      problem. Full story in `01-DIVERGENCES.md`.

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
- [ ] **Expect to babystep the Z offset up noticeably from the calibrated value**
      for a good first layer — this is normal, not a calibration failure.
      `z_offset`/the eddy trigger height is not the same thing as first-layer
      squish; dial it in with a real print the same way you would on any probe.
- [ ] **Watch the hotend fan across a cancel/pause, not just during printing.**
      On this printer's first real print, the fan ran fine while printing but cut
      off *instantly* on `CANCEL_PRINT` while the nozzle was still ~265°C — a real
      heat-creep/clog risk on long prints, still unresolved as of this writing.
      Leading hypothesis (unverified): `CANCEL_PRINT`'s `TURN_OFF_HEATERS` zeroes
      the extruder *target* instantly, and `heater_fan` may key off "heater
      active" rather than measured temperature. Check `~/klipper/klippy/extras/
      fan.py`'s actual on/off logic before changing anything. Also separately
      observed: the fan sat dead still for the first couple of layers despite the
      extruder being well above its 45°C threshold, then started on its own —
      unclear yet if same root cause. Full details in `01-DIVERGENCES.md`.

## Rollback (if the evening goes sideways)

Any single MCU bricked → its recovery path (doc 00, Safety nets). Whole-stage
rollback → swap the spare eMMC and reflash MCUs with Sovol firmware via the vendor
scripts... which is why the spare eMMC stays sealed until this doc is complete.

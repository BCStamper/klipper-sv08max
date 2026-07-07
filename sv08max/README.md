# Sovol SV08 MAX on Mainline Klipper (master-tracking)

This branch (`sv08max-master`) tracks **upstream Klipper master** — the motion_queuing
era — for a Sovol SV08 MAX with its auxiliary filament buffer and power-loss recovery
rebuilt as **pure config**, targeting a custom toolhead: Yavoth Demon Remix / BTT EBB36
CAN v1.2 (MAX31865 + onboard ADXL345) / BTT Eddy Duo (CAN) / Phaetus Rapido 2 UHF Plus
(PT100) / LDO Orbiter v2.5.

## Philosophy

Sovol's fork carried ~40 modified core files. The previous attempt (`sv08max-mainline`,
kept for reference) ported their `buffer_stepper.py` module onto v0.13.0 — but that
module is incompatible with the motion_queuing rework on master (post 2025-08-11), which
removed `MCU.flush_moves` and `MCU_stepper.generate_steps`. Rather than trade one static
branch for another, this branch shrinks the delta to:

| Delta | Why |
|---|---|
| `klippy/extras/gcode_shell_command.py` | Out-of-tree community module (PLR + utility scripts); no motion coupling |
| `sv08max/` | Config overlay + docs (this directory) |

That's it. No motion code, no Kconfig patch (upstream master already supports the
H750's 128KiB bootloader). Rebasing onto any future master is expected to be trivial.

## The filament buffer, rebuilt as config

Two interchangeable variants (include exactly one from `printer.cfg`):

- **`buffer-synced.cfg` (recommended)** — the AFC TurtleNeck pattern: the feeder runs as
  an `[extruder_stepper]` synced to the extruder; the push switch trims effective
  rotation_distance ±10% (bang-bang follower). Smoothest feed, zero mid-print gcode
  injection. Clog-at-extruder detection is delegated to the Orbiter toolhead motion
  sensor.
- **`buffer-pushed.cfg` (fallback)** — faithful to Sovol's behavior: discrete 25mm
  `MANUAL_STEPPER` pushes on switch trigger, plus the stock extrusion-without-pushes
  clog heuristic. Bench-verify pushes don't stutter XY.

Both keep the stock UI contract: sensor named `filament_sensor`, `variables` macro
flags (`winding_status`, `plug_status`), LED pins, jam/runout semantics, and the
1100mm runout tail-consumption chain (`CONTINUE_PRINT_D`).

## Power-loss recovery, rebuilt as config + shell

`plr.cfg` + `plr.sh`: a `delayed_gcode` journals `{file byte offset, Z, XY, temps, fan}`
to `save_variables` every 5s while printing; on boot after an interruption, a
Mainsail/Fluidd prompt offers resume; `plr.sh` regenerates a trimmed file seeking by
**byte offset** (more robust than Sovol's text-match seek) with extrusion-mode-aware
`G92 E` restore. Zero core patches; loses at most ~5s of print. Slicer contract:
start/end gcode call `PRINT_START` / `PRINT_END`.

## Branches in this repo

- `sv08max-master` — this branch. Current.
- `sv08max-mainline` — previous approach: v0.13.0 + ported buffer_stepper.py module.
  Kept as reference/fallback; do not merge it past v0.13.0.
- `sovol-stock-fork` — faithful reconstruction of Sovol's shipped fork on its true base
  (mainline `a91d8a66f`, identified by full-tree blob matching) for diffing.

Sovol MCU facts: mainboard STM32H750 (USB-to-CAN bridge), toolhead + buffer STM32F103
(CAN on PB8/PB9), all CAN at 1M. Stock firmware hardcodes CAN UUIDs — re-query after
flashing mainline.

## Status

- [x] Buffer rebuilt as config, both variants drafted
- [x] PLR rebuilt as config + shell
- [ ] Bench test: EBB36 + Eddy Duo on CAN
- [ ] Bench test: buffer variants on the feeder MCU (pick winner)
- [ ] Power-cut PLR test
- [ ] H750 mainboard flash procedure (undocumented for the MAX — research before cutover)
- [ ] Full bring-up per `BRINGUP.md`

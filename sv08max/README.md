# Sovol SV08 MAX on Mainline Klipper (master-tracking)

This branch (`sv08max-master`) tracks **upstream Klipper master** for a Sovol SV08 MAX
with the auxiliary filament buffer and power-loss recovery rebuilt as **pure config**,
targeting a custom toolhead: Yavoth Demon Remix (custom carriage adapter, Sovol
steel-plate mount retained) / BTT EBB36 CAN v1.2 (MAX31865 + onboard ADXL345) / BTT
Eddy Duo (CAN) / Phaetus Rapido 2 UHF Plus (PT100) / LDO Orbiter v2.5.

Install path: **3DPrintDemon's "Mainline Your MAX" method** (stock Sovol eMMC kept,
Klipper swapped via KIAUH, MCUs flashed over CAN — Katapult ships preinstalled on MAX
MCUs), with KIAUH pointed at THIS fork instead of upstream. See `BRINGUP.md` for the
full sequence and the Demon guide in
`3DPrintDemon/Demon_Klipper_Essentials_Unified` for the method's origin — consider
supporting his Patreon.

## Philosophy

Sovol's fork carried ~40 modified core files. Their `buffer_stepper.py` module is
incompatible with the motion_queuing rework on master (post 2025-08-11: removed
`MCU.flush_moves`, `MCU_stepper.generate_steps`). Rather than trade one static branch
for another, this branch shrinks the delta to:

| Delta | Why |
|---|---|
| `klippy/extras/gcode_shell_command.py` | Out-of-tree community module (PLR + utility scripts); no motion coupling |
| `sv08max/` | Config overlay + docs (this directory) |

No motion code. No Kconfig patch — upstream master already allows the H750's 128KiB
bootloader, which also makes the Demon guide's manual `nano` Kconfig step unnecessary
when installing from this fork.

## Installing via KIAUH (Demon method, step 3)

In KIAUH Settings, set the Klipper source to this repo and branch:

```
Repo: https://github.com/BCStamper/klipper-sv08max
Branch: sv08max-master
```

Then remove Sovol Klipper and install as usual. Deploy `sv08max/*.cfg` + `plr.sh` into
`~/printer_data/config/`.

## The filament buffer, rebuilt as config

Two interchangeable variants (include exactly one from `printer.cfg`):

- **`buffer-synced.cfg` (recommended)** — AFC TurtleNeck pattern: feeder runs as an
  `[extruder_stepper]` synced to the extruder; the push switch trims effective
  rotation_distance ±10% (bang-bang follower). Smoothest feed, zero mid-print gcode
  injection. Clog detection delegated to the Orbiter toolhead motion sensor.
- **`buffer-pushed.cfg` (fallback)** — faithful to Sovol's behavior: discrete 25mm
  `MANUAL_STEPPER` pushes plus the stock extrusion-without-pushes clog heuristic.

Both preserve the stock UI contract: sensor named `filament_sensor`, `variables` macro
flags (`winding_status`, `plug_status`), LED pins, jam/runout semantics, and the 1100mm
runout tail-consumption chain (`CONTINUE_PRINT_D`).

## Power-loss recovery, rebuilt as config + shell

`plr.cfg` + `plr.sh`: a `delayed_gcode` journals `{file byte offset, Z, XY, temps, fan}`
to `save_variables` every 5s while printing; on boot after an interruption a
Mainsail/Fluidd prompt offers resume; `plr.sh` regenerates a trimmed file seeking by
**byte offset** (more robust than Sovol's text-match seek) with extrusion-mode-aware
`G92 E` restore. Zero core patches; ≤~5s of print lost. Slicer start/end gcode must
call `PRINT_START` / `PRINT_END`.

## Rebasing on upstream (the point of this design)

```
git fetch origin            # origin = Klipper3d/klipper
git rebase origin/master    # 2 commits replay; conflicts are unlikely by construction
```

After any rebase, re-verify only three things: `gcode_shell_command.py` still imports
(`python3 -m py_compile`), `SYNC_EXTRUDER_MOTION` / `SET_EXTRUDER_ROTATION_DISTANCE`
still exist (buffer-synced), and `MANUAL_STEPPER` semantics unchanged (buffer-pushed).
Everything else is config against stable user-facing interfaces.

## Branches in this repo

- `sv08max-master` — this branch. Current.
- `sv08max-mainline` — first approach: v0.13.0 + ported buffer_stepper.py module.
  Fallback only; do not merge past v0.13.0 (motion_queuing breaks the module).
- `sovol-stock-fork` — faithful reconstruction of Sovol's shipped fork on its true base
  (mainline `a91d8a66f`, found by full-tree blob matching) for diffing. Also preserves
  Sovol's MCU build configs (note: their `FLASH_START_0000` contradicts the
  Katapult-preinstalled evidence — stale factory-direct builds; mirror them for
  pin/feature selections only, never for flash offsets; see BRINGUP Phase 0.75).

Hardware facts: mainboard STM32H750 (USB-to-CAN bridge, app at 0x08020000), toolhead +
buffer STM32F103 (CAN PB8/PB9), all CAN at 1M. Stock firmware hardcodes CAN UUIDs —
re-query after every flash (Katapult mode reports a different, real-chip-ID UUID).
X endstop: physical switch on the EBB36 endstop header (decided; sensorless is
impossible — no TMC5160 DIAG routing; mainboard PD6 spare endstop port is the
documented alternative). No chamber heater on this machine (`hot_mcu` intentionally
absent).

## Status

- [x] Buffer rebuilt as config, both variants drafted
- [x] PLR rebuilt as config + shell (script smoke-tested)
- [x] Flash procedure CONFIRMED: Katapult is Sovol's own OTA mechanism
      (`~/printer_data/build/flash_can.py` + vendor update scripts; see BRINGUP 0.75)
- [ ] Bench test: EBB36 + Eddy Duo on CAN
- [ ] Bench test: buffer variants on the feeder MCU (pick winner)
- [ ] Power-cut PLR test
- [ ] Full bring-up per `BRINGUP.md`

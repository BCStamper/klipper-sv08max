# Sovol SV08 MAX on Mainline Klipper

This branch (`sv08max-mainline`) is mainline Klipper v0.13.0 plus the minimum needed
to run a Sovol SV08 MAX with its auxiliary filament buffer, targeting a custom toolhead:
Yavoth Demon Remix / BTT EBB36 CAN v1.2 (MAX31865 + onboard ADXL345) / BTT Eddy Duo (CAN) /
Phaetus Rapido 2 UHF Plus (PT100) / LDO Orbiter v2.5.

## What's added over v0.13.0

| Change | What it does |
|---|---|
| `klippy/extras/buffer_stepper.py` | Sovol's auxiliary filament feeder module, ported from their fork (two bug fixes; see commit) |
| `klippy/extras/gcode_shell_command.py` | Standard community module (Sovol config scripts use it) |
| `src/stm32/Kconfig` | One-liner: allow 128KiB bootloader on STM32H750 (SV08 MAX mainboard) |
| `sv08max/` | This directory: draft printer configs + bring-up plan |

## Config set (`sv08max/`)

- `printer.cfg` — full draft; `TODO` markers for CAN UUIDs, travel limits, probe offsets, PID
- `buffer_stepper.cfg` — feeder hardware + its macro contract
- `macros.cfg` — compatibility layer (runout tail-consumption chain, feeder-aware PAUSE/RESUME)
- `BRINGUP.md` — phased bring-up & offset-calibration plan

## Provenance

Sovol ships their fork as a plain tree with no git history. Its true base was identified as
mainline commit `a91d8a66f` (2024-10-30) by full-tree blob matching (1875/2043 files
identical). The faithful reconstruction of their fork lives on the `sovol-stock-fork`
branch of this repo for diffing/cherry-picking. The feeder module was ported from there
and verified against v0.13.0 APIs.

Sovol MCU facts (from their build configs, preserved on `sovol-stock-fork`):
mainboard STM32H750 (USB-to-CAN bridge, 128KiB bootloader), toolhead + buffer STM32F103
(CAN on PB8/PB9), all CAN at 1M. Stock firmware hardcodes CAN UUIDs — mainline builds
derive real ones, so UUIDs must be re-queried after flashing.

## Status

- [x] Module port, syntax-checked
- [x] Draft configs
- [ ] Bench test: EBB36 + Eddy Duo on CAN
- [ ] Buffer MCU on mainline firmware with ported module
- [ ] H750 mainboard flash procedure (undocumented for the MAX — research before cutover)
- [ ] Full bring-up per `BRINGUP.md`

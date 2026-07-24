# 00 — Project Overview: SV08 MAX on Mainline Klipper

**Read this once before any work session. The numbered docs are the work sessions.**

## What this project is

Migrate a Sovol SV08 MAX from Sovol's frozen Klipper fork to mainline (this fork:
upstream master + a 2-file delta), preserving the two Sovol features upstream never
had — the auxiliary filament buffer and power-loss recovery — then swap in a custom
toolhead. Workload target: long (30hr) PETG-CF prints. **Reliability > features.**

## Why it's built the way it is

- **Track upstream master, not a pinned release** — Sovol's fork died by freezing.
  Our entire delta is `gcode_shell_command.py` + this config/docs overlay, so
  rebasing is trivial forever. (There is still no stable release containing the
  motion_queuing rework; master is where current Klipper lives.)
- **Buffer rebuilt as pure config, not a module** — Sovol's `buffer_stepper.py`
  broke against the 2025-08-11 motion_queuing rework and *will* break again with
  any custom motion code. Config primitives (`extruder_stepper` sync /
  `manual_stepper`) are upstream-maintained APIs. Two variants exist; doc 03 picks
  the winner on the bench.
- **PLR rebuilt as config + shell, zero core patches** — journals byte offset + state
  to `save_variables` every 5s; `plr.sh` regenerates a resume file. More robust seek
  than Sovol's (byte offset vs text match), loses ≤5s of print.
- **eddy-ng as the probe stack, both toolheads** — tap gives nozzle-contact Z that
  self-corrects for CF-induced nozzle wear (a drifting-first-layer killer on this
  workload). One stack, two coils: stock Sovol coil (doc 01), Eddy Duo (doc 04).
- **Staged migration** — each doc changes ONE layer, so every failure has an obvious
  suspect: 01 = software, 02 = macros, 03 = nothing (validation only), 04 = new
  hardware.
- **One-shot flashing per stage** — no pre-baked binaries; each stage flashes its
  own MCUs in document order so done-vs-pending is always obvious.

## The work sessions

| Doc | Session | Changes | Ends with |
|---|---|---|---|
| [01](01-MAINLINE-CUTOVER.md) | Mainline cutover | Host software + 3 MCU firmwares | Smoke-tested mainline printer, stock toolhead |
| [02](02-DKEU-INTEGRATION.md) | DKEU macro pack | Macro layer only | DKEU-orchestrated printing |
| [03](03-STOCK-VALIDATION.md) | Full validation | Nothing — testing only | Exit criteria passed; print until bored |
| [04](04-TOOLHEAD-CHANGEOVER.md) | Toolhead swap | Hardware + 2 new MCUs + config | The real machine |

Why DKEU (02) comes *before* full validation (03): the test battery then exercises
the final macro stack once, instead of twice. Fault isolation is preserved by the
smoke test at the end of 01 — if 02 breaks something the smoke test passed, the
suspect is the macro integration.

## Hardware facts (established by analysis + on-unit verification)

| Fact | Detail |
|---|---|
| Host | Allwinner/sunxi SBC, Sovol Debian image (kept — no reimage), `sovol@192.168.8.243` via Tailscale subnet |
| Mainboard | STM32H750, USB-to-CAN bridge (gs_usb → `can0`), app at `0x08020000` |
| CAN | All nodes 1M; F103s on PB8/PB9. Termination: exactly two 120Ω on the bus (relevant only in doc 04 when nodes change) |
| Bootloaders | **Katapult on all MCUs — it IS Sovol's own OTA mechanism** (their `~/printer_data/build/flash_can.py` + jump scripts; verified on this unit). H750's Katapult presents as USB serial `usb-katapult_stm32h750xx_*` |
| UUIDs | Sovol app firmware hardcodes them; Katapult mode and mainline use REAL chip IDs → **re-query after every jump and every flash** |
| Buffer MCU | F103; has NO vendor update path anywhere (factory-flashed once) — Katapult inferred, unproven until first jump → flashed LAST, Moffy97 SBC-SWD as its recovery |
| X endstop | Sensorless impossible (no TMC5160 DIAG routing — pin PDF verified). Stock switch on toolhead (01–03); new switch on EBB36 PB6 (04); mainboard PD6 = spare port alternative |
| Chamber heater | Not fitted on this machine — no `hot_mcu` anywhere |
| Screen | Serial HMI panel on `/dev/ttyS4` driven by `makerbase-client` (Moonraker API client). **Stays running** — future integration hook. KlipperScreen on the image is vestigial (no display attached); an HDMI touchscreen later is the penciled-in upgrade |

## Repo & directory map (when lost, start here)

| Where | What it is |
|---|---|
| **[BCStamper/klipper-sv08max](https://github.com/BCStamper/klipper-sv08max)** | **THE project.** Klipper fork; branch `sv08max-master` (default) = upstream master + 2-file delta + the `sv08max/` overlay and these docs. `sv08max-mainline` = old v0.13.0 module-port fallback (never merge past v0.13.0). `sovol-stock-fork` = faithful reconstruction of Sovol's fork for diffing. `master` = clean upstream tracking |
| [BCStamper/sv08max-reference-docs](https://github.com/BCStamper/sv08max-reference-docs) | Vendor reference fork (was named `SV08MAX` — renamed 2026-07-09 to end the confusion; old URLs redirect). PDFs, CAD, pin maps, Sovol's shipped-image snapshot. Nothing here runs on the printer |
| Local `References/SV08MAX` | Clone of the reference-docs repo (folder keeps the old name). Also holds `live-backup/` — local-only, gitignored, contains the Obico token |
| Local `References/klipper` | Working clone where the fork's branches are built (`origin` = Klipper3d, `fork` = klipper-sv08max) |
| Local `References/Rappetor-SV08-Mainline` | Community guide for the REGULAR SV08 (renamed from the misleading `Mainline_MAX`) — reference only |
| The printer | `sovol@192.168.8.243` (SPI-XI, via Tailscale subnet) |

Rule of thumb: **if it configures or runs the printer, it lives in klipper-sv08max;
if it documents Sovol's hardware, it lives in reference-docs.**

## Standing warnings

- ⚠ **Never tap update/OTA on the touchscreen.** The vendor endpoint currently
  serves a TEST manifest for a different printer, and the updater installs on any
  version mismatch. (Post-cutover the version check fails safely. Still don't.)
- ⚠ `live-backup/` (local, on the Mac) contains `moonraker-obico.cfg` with the
  Obico auth token — never push it unscrubbed.
- The published Sovol source (2.0.1) lags shipped firmware (2.1.9) by ~9 months;
  drift that mattered has been mirrored into this overlay already.

## Decision log

| Date | Decision |
|---|---|
| 2026-07-02 | Mainline migration; GitHub fork created |
| 2026-07-07 | Track master (motion_queuing); buffer as pure config (AFC pattern study); PLR restored, poller design; Demon flash method adopted; EBB36 PB6 X endstop |
| 2026-07-08 | Staged migration (this doc set); eddy-ng both stages; makerbase-client stays; one-shot flashing per stage; DKEU added as its own stage; HDMI/KlipperScreen penciled for the future |

## Safety nets (all stages)

Spare pre-flashed Sovol eMMC (full factory rollback, on hand) · ST-Link V2 +
STM32CubeProgrammer (on hand) · live config backup taken 2026-07-08 ·
[Moffy97 SBC-as-SWD recovery](https://github.com/Moffy97/sovol-sv08max-toolhead-recovery)
(toolhead/buffer F103s, no ST-Link needed) · Klipper reflash address `0x08020000`;
Katapult rebuild needs `|| MACH_STM32H750` in its Kconfig (128KiB + flash-settings
sections), erase, `0x08000000`.

Credit where due: the flash method and the stock-coil eddy-ng config come from
[3DPrintDemon's guide](https://github.com/3DPrintDemon/Demon_Klipper_Essentials_Unified)
— support his Patreon.

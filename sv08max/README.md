# Sovol SV08 MAX on Mainline Klipper (master-tracking)

This branch (`sv08max-master`) tracks **upstream Klipper master** for a Sovol SV08 MAX,
running mainline instead of Sovol's stock/factory fork, with [DKEU](https://github.com/3DPrintDemon/Demon_Klipper_Essentials_Unified)
(3DPrintDemon's macro pack) for print orchestration and a from-scratch, zero-core-patch
power-loss-recovery rebuild. Targeting a custom toolhead: Yavoth Demon Remix (custom
carriage adapter, Sovol steel-plate mount retained) / BTT EBB36 CAN v1.2 (MAX31865 +
onboard ADXL345) / BTT Eddy Duo (CAN) / Phaetus Rapido 2 UHF Plus (PT100) / LDO Orbiter
v2.5.

Install path: **3DPrintDemon's "Mainline Your MAX" method** (stock Sovol eMMC kept,
Klipper swapped via KIAUH, MCUs flashed over CAN — Katapult ships preinstalled on MAX
MCUs), with KIAUH pointed at THIS fork instead of upstream. See `sv08max/docs/` (via
`00-OVERVIEW.md`) for the full sequence and the Demon guide in
`3DPrintDemon/Demon_Klipper_Essentials_Unified` for the method's origin — consider
supporting his Patreon.

**For deep technical detail** (the eddy-probe calibration ceiling, why the filament
buffer is shelved, DKEU integration gotchas, Klipper-internals facts learned the hard
way) — Claude Code sessions working on this printer should consult the
`sv08-max-mainline-klipper` skill (personal, not tracked in this repo) and the
`NN-DIVERGENCES.md` companion docs alongside each numbered stage doc. This README stays
intentionally high-level.

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
`~/printer_data/config/`, then follow DKEU's own installer for the macro pack (doc 02).

## Staged migration — the runbook is `sv08max/docs/` (index: `00-OVERVIEW.md`)

Four work sessions, one numbered doc each, each with the what/why/how:
**[01 mainline cutover](sv08max/docs/01-MAINLINE-CUTOVER.md)** (stock toolhead stays;
deploy **`printer-stock-toolhead.cfg` as `printer.cfg`** — also the permanent
fallback) → **[02 DKEU](sv08max/docs/02-DKEU-INTEGRATION.md)** (macro pack integration
— ran far deeper than originally scoped, see `02-DIVERGENCES.md`) → **[03
validation](sv08max/docs/03-STOCK-VALIDATION.md)** (PLR power-cut test, screen
evaluation — buffer-variant selection no longer applies, see below) → **[04 toolhead
changeover](sv08max/docs/04-TOOLHEAD-CHANGEOVER.md)** (EBB36/Eddy Duo; deploy the
repo's `printer.cfg`). Overview, hardware facts, and the decision log live in
**[00](sv08max/docs/00-OVERVIEW.md)**.

Probe stack is mainline's own **`probe_eddy_current`** (object name `eddy`) on **both**
stages — not eddy-ng. eddy-ng was tried first and hit a confirmed, still-open upstream
bug ([vvuk/eddy-ng#146](https://github.com/vvuk/eddy-ng/issues/146)) that blocks
first-time Z homing. This stopped mattering once mainline's own `probe_eddy_current`
gained native **tap** support (nozzle-contact Z, self-corrects CF nozzle wear —
`PROBE_EDDY_CURRENT_TAP_CALIBRATE`), already present in this fork — no eddy-ng install
needed anywhere. Full story: `01-DIVERGENCES.md`, `02-DIVERGENCES.md`, and the skill's
`eddy-probe.md`. The vendor screen client (`makerbase-client`) intentionally stays
running post-cutover — it's a Moonraker API client and a future integration hook.

## The filament buffer — tried, rebuilt three times, shelved

Sovol's stock buffer drove the feeder via a direct MCU API (`self.mcu.flush_moves()`)
that mainline's `motion_queuing` rework removed outright. This project rebuilt it from
scratch three separate times — synced-to-extruder, discrete `manual_stepper` pushes,
then a registered gcode axis — each attempt cleared a real, distinct Klipper limitation
(a mechanical mismatch with the feeder's actual tension-sensing design, `FORCE_MOVE`'s
blocking `dwell()`, `manual_stepper`'s unconditional `sync_print_time()` flush) before
hitting a genuinely structural one: non-kinematic moves don't get real junction-velocity
planning in Klipper's shared lookahead queue, so any inserted buffer move forces the next
real print move to plan from a dead stop. Fixing that needs actual Klipper `extras`
source work (a separate trapq timeline), not more config — so the buffer is **shelved**
as of 2026-08-19, not carried forward. `buffer-synced.cfg`/`buffer-pushed.cfg` and
`macros.cfg` remain in this repo for reference but are not included by either active
`printer*.cfg`. Full account: the skill's `filament-buffer.md`.

## Power-loss recovery, rebuilt as config + shell

`plr.cfg` + `plr.sh`: a `delayed_gcode` journals `{file byte offset, Z, XY, temps, fan}`
to `save_variables` every 5s while printing; on boot after an interruption a
Mainsail/Fluidd prompt offers resume; `plr.sh` regenerates a trimmed file seeking by
**byte offset** (more robust than Sovol's text-match seek) with extrusion-mode-aware
`G92 E` restore. Zero core patches; ≤~5s of print lost. DKEU owns the slicer start/end
gcode contract (`DEMON_START`/`DEMON_END`) — this project's PLR hooks
(`save_last_file`/`was_interrupted`/journal start-stop) live inside DKEU's own
`Demon_User_Files/demon_custom_expansion_v2.0.0.cfg` hook system
(`_CUSTOM_PRE_START`/`_CUSTOM_POST_END`), not as standalone `PRINT_START`/`PRINT_END`
macros. **Not yet tested end-to-end** (a real mains-power-cut mid-print) — see doc 03.

## Rebasing on upstream (the point of this design)

```
git fetch origin            # origin = Klipper3d/klipper
git rebase origin/master    # 2 commits replay; conflicts are unlikely by construction
```

After any rebase, re-verify `gcode_shell_command.py` still imports
(`python3 -m py_compile`) and that `probe_eddy_current`'s tap-related API
(`PROBE_EDDY_CURRENT_TAP_CALIBRATE`, `METHOD=tap`) is still present — everything else is
config against stable user-facing interfaces.

## Branches in this repo

- `sv08max-master` — this branch. Current.
- `sv08max-mainline` — first approach: v0.13.0 + ported buffer_stepper.py module.
  Fallback only; do not merge past v0.13.0 (motion_queuing breaks the module).
- `sovol-stock-fork` — faithful reconstruction of Sovol's shipped fork on its true base
  (mainline `a91d8a66f`, found by full-tree blob matching) for diffing. Also preserves
  Sovol's MCU build configs (note: their `FLASH_START_0000` contradicts the
  Katapult-preinstalled evidence — stale factory-direct builds; mirror them for
  pin/feature selections only, never for flash offsets; see docs/01, section B).

Hardware facts: mainboard STM32H750 (USB-to-CAN bridge, app at 0x08020000), toolhead
STM32F103 (CAN PB8/PB9, Stage 1 only — replaced by the EBB36 in Stage 2), all CAN at
1M. Stock firmware hardcodes CAN UUIDs — re-query after every flash (Katapult mode
reports a different, real-chip-ID UUID). Z axis is belt-driven per corner (not
leadscrew, despite `gear_ratio: 80:12` looking that way at a glance). X endstop:
physical switch, on the toolhead itself in Stage 1, moving to the EBB36's endstop
header in Stage 2 (decided; sensorless is impossible — no TMC5160 DIAG routing;
mainboard PD6 spare endstop port is the documented alternative). No chamber heater on
this machine (`hot_mcu` intentionally absent).

## Status

- [x] **Stage 1 (mainline + DKEU, stock toolhead): complete.** First successful print
      landed after root-causing a chain of eddy-probe-range bugs — full account in
      `02-DIVERGENCES.md`. PLR alive; buffer shelved (see above).
- [ ] **Stage 2 (toolhead swap): in progress.** Hardware nearly fully assembled;
      `printer.cfg` rebuilt from Stage 1's proven structure with the new toolhead's
      hardware sections and a full temperature-drift-compensation addition (Eddy
      Duo capability, confirmed independent of USB vs CAN) — genuinely new-hardware
      values (CAN UUIDs, probe offsets, calibration-derived settings) are explicit
      TODOs, not guesses, resolved in `04-TOOLHEAD-CHANGEOVER.md`'s own section order.
- [ ] **Still open, not blocking Stage 2**: a real PLR power-cut test (kill mains
      mid-print, confirm resume) has never been run end-to-end — see doc 03.

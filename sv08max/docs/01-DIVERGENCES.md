# 01 — Divergences: What Actually Happened vs. The Plan

**What this is**: doc 01 (`01-MAINLINE-CUTOVER.md`) has already been corrected to
reflect everything below — its steps, warnings, and cross-references are the
*current* instructions. This doc is the narrative behind those corrections: what
the original plan assumed, what actually happened during the real cutover session,
and why each change was made. Read it when you want the reasoning, not just the
instruction. Doc 00's decision log has the one-line version of the biggest call
(eddy-ng → `probe_eddy_current`); this is the long version.

Everything here happened in a single (very long) cutover session, starting from a
disk-full error at 5am and ending with hot plastic coming out of a calibrated
machine. Order below follows doc 01's own section letters.

---

## Prerequisites & Section A — host conversion

**Planned**: SSH in, point KIAUH at the fork, remove/install Klipper, done in a
few minutes.

**Actual**: KIAUH's repo-switch backup step filled the eMMC's root partition
(only ~6.9GB total) mid-switch, aborting the clone. Cleared `~/kiauh_backups`
(638MB of failed partial backups from the aborted attempts) plus apt/pip caches to
recover ~1.6GB free. Then hit a DNS resolution failure on the second retry
(`bullseye-backports` repo had gone stale/archived, and general DNS was flaky) —
fixed by prepending `1.1.1.1` to `/etc/resolv.conf` (NetworkManager may overwrite
this on a future reconnect; redo if `github.com`/`deb.debian.org` stop resolving).
A couple of `python3.9` package versions also failed to fetch over the flaky link;
side-loaded the `.deb`s directly from the Mac and installed with `dpkg -i` +
`apt-get -f install`.

**Landed in doc 01**: the disk-space precheck in Prerequisites.

## Section B — MCU flashing

**Planned**: flash mainboard, toolhead, buffer over CAN via Katapult, in that
order, re-querying UUIDs as we go.

**Actual**: this section matched the plan closely — the real surprises were
smaller and are now folded into doc 01 directly: `python3-serial` wasn't
installed and is needed for the mainboard's serial-flash step; the mainboard's
one-shot `-u` flash command fails because it's a CAN bridge that drops off the bus
the instant it jumps to bootloader (the jump itself still succeeds — finish with
`-d` pointed at the resulting USB serial device); and the buffer MCU's Katapult
offset, flagged in the original plan as *inferred, not proven*, turned out to be
correct (8KiB, confirmed via its own Katapult connect banner reporting
`Application Start: 0x8002000`) — same as the toolhead.

**The one lesson worth its own callout**: after any restart (host reboot, a
`SAVE_CONFIG`-triggered restart, doesn't matter which), `canbus_query.py` can
report 0 nodes even though every flash succeeded. CAN-connected MCUs that stay
powered through a host-only restart keep believing they're bound to the previous
klippy session and won't answer a fresh discovery broadcast. A full power cycle
(mains switch) resets them to discoverable. We burned real time re-suspecting a
flash that was actually fine before finding this.

**Landed in doc 01**: the `python3-serial` note, the single-shot-vs-two-step
mainboard flash explanation, the confirmed (not just hoped) 8KiB buffer offset,
and the power-cycle-vs-reboot warning box.

## Section C — first-boot sanity

Matched the plan almost exactly. One correction: the original doc credited
software-i2c-on-PB10/PB11 to "eddy-ng dodging the F103 errata" — that workaround
is actually a Klipper-core `bus.py` capability, unrelated to which probe driver is
active. Worth being precise about, since we changed drivers later in this same
session (see below) and the wiring reasoning needed to still make sense afterward.

## Section D — probe calibration: the big one

This is where the plan and reality diverged the most, and where the real
architectural decision happened.

### What was supposed to happen

Install eddy-ng, calibrate the stock coil with `PROBE_EDDY_NG_CALIBRATE`, get tap
(nozzle-contact Z) as a bonus that self-corrects for PETG-CF nozzle wear — the
whole reason eddy-ng was chosen for this project in the first place, back when the
toolhead swap was first being planned.

### What actually happened, roughly in order

1. **A real Z-into-bed collision.** The original doc's calibration sequence went
   straight from `G28 X Y` into `PROBE_EDDY_NG_CALIBRATE`, with no step moving the
   toolhead to bed center first. After `G28 X Y` alone, the toolhead sits at
   whatever corner the endstops physically are (X≈-11, Y≈505 on this printer) —
   off the bed. The manual-probe park position was therefore unreachable, which
   sent the user looking for another way to get over the bed — pressing the
   touchscreen's "Home All" button, which attempted a full `G28` including Z. Z
   homes via the (at that point uncalibrated) probe as a virtual endstop, so it
   had no way to know when to stop and drove the nozzle into the bed until power
   was cut. No damage found on inspection, but this is the single most important
   fix in the corrected doc 01 — the missing `G1 X250 Y250` travel line.

2. **A gantry racking scare, resolved by hand.** After the recovery, it wasn't
   obvious whether the crash had racked the gantry (this printer's Z is
   belt-driven per corner, not leadscrew — a hard stop can, in principle, skip a
   belt tooth on one corner without affecting the others). Checked by parking at
   one corner with a feeler gauge, then traveling XY only (no Z moves) to the
   other three corners and comparing clearance by feel. Found up to several mm of
   real discrepancy. Fixed by hand: pushing each corner's gantry down (overpowering
   the stepper's holding torque) until it matched the reference corner. It moved
   smoothly with no felt tooth-skipping, and afterward all four corners were
   within 0.3mm. No permanent damage, no belt re-timing needed. This check isn't
   in doc 01 as a mandatory step (it's a reaction to an incident that the crash
   fix above should now prevent) but is worth doing after any real Z collision.

3. **The eddy-ng homing bug — the actual decision point.** Even after avoiding the
   crash, eddy-ng's own calibration flow (`PROBE_EDDY_NG_SETUP`,
   `PROBE_EDDY_NG_CALIBRATE`) hit a reproducible dead end: `G28 Z` (and even
   `G28` combined) failed with `"Z axis must be homed before probing"` —
   circular, since that's the error you'd expect *before* Z is homed, raised by
   the very call meant to home it. Read the actual source
   (`~/eddy-ng/probe_eddy_ng.py`) to find the real cause rather than guess:
   `start_probe_session()` — the entry point Klipper calls for *any* probe
   operation including homing — unconditionally instantiates
   `ProbeEddyScanningProbe`, a scan-only session that requires Z already homed.
   The correct conditional logic (fall through to a classic session for normal
   homing, only use the scan session for `METHOD=scan`/`rapid_scan`) exists in the
   file as commented-out dead code, and its target
   (`self._probe_session`) is never assigned anywhere — so even manually
   restoring the commented logic wouldn't have worked; it would just trade one
   error for a Python `AttributeError`.

   This matches a real, open GitHub issue: **vvuk/eddy-ng#146**, "Eddy-NG Fix —
   'Z axis must be homed before probing' on new Klipper" — Klipper's own
   `home_rails()` was refactored (around v0.13.0-665..667) to route probe-based Z
   homing through `start_probe_session()`, and eddy-ng's code hasn't caught up.
   Checked directly (not just trusted a web search summary, which turned out to
   have hallucinated a fix branch and commit hash that don't exist): neither
   `origin/main` nor `origin/eng-work` contains a working fix — both have the
   identical broken `start_probe_session()`.

4. **Decision: switch to mainline `probe_eddy_current` for the stock toolhead.**
   Reasoning at the time: both `probe_eddy_current` and `probe_eddy_ng` are
   generic LDC1612 drivers, not coil-specific ones — switching now doesn't cost
   anything at Stage 2 (the Eddy Duo needs fresh calibration regardless of which
   driver is used, since it's different hardware). The only real loss is tap,
   and manual recalibration every 5-10kg of CF filament was judged an acceptable
   substitute. Full technical reasoning for *why* the decision was framed as
   "reversible, revisit at Stage 2" is in doc 00's decision log.

5. **A second, unrelated homing puzzle**, this time in mainline code, not
   eddy-ng: `TESTZ` (used by `PROBE_EDDY_CURRENT_CALIBRATE`'s manual paper-touch
   step) *also* failed with "Must home axis first" — even with X/Y genuinely
   homed. Traced to `corexy.py`'s per-axis `limits` tracking: homed axes get a
   real `(position_min, position_max)` range; unhomed axes get an inverted
   sentinel range `(1.0, -1.0)` where min > max, so *any* move target fails the
   bounds check. `FORCE_MOVE` updates Klipper's tracked position but never
   touches this flag — only real homing, or `SET_KINEMATIC_POSITION`, does. This
   isn't a bug; it's `corexy.py` correctly enforcing a safety check whose
   prerequisite (a real Z home) doesn't exist yet for a probe that's mid-way
   through its own first calibration. Fixed by running bare `SET_KINEMATIC_POSITION`
   (defaults to current X/Y/Z, marks all three "trustworthy") immediately before
   the calibration commands — after first re-verifying Z's actual clearance,
   since repeated `G28 X Y` calls were separately observed to auto-lift Z a
   couple mm each time (very likely Mainsail's dashboard "home" button doing a
   client-side safety nudge before sending the command — never confirmed the
   exact mechanism, and it didn't matter once the fix was "always re-verify, never
   trust a stale value").

6. **Bed mesh false cliffs — a hardware issue with zero software fault.** The
   first `BED_MESH_CALIBRATE METHOD=rapid_scan` after successful homing and QGL
   showed two sharp ~1.2mm spikes concentrated entirely on the Y=490 row (the
   back edge of the configured mesh area). Initially suspected as an eddy-current
   sensor picking up nearby metal (bed clips, drag chain) — a real, known class of
   issue for eddy probes, and the double-peak shape (two distinct spikes at
   different X, not a smooth ridge) fit that theory reasonably well. The actual
   cause was simpler: the removable spring-steel plate was resting on its own
   rear retention stops rather than fully, magnetically seated — genuine physical
   tilt, not a sensing artifact. The probe was reporting real data faithfully.
   Reseating the plate and rerunning QGL + mesh (QGL had to be redone too — its
   corrections were computed from probe data taken while the plate was sitting
   wrong) produced a clean 0.485mm-range mesh with no edge anomalies.

### Why this doesn't threaten the rest of the plan

See the dedicated discussion in doc 00 / the conversation that produced this doc,
but the short version: DKEU has explicit, first-class support for
`probe_eddy_current` under this exact object name (`eddy`) in its mesh-building
logic, and treats eddy-ng as one optional probe type among several (its own
z-calibration macro *refuses to run* if eddy-ng is detected, deferring to eddy-ng's
own tools) — not a hard dependency. Confirmed by reading DKEU's source directly,
not assumed.

## Section E — smoke test: incomplete, not failed

**Planned**: one small print completes, first layer good, no MCU errors, feeder
and screen observed.

**Actual**: first print attempt (PETG) needed significant Z-offset babystepping
above the calibrated trigger height (expected — trigger height ≠ first-layer
squish, this is normal for any probe). Two hotend-fan findings, both still open:

- The fan sat completely still for the first couple of layers despite the
  extruder being well above its 45°C `heater_temp` threshold, then started on its
  own with no command issued.
- Canceling the print cut the fan instantly while the nozzle was still ~265°C —
  a real heat-creep/clog risk, and the reason the print was canceled rather than
  left to run. Leading hypothesis, **not yet verified**: `CANCEL_PRINT`'s
  `TURN_OFF_HEATERS` zeroes the extruder's *target* instantly, and `heater_fan`
  may key its on/off decision off "is the heater active" rather than the
  *measured* temperature. This needs an actual read of
  `~/klipper/klippy/extras/fan.py`'s `heater_fan` logic before anything gets
  changed — don't guess and patch blind on something this safety-relevant.

Both are recorded as open watch-items in doc 01's Section E rather than resolved
there, since they weren't resolved. The print was **canceled deliberately**, not a
failure of the pipeline — everything upstream (homing, mesh, QGL, extrusion,
temperature control) worked; the fan-on-cancel behavior is what ended the session.

**One piece of good news that arrived ahead of schedule**: the buffer
(`buffer-synced.cfg`) showed its first real positive signal during this same
print — green LED throughout (filament present, feeding normally), and
noticeably quieter than Sovol's stock discrete-push design. That's the expected
signature of the synced approach (continuous extruder-stepper sync) versus the
original stop-start pushing, and a good early sign for the buffer variant choice
doc 03 is meant to formally validate.

## Still open, going into doc 02

- Hotend fan cuts off instantly on `CANCEL_PRINT` while still hot — needs
  `fan.py` source read, not a patch guess.
- Hotend fan dead-still-then-self-starting during the first couple of layers —
  separate from the above, unclear if same root cause. Watch on the next print.
- Part-cooling fan0/fan1 status was mid-investigation when the print got
  canceled — recheck early in a fresh print rather than assume anything.
- eddy-ng issue #146 remains unresolved upstream. Nothing in Stage 1 or Doc 02
  needs it. Revisit specifically when Stage 2 (Eddy Duo, tap) is actually being
  built — check the issue's status then, don't decide it now either way.

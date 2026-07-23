# 03 — Full Validation on the Stock Toolhead

**What**: the complete test battery — buffer variant selection, PLR power-cut test,
runout chain, screen evaluation — on the final Stage-A software stack (mainline +
our overlay + DKEU).
**Why now**: nothing changes in this session, so results are pure signal. Everything
proven here is inherited by doc 04, where only hardware changes.
**Ends with**: exit criteria passed → print until bored → doc 04 whenever parts and
patience align.

## A. Buffer variant selection (the bench-pick)

*Why two variants exist: `buffer-synced.cfg` (AFC pattern — feeder runs as an
extruder_stepper synced to the extruder, push switch trims rotation_distance ±10%)
is smoother and injects nothing into the gcode stream mid-print; `buffer-pushed.cfg`
reproduces Sovol's discrete 25mm pushes exactly. Synced is the default; the bench
decides.*

Start with `buffer-synced.cfg` (the deployed default):

1. [ ] **Follow test**: long extrude (several meters via repeated `G1 E100`).
       Feeder tracks demand; push switch toggles the trim (console shows the
       rotation-distance changes); slack arm stays inside its travel the whole time.
2. [ ] **Jam test**: pinch the reverse-Bowden at the spool side mid-feed. Expect
       within ~5s: PAUSE, blue LED, `winding_status=True` (check via
       `printer.objects` or the screen). Clear it; RESUME recovers.
3. [ ] **Runout tail chain**: withdraw filament from the inlet sensor mid-test-print.
       Expect: green LED off → `CONTINUE_PRINT_D` counts down 1100mm of continued
       printing (*that's the point — the sensor is ~1.1m from the nozzle; the tail
       gets used, not wasted*) → `M600` → filament-change pause → long unload spits
       the tail (with the ~50s dwell — the ejection runs on the feeder's own
       timeline).
4. [ ] **FORCE_MOVE quoted-name check**:
       `FORCE_MOVE STEPPER="extruder_stepper filament_buffer" DISTANCE=10 VELOCITY=30`
       (*manual feed + unload in the synced variant depend on this parsing*).
5. [ ] **Decision point**: if feed quality disappoints (slack oscillation, grinding,
       trim hunting), swap the include to `buffer-pushed.cfg` and rerun 1–3, plus:
       verify a mid-print push does NOT stutter XY (watch a test print's surface
       while triggering the switch by hand — *the pushed variant's one theoretical
       risk is gcode-queue injection latency*).
6. [ ] Record the winner in this file and in `printer.cfg`'s include (and the
       stock-toolhead fallback config, so the fallback matches reality).

## B. PLR power-cut test

*Why this is the highest-value test here: 30-hour PETG-CF prints are the workload,
and this feature is why no UPS was purchased.*

1. [ ] Slicer start/end gcode calls DKEU's start/end (hooks verified in 02-C)
2. [ ] Sacrificial print (absolute-E sliced) to ~10mm height → kill mains
3. [ ] Power on: Mainsail prompt offers Resume/Discard; `saved_variables.cfg` shows
       a `plr_state` no older than ~5s of the cut
4. [ ] Resume: XY homes, **Z does NOT home** (*Z truth comes from the journal —
       the bed hasn't moved; probing mid-object would crash*), temps restore, nozzle
       returns, print completes
5. [ ] Inspect the seam: one band ≤ one layer + 5s of print
6. [ ] Repeat with a relative-E (M83) sliced file (*the regenerator handles both
       extrusion modes differently — both paths need one real test*)
7. [ ] Test Discard path once: G31 clears the flag and the plr file

## C. Screen evaluation (makerbase-client stays running)

*Why: it's a Moonraker API client and our config preserves the object names it
reads. This session documents reality instead of guessing.*

- [ ] Note which panel screens work / partially work / error (temps, print status,
      pause/resume buttons, filament menus, the eddy/Z-offset screens will error —
      expected, no `Z_OFFSET_CALIBRATION` exists)
- [ ] Watch `klippy.log` + `moonraker.log` for client-induced spam during A and B
- [ ] Only if it actively misbehaves: `sudo systemctl disable --now makerbase-client`
- [ ] ⚠ Standing rule regardless: never tap the screen's update/OTA button
- [ ] Optional nicety, if the panel proves mostly-alive: shim macro named
      `Z_OFFSET_CALIBRATION` that runs eddy-ng tap, reviving that button

## EXIT CRITERIA (gate to doc 04)

- [ ] Prints reliably on mainline + DKEU with the stock toolhead
- [ ] Buffer variant chosen, jam + runout + tail chain all passing
- [ ] PLR passed on absolute-E AND M83 files
- [ ] QGL + mesh + tap consistent across a week of real printing
- [ ] Screen behavior documented
- [ ] You're bored of the stock hotend

**Print big things here as long as you like.** Doc 04 waits indefinitely — this
state is a complete, reliable printer.

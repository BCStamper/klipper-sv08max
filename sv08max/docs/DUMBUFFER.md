# DUMBUFFER — standalone filament buffer firmware (future fork)

**Status: planning only.** This document sketches the plan; implementation
happens in a fork of this project, not here. Nothing in this file has been
built or tested.

## What this is

Reflash the filament buffer's own STM32F103 with standalone firmware —
Arduino/STM32duino, no Klipper integration, no CAN bus participation at all —
so it runs as a genuinely dumb, independent tension buffer. Architecturally
the same idea as the BIQU Panda Bamboo Feeder: a standalone microcontroller
that just feeds filament on its own terms, with zero awareness that a host
printer exists.

## Why this, why now

This project's own Klipper-integrated buffer rebuild is fully chronicled in
the `sv08-max-mainline-klipper` skill's `references/filament-buffer.md` —
read that before starting the fork, so it doesn't get rediscovered the hard
way. Short version: **four** rebuild attempts (synced extruder_stepper →
discrete FORCE_MOVE pushes → the same with SYNC=0 → registered as the
toolhead's own gcode axis), each defeating a different real blocker, ending
at a genuine structural Klipper limit: `Move.calc_junction()` doesn't set a
real junction velocity across non-kinematic moves, so any buffer push
inserted into the shared lookahead queue forces the *next real print move*
to plan from a dead stop — independent of blocking/sync concerns, a property
of how Klipper's shared motion queue works, not fixable via config or
macros. Fixing it properly would need real Klipper `extras` source work (a
separate trapq timeline) — a materially bigger lift than this is worth.

A **standalone** firmware sidesteps all of that by construction, not by
workaround: if the buffer isn't part of Klipper's motion queue at all, none
of the four attempts' failure modes can apply. This is also exactly how
Sovol's own stock firmware did it in the first place — `buffer_stepper.py`
used `self.mcu.flush_moves()`, a low-level direct-MCU API that submitted
steps entirely outside Klipper's shared toolhead queue. That API was removed
from mainline in the `motion_queuing` rework (~2025-08-11); going fully
standalone is the same trick stock used, just at the firmware level instead
of inside Klipper.

**Community angle**: DKEU's own docs independently flag this same loss
("WITH ANY VERSION OF THE LATEST KLIPPER YOU WILL LOOSE THE ABILITY TO RUN
THE BUFFER_STEPPER... you will also loose the Sovol PLR function") — this
isn't a problem specific to this printer. A documented, working
standalone-firmware conversion could be genuinely useful to other SV08 MAX
owners doing the same mainline migration, not just here. Worth considering
publishing the fork as its own reusable project rather than keeping it
buried in this repo, once it works.

## Hardware — what's known, what needs verifying on the real board

- **MCU**: STM32F103 (same chip class as the Stage-1 stock toolhead's own
  MCU).
- **Flashing**: ST-Link V2 already on hand.
- **Mechanism**: a spring-loaded **tension-sensing slide joint** between
  spool and extruder — confirmed via Sovol forum research plus hands-on
  correction of an earlier wrong mental model (it is *not* a slack-loop
  follower). Built specifically so the feeder doesn't track the extruder's
  every move — the spring absorbs normal demand variation, and the feeder
  only acts when tension moves toward one end of the joint's travel.
- **Two sense pins** (tension-triggered, slack-triggered) — this project's
  own history has referred to these inconsistently at different points
  (early docs called one side "jam"/"clog" with pin numbers that shifted
  between descriptions as understanding improved) — **do not trust a
  specific pin number carried over from memory or old docs; re-verify
  against the actual board/schematic before wiring anything.**
- **Stepper + driver**: present on this board already (drove the original
  25mm discrete pushes) — pull the exact driver chip and current settings
  from this repo's own tracked pre-shelving config
  (`sv08max/dkeu-patches/` or git history around 2026-08-16 to 08-19) rather
  than re-deriving from scratch.
- **LEDs**: the old Klipper-integrated version exposed status via
  `plug_status`/`winding_status` gcode_macro variables that the touchscreen
  read — check whether the LEDs themselves are simple direct-GPIO outputs
  (likely) before assuming any indirection needs replicating.

## Functional requirements

1. Poll (or interrupt-drive) the two tension/slack sense pins directly.
2. On **tense** trigger: begin a discrete push (feed toward the extruder).
   Matches the original mechanism's own design intent — don't reintroduce
   continuous syncing (see "explicitly ruled out" below).
3. On **slack** trigger: stop the push.
4. Reserve one spare pin/input for an externally-triggered **long
   retraction** call, and one for a **long feed** call — for filament
   load/unload operations needing more travel than a normal tension-push.
   **Open design question, not resolved by this brain dump**: how does an
   external signal reach this pin at all, now that the board has no CAN
   connection and no Klipper awareness? A physical button on the buffer
   housing itself matches the "dumb, standalone" framing most directly; a
   driven signal wire from the EBB36 (which does have free pins) would work
   too but reintroduces a small dependency on the host for triggering, even
   if not for timing/control. Decide explicitly, don't default silently.
5. Preserve LED status functionality — the firmware now owns this logic
   itself (no more Klipper variables to read), driving the LEDs directly off
   its own internal tension/push state.
6. **Explicitly not needed**: filament presence/runout sensing. The Orbiter
   Smart Sensor on the toolhead already covers this (see
   `04-ORBITER-SMART-SENSOR.md` / `references/hardware.md`) — don't
   duplicate it here.

## Explicitly out of scope

- **No CAN bus participation.** Also sidesteps this project's own
  still-unresolved mainboard/EBB36 mystery CAN traffic investigation
  entirely — this device won't be on that bus to be affected by it, or to
  muddy any future investigation of it.
- **No Klipper communication of any kind**, USB serial included, if it can
  be avoided — matches "outside of Klipper and the CAN network" literally,
  not just in spirit.
- **No jam/clog detection reported back to the host.** The original
  Klipper-integrated version paused the print on a stuck push signal via
  `winding_status`. A genuinely standalone unit can't report anything back
  by definition — decide explicitly whether the firmware needs its *own*
  jam-vs-normal-cycling distinction (e.g. "push has run N seconds with no
  slack trigger — something's actually wrong") with a visual-only response
  (an LED error state, matching the Orbiter sensor's own autonomous RGB ring
  philosophy), or whether jam protection is fully out of scope for this
  device now that the Orbiter sensor's tangle detection exists upstream of
  it. Don't let this drop silently either way — pick one on purpose.
- **Not reviving the synced/multiplier-trim approach** (attempt 1 from the
  skill reference) under any circumstances — its failure was a mechanical
  mismatch (continuous syncing fighting a tension-sensing spring joint),
  completely independent of the motion-queue reasoning that makes standalone
  firmware the right call here. Nothing about going standalone changes that
  mechanism's own verdict.

## Suggested approach

Arduino/STM32duino — matches Ben's own embedded background and was his own
original idea for this exact fix, not something newly proposed here. Given
the actual I/O surface (two digital inputs, one stepper output, a couple LED
outputs), a bare polling loop is almost certainly sufficient — there's no
print-time synchronization to get right anymore, since that's the entire
point of decoupling this from Klipper.

## Open questions for the fork to resolve

- Exact current pin mapping (tension sense, slack sense, stepper step/dir/
  enable, LED pins) — verify against the physical board directly.
- How the long-retract/long-feed trigger actually reaches the board
  (physical button vs. driven signal wire).
- Whether the firmware needs its own jam-detection logic, and if so what it
  does about it (LED-only, since there's no host to pause).
- Stepper current/microstepping — pull from this repo's own last-known-good
  buffer config rather than re-deriving.

## Where to start

- `sv08-max-mainline-klipper` skill, `references/filament-buffer.md` — full
  failure history of the Klipper-integrated attempts, read first.
- `sv08-max-mainline-klipper` skill, `references/hardware.md` — general
  board/MCU facts for this printer.
- This repo's git history around 2026-08-16 through 2026-08-19 for the last
  tracked buffer config (pin assignments, driver settings) before shelving.
- BIQU Panda Bamboo Feeder as an existing precedent for this exact
  architecture (standalone ESP32, not a Klipper model) — worth a look at
  whatever's publicly documented about it before designing from zero.

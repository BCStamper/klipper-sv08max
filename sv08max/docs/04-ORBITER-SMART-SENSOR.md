# 04 — Orbiter Smart Sensor (deferred addendum)

**What**: RobertLorincz's "Smart Sensor for Orbiter V2" — a combined filament
presence + tangle sensor that mounts directly on top of the Orbiter v2.5
extruder, already part of the new toolhead's BOM.
**Status (2026-08-17): mount it during the Stage 2 physical build (it's part of
the extruder assembly, easiest to do while everything's already apart), but
DEFER the Klipper-side wiring/config to a deliberate follow-up session AFTER
doc 04's baseline bring-up is proven working.** Reasoning: this is a second,
independent filament-sensing subsystem stacked on top of the buffer-inlet
`filament_switch_sensor` we spent 2026-08-16/17 getting right. Folding it into
an already-complex first bring-up (new toolhead + new endstop + new probe)
compounds unknowns instead of isolating them — the same "stages exist to
isolate failure domains" reasoning doc 04 itself already uses for why the
toolhead swap comes last. `04-TOOLHEAD-CHANGEOVER.md` steps B.2 and H
previously assumed this got wired in during the changeover itself — written
before this research existed — and have been updated to point here instead.

## What it actually is

- **Presence detection**: a 5.5mm steel ball presses a microswitch lever when
  filament is present.
- **Tangle detection**: a spring-loaded ring mechanism trips when pulling force
  exceeds ~2kg.
- **RGB status ring**: red (no filament) / green (present) / blue blinking
  (unloading) / yellow blinking (tangle).
- **Onboard ATtiny412** handles all debouncing/filtering in its own firmware
  (`O2SmartSensor_v2.4.hex` in the repo below) — the two signals Klipper sees
  are already clean.
- Complements, doesn't replace, our existing sensor: ours (`filament_switch_
  sensor filament_sensor`, buffer inlet, `buffer_mcu:PA10`) is far upstream and
  structurally can't see anything between the buffer and the nozzle. This one
  sits right at the extruder.

## Electrical / protocol (confirmed, not guessed)

Pulled the actual shipped Klipper config from the sensor's own repo
(`Klipper Config/Orbiter2_SmartSensor.cfg` in
[RobertLorincz/Orbiter-2-Smart-Sensor](https://github.com/RobertLorincz/Orbiter-2-Smart-Sensor)),
not just the product page. Two plain digital signals, nothing exotic:

```
[filament_switch_sensor O2_sensor]
switch_pin: orbitoolO2:PA13   # FS -- repoint to our board, see below

[gcode_button filament_unload]
pin: orbitoolO2:PA14          # FTU -- repoint to our board, see below
```

4-pin connector: GND, 3.3V (5V also supported), FS, FTU. No I2C/SPI/UART, no
special driver needed on the toolhead MCU — standard `filament_switch_sensor`
+ `gcode_button` primitives. The "multiplexed" language on the product page
turned out to refer to the mechanical lever serving both the presence *and*
tangle triggers, not the electrical signals — FS and FTU are electrically
independent pins.

## EBB36 CAN v1.2 pin fit (confirmed against BTT's own sample config)

Pulled `sample-bigtreetech-ebb-canbus-v1.2.cfg` from
[bigtreetech/EBB](https://github.com/bigtreetech/EBB) directly. It ships with
two pins commented out and pre-labeled for exactly this use case:

```
#[filament_switch_sensor switch_sensor]
#switch_pin: EBBCan:PB4
#[filament_motion_sensor motion_sensor]
#switch_pin: ^EBBCan:PB3
```

Cross-checked against everything already committed on this EBB36 for our
build — extruder step/dir/enable (`PD0`/`PD1`/`PD2`), heater (`PB13`), PT100
(`PA4` + `spi1`), TMC UART (`PA15`), part-cooling fan (`PA0`), hotend fan
(`PA1`), onboard ADXL345 (`PB12` + `spi2`), NeoPixels (`PD3`) — `PB3`/`PB4` are
both free. This is about as clean a pin fit as we could ask for; BTT
clearly designed the board with a dual-signal filament sensor like this one in
mind.

**Still unverified**: the physical connector type on both the sensor's 4-pin
cable and whatever header EBB36 breaks `PB3`/`PB4` out to — may need a small
adapter cable. Trivial to sort out, just not checked yet.

## The real gotcha — don't repeat today's bug class

The sensor's bundled config is not just the two sensor declarations above — it
also ships a **complete opinionated macro pack**: its own `PAUSE`/`RESUME`/
`CANCEL_PRINT` overrides (`rename_existing: BASE_PAUSE` etc.) and its own
filament-change state machine (`filament_change_state1`, `filament_load`,
`filament_unload`, `filament_tangle`, ...). It's clearly designed to be the
*only* filament-handling system in the printer.

Copying that in wholesale would collide directly with everything built
2026-08-16/17: our buffer-aware `PAUSE`, `BUFFER_LONG_UNLOAD_FILAMENT`,
`CONTINUE_PRINT_D`, and DKEU's stage-orchestration watchdogs — the exact
last-file-wins/competing-macro-pack bug class the whole 2026-08-16 collision
audit existed to root out (see the memory file / this repo's own audit
history: M600, LOAD_FILAMENT, UNLOAD_FILAMENT, PRINT_START all had a version
of this same problem).

**When this gets wired in, take only**:
```
[filament_switch_sensor O2_sensor]
switch_pin: EBBCan:PB4

[gcode_button filament_unload]
pin: EBBCan:PB3
```
(exact PB3/PB4 assignment between FS/FTU doesn't matter, just be consistent
with the physical wiring) — then write our *own* `runout_gcode`/`insert_gcode`/
`press_gcode` handlers that call into our existing `PAUSE`/
`BUFFER_LONG_UNLOAD_FILAMENT`/`UNLOAD_FILAMENT` chain. Do not include the
sensor's own `PAUSE`/`RESUME`/`CANCEL_PRINT`/filament-change macros.

## Sources

- Product page: https://www.orbiterprojects.com/smart-sensor-for-orbiter-v2/
- Repo: https://github.com/RobertLorincz/Orbiter-2-Smart-Sensor
  (`Klipper Config/Orbiter2_SmartSensor.cfg`, `Schematic/OrbiterSmartSensor v4.2.pdf`,
  `Firmware/O2SmartSensor_v2.4.hex`)
- BTT EBB36 CAN v1.2 sample config:
  https://github.com/bigtreetech/EBB/blob/master/EBB%20CAN%20V1.1%20and%20V1.2%20(STM32G0B1)/sample-bigtreetech-ebb-canbus-v1.2.cfg

## Follow-up checklist (for whenever this gets picked up)

- [ ] Confirm connector compatibility / build adapter cable if needed
- [ ] Confirm EBB36 firmware build already exposes `PB3`/`PB4` (should be
      default — they're not aux/special pins)
- [ ] Add `[filament_switch_sensor O2_sensor]` + `[gcode_button
      filament_unload]` to the toolhead config, pins as above
- [ ] Write `runout_gcode`/`insert_gcode`/`press_gcode` wired into our own
      macros, not the sensor's bundled pack
- [ ] Decide RGB ring behavior (leave sensor-autonomous, or drive from our own
      `red_led`/`green_led`/`blue_led` state like the buffer's LEDs?)
- [ ] Bench test in isolation before trusting it on a real print

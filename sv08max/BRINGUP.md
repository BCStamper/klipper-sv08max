# SV08 MAX Migration — Index

The runbook lives in [`docs/`](docs/), split by work session. Start with the
overview; open exactly one numbered doc per session and work top to bottom.

| Doc | Session | Status |
|---|---|---|
| [00 — Overview](docs/00-OVERVIEW.md) | What/why of the whole project, hardware facts, decision log, safety nets | reference |
| [01 — Mainline cutover](docs/01-MAINLINE-CUTOVER.md) | Fork onto the host, flash the 3 existing MCUs, eddy-ng on stock coil, smoke test | ☐ |
| [02 — DKEU integration](docs/02-DKEU-INTEGRATION.md) | Macro pack + collision resolution + hook migration | ☐ |
| [03 — Stock validation](docs/03-STOCK-VALIDATION.md) | Buffer variant pick, PLR power-cut test, runout chain, screen evaluation → exit criteria | ☐ |
| [04 — Toolhead changeover](docs/04-TOOLHEAD-CHANGEOVER.md) | EBB36 + Eddy Duo + Demon Remix: flash, CAN termination, datum, offsets, calibration cascade | ☐ |

Fault-isolation contract: every failure in 01 is software, in 02 macros, in 03
nothing (validation only), in 04 the new hardware. Don't start a doc until the
previous one's gate passed.

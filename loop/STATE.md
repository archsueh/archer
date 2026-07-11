# Loop STATE · Archer Heartbeat

Runtime log for hand-run ticks. Append-only by `loop.sh`.

## Config

- Level: **L1 supervised** (no cron, no auto Installer)
- Gate: `loop/guardrails/verify.sh` (quick=build, full=test)
- Contract: `loop/contract.md`
- Skill ref: `agentic-os-workflows` (global)

## Bootstrap

```bash
chmod +x loop/loop.sh loop/guardrails/verify.sh
./loop/loop.sh --status
./loop/loop.sh                 # expect quiet if empty queue
./loop/loop.sh --gate-only     # prove Gate
```

## Tick log

_(appended below by loop.sh)_

### Quiet tick 2026-07-11T21:06:33+0800
- triage: quiet (empty work-orders/, no --force)
- gate: skipped
- next: drop a work-order into `loop/work-orders/` or `./loop/loop.sh --force`

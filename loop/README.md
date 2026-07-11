# Archer · Heartbeat loop (L1)

Agentic OS **01 Heartbeat** scaffold: deterministic **Gate** + hand-run tick.  
No cron. No auto PR. Conductor / Worker / Verifier are **prompt seats** for you or an agent.

## Quick start

```bash
chmod +x loop/loop.sh loop/guardrails/verify.sh

# Prove Gate
./loop/loop.sh --gate-only          # swift build
./loop/loop.sh --gate-full          # swift test --parallel  (slow)

# Quiet tick (empty queue)
./loop/loop.sh

# Actionable: drop an order, then tick
cp loop/work-orders/_TEMPLATE.md loop/work-orders/my-fix.md
# …edit goal/scope/done_when…
./loop/loop.sh
# → follow seat prompts; Gate runs at end of script (quick)
```

## Layout

```
loop/
  loop.sh                 # one tick
  contract.md             # acts-alone / queues / wakes-me / never
  STATE.md                # append-only tick log
  triage.md               # seat prompts
  conductor.md
  workers/implement.md
  workers/verify.md
  guardrails/verify.sh    # Gate (bash only)
  work-orders/            # queue (*.md / *.json)
  goals/                  # standing goals (start with example)
  memory/pulse.log        # machine log
```

## Seat order

Signals → **Triage** → **Conductor** → **Worker** → **Verifier** → **Gate** → Installer(human)

## Related

- Global skill: `~/.agents/skills/agentic-os-workflows/`
- Notes: `~/Documents/Notes/AI/Agentic-OS-Fable5-Workflows.md`

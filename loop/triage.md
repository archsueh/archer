# Seat · Triage

**Job:** classify this tick. Do **not** implement.

## Inputs

- `loop/work-orders/*` non-empty?
- `git status` dirty / open PR?
- User force: `./loop/loop.sh --force`

## Rules

- If nothing queued and no force → **quiet** (spin / wait Δ). Cost must stay ~penny.
- If work-order exists or force → **actionable** → hand to Conductor.
- Never expand scope. Never run build for fun.

## Output

One line to `loop/STATE.md`:

```text
triage: quiet | actionable · reason: <short>
```

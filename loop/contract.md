# Loop contract · Archer

Blast radius before the first tick. Laws, not tips.

## Acts alone (auto later — L3+)

- Nothing yet. L1 is **supervised only**.

## Queues (drafts wait for human)

- Any code change > cosmetic
- Dependency bumps
- Bridge / socket / security paths
- Theme global glass params (`glassOpacity` / blur / saturate)

## Wakes me (hard stop)

- Deleting files / `git reset --hard` / force-push
- Changing pricing, updater feed, or signing
- Any change to `Theme.glassOpacity` global defaults
- Gate (`verify.sh`) red after two Worker attempts

## Never

- Never ask a model to "show your thinking" / echo chain-of-thought in the response
- Never let Worker rewrite or weaken tests to go green
- Never let Verifier edit product sources
- Never Installer without Gate PASS (`--full` before ship)
- Never skip Reference Sweep after signature/enum changes (see CLAUDE.md)

## Gate commands

```bash
./loop/guardrails/verify.sh          # quick: swift build
./loop/guardrails/verify.sh --full   # full:  swift test --parallel
```

## Seats (model routing — adjust to your keys)

| Seat | Job | Suggested effort |
|------|-----|------------------|
| Triage | quiet vs actionable | cheapest |
| Conductor | plan + work-order | strong (Fable/Opus/Grok high) |
| Worker | implement | mid / cheap |
| Verifier | fresh-context grade | strong, **new session** |
| Gate | bash only | — |
| Installer | commit/PR | human @ L1 |

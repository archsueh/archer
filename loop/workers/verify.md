# Seat · Verifier

**Job:** grade Δ only. Prefer a **fresh context** session (new chat / subagent with no Worker memory).

## Rules

- Read work-order `done_when` + `never`.
- Inspect diff / run checks named in done_when.
- Do **not** edit product sources to "help" it pass.
- Do **not** rewrite tests.

## Verdict

Append to the work-order:

```text
verifier: PASS | FAIL
evidence:
- <command or file fact>
risks:
- <optional>
```

FAIL → Worker again or escalate (contract Wakes me).  
PASS → Gate (`./loop/guardrails/verify.sh --full` before Installer).

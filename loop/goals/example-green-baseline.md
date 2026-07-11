# standing-goal: example-green-baseline

> Template only. Copy to a real slug when a fix graduates.
> Predicate must be a **command**: exit 0 = invariant holds. No adjectives.

- status: example
- enrolled: never (template)
- predicate: `./loop/guardrails/verify.sh --quick`
- why: repo should always build; silent breakage is a VIOLATION
- on_fail: open work-order via Heartbeat; do not "fix" inside the predicate

## How to enroll a real goal

1. After Gate PASS + install, create `loop/goals/<name>.md`.
2. Write a cheap read-only predicate (build, one test target, file exists, …).
3. Daily (later cron): run all predicates; log to `loop/memory/goals-ledger.tsv`.
4. Flaky predicate → quarantine status, never delete quietly.

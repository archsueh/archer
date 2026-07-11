# work-order: example-slug

- goal: <one sentence>
- scope: <paths>
- done_when:
  - `./loop/guardrails/verify.sh --quick` exits 0
  - <behavior fact>
- never:
  - rewrite tests to go green
  - change Theme glass globals
- seat_model: worker=mid verifier=fresh-strong
- standing_goal_candidate: no

<!-- worker: … -->
<!-- verifier: … -->

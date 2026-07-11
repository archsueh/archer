#!/usr/bin/env bash
# [archer] Heartbeat — one hand-run tick (L1). No cron, no auto ship.
#
# Seats (Agentic OS 01):
#   Signals → Triage → Conductor → Worker → Verifier → Gate → Installer
#
# This script is the skeleton:
#   - Triage:  quiet vs actionable (queue / open work-order / --force)
#   - Gate:    ./loop/guardrails/verify.sh (deterministic)
#   - Seats:   prompt files for human or agent; we do NOT call models here
#
# Usage:
#   ./loop/loop.sh                 # one tick; quiet if nothing queued
#   ./loop/loop.sh --force         # treat as actionable even if empty queue
#   ./loop/loop.sh --gate-only     # only run Gate (quick)
#   ./loop/loop.sh --gate-full     # only run Gate (full tests)
#   ./loop/loop.sh --status        # print STATE + queue
#
# Exit: 0 quiet/done · 1 gate fail · 2 usage · 3 needs human (actionable)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOOP="$SCRIPT_DIR"
export ARCHER_ROOT="$ROOT"

QUEUE_DIR="$LOOP/work-orders"
STATE_FILE="$LOOP/STATE.md"
PULSE_LOG="$LOOP/memory/pulse.log"
mkdir -p "$QUEUE_DIR" "$LOOP/memory"

FORCE=0
GATE_ONLY=0
GATE_FULL=0
STATUS_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --gate-only) GATE_ONLY=1 ;;
        --gate-full) GATE_FULL=1; GATE_ONLY=1 ;;
        --status) STATUS_ONLY=1 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "loop.sh: unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log_pulse() {
    echo "[$(ts)] $*" | tee -a "$PULSE_LOG"
}

# --- status ---
if [[ "$STATUS_ONLY" -eq 1 ]]; then
    echo "=== loop status ==="
    echo "root:  $ROOT"
    echo "state: $STATE_FILE"
    echo "queue:"
    shopt -s nullglob
    local_orders=("$QUEUE_DIR"/*.json "$QUEUE_DIR"/*.md)
    shown=0
    for f in "${local_orders[@]}"; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f")"
        [[ "$base" == _* ]] && continue
        echo "  - $base"
        shown=1
    done
    if [[ "$shown" -eq 0 ]]; then
        echo "  (empty — templates ignored)"
    fi
    echo
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "(no STATE.md yet)"
    fi
    exit 0
fi

# --- gate-only ---
if [[ "$GATE_ONLY" -eq 1 ]]; then
    if [[ "$GATE_FULL" -eq 1 ]]; then
        exec "$LOOP/guardrails/verify.sh" --full
    else
        exec "$LOOP/guardrails/verify.sh" --quick
    fi
fi

# --- triage ---
shopt -s nullglob
OPEN_ORDERS=("$QUEUE_DIR"/*.json "$QUEUE_DIR"/*.md)
# drop globs that didn't match; ignore templates (_*)
REAL_ORDERS=()
for f in "${OPEN_ORDERS[@]}"; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == _* ]] && continue
    REAL_ORDERS+=("$f")
done

ACTIONABLE=0
if [[ "$FORCE" -eq 1 ]]; then
    ACTIONABLE=1
elif [[ ${#REAL_ORDERS[@]} -gt 0 ]]; then
    ACTIONABLE=1
fi

log_pulse "tick start force=$FORCE actionable=$ACTIONABLE orders=${#REAL_ORDERS[@]}"

if [[ "$ACTIONABLE" -eq 0 ]]; then
    log_pulse "triage: quiet — spin / wait Δ"
    # Append quiet tick to STATE
    {
        echo
        echo "### Quiet tick $(ts)"
        echo "- triage: quiet (empty work-orders/, no --force)"
        echo "- gate: skipped"
        echo "- next: drop a work-order into \`loop/work-orders/\` or \`./loop/loop.sh --force\`"
    } >> "$STATE_FILE"
    echo
    echo "Quiet tick. No work-orders. Exit 0."
    echo "  Queue work:  loop/work-orders/<name>.md  (see work-orders/_TEMPLATE.md)"
    echo "  Force seat:  ./loop/loop.sh --force"
    echo "  Gate only:   ./loop/loop.sh --gate-only"
    exit 0
fi

# --- actionable path: print seat checklist, then Gate ---
log_pulse "triage: actionable — hand seats to agent/human"

ORDER_HINT="(none)"
if [[ ${#REAL_ORDERS[@]} -gt 0 ]]; then
    ORDER_HINT="$(basename "${REAL_ORDERS[0]}")"
fi

cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  HEARTBEAT · actionable tick                                 ║
╚══════════════════════════════════════════════════════════════╝

Open order(s): ${#REAL_ORDERS[@]}  (first: $ORDER_HINT)

Run seats IN ORDER (prompts live under loop/):

  1. Conductor  →  loop/conductor.md
     Produce/refresh work-order JSON fields: goal, scope, done_when, never, seat_model

  2. Worker     →  loop/workers/implement.md
     Execute only the work-order. No verify, no expand scope.

  3. Verifier   →  loop/workers/verify.md
     Fresh context preferred. Score Δ only. Do not edit product code.

  4. Gate       →  ./loop/guardrails/verify.sh [--full]
     Deterministic. This script will run Gate (quick) next.

  5. Installer  →  only if Gate PASS: commit / PR per repo rules.
     L1: human approves. No auto push.

Contract:     loop/contract.md
Standing goal example: loop/goals/example-green-baseline.md

EOF

echo "[gate] running quick gate after seat reminder…"
if ! "$LOOP/guardrails/verify.sh" --quick; then
    log_pulse "gate: FAIL"
    {
        echo
        echo "### Actionable tick $(ts) — GATE FAIL"
        echo "- orders: ${#REAL_ORDERS[@]}"
        echo "- first: \`$ORDER_HINT\`"
        echo "- gate: FAIL (quick)"
        echo "- next: fix build, re-run Worker or \`./loop/loop.sh --gate-only\`"
    } >> "$STATE_FILE"
    echo
    echo "Gate FAIL. Exit 1."
    exit 1
fi

log_pulse "gate: PASS (quick)"
{
    echo
    echo "### Actionable tick $(ts) — GATE PASS (quick)"
    echo "- orders: ${#REAL_ORDERS[@]}"
    echo "- first: \`$ORDER_HINT\`"
    echo "- gate: PASS quick"
    echo "- next: run full gate before install: \`./loop/loop.sh --gate-full\`"
    echo "- then: human Installer (commit/PR). Move finished order out of work-orders/"
} >> "$STATE_FILE"

echo
echo "Gate PASS (quick). Exit 3 = still needs human Installer / full gate."
echo "  Full tests:  ./loop/loop.sh --gate-full"
echo "  After ship:  move work-order out of loop/work-orders/; graduate a standing goal if needed"
exit 3

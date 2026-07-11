#!/usr/bin/env bash
# [archer] Agentic OS Gate — deterministic final vote. No LLM.
# Exit: 0 pass · 1 fail · 2 usage error
#
# Usage:
#   ./loop/guardrails/verify.sh           # quick: swift build
#   ./loop/guardrails/verify.sh --full    # full:  swift test --parallel
#   GATE_MODE=full ./loop/guardrails/verify.sh
#
# Env:
#   GATE_MODE=quick|full   (default quick; --full overrides)
#   ARCHER_ROOT            (default: repo root inferred from this script)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ARCHER_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
cd "$ROOT"

MODE="${GATE_MODE:-quick}"
for arg in "$@"; do
    case "$arg" in
        --full|-f) MODE=full ;;
        --quick|-q) MODE=quick ;;
        -h|--help)
            sed -n '2,14p' "$0"
            exit 0
            ;;
        *)
            echo "verify.sh: unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

echo "[gate] $(ts) mode=$MODE root=$ROOT"

case "$MODE" in
    quick)
        echo "[gate] swift build"
        if ! swift build; then
            echo "[gate] FAIL swift build" >&2
            exit 1
        fi
        ;;
    full)
        echo "[gate] swift package resolve"
        swift package resolve
        echo "[gate] swift test --parallel"
        if ! swift test --parallel; then
            echo "[gate] FAIL swift test" >&2
            exit 1
        fi
        ;;
    *)
        echo "[gate] unknown GATE_MODE=$MODE" >&2
        exit 2
        ;;
esac

echo "[gate] $(ts) PASS ($MODE)"
exit 0

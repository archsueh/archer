#!/bin/bash
# Pre-commit hook to run tests before committing in archer.
# When running inside an Archer agent session (agy, claude, etc.), we do a
# lighter check to keep the agent experience responsive. Full enforcement
# still happens for human commits.

set -euo pipefail

is_agent_session() {
    [[ -n "${ARCHER_SURFACE_ID:-}" || -n "${ARCHER_AGENT:-}" ]]
}

echo "Formatting staged Swift files with swiftformat..."
# Only format files that are actually staged (or about to be). Avoids touching
# unrelated files and keeps the diff the agent (or human) intended.
staged_swift=$(git diff --cached --name-only --diff-filter=ACMR | grep '\.swift$' || true)
if [[ -n "$staged_swift" ]]; then
    echo "$staged_swift" | xargs swiftformat --quiet
    git add $staged_swift
fi

if is_agent_session; then
    echo "Agent session detected (ARCHER_SURFACE_ID or ARCHER_AGENT). Skipping full test suite for responsiveness."
    echo "  (Human commits will still run the complete check.)"
    echo "  Use 'git commit --no-verify' if you explicitly want to bypass."
    exit 0
fi

echo "Checking Swift Package dependencies resolution..."
swift package resolve

echo "Running swift test before committing..."
swift test --parallel

echo "✓ Pre-commit checks passed."



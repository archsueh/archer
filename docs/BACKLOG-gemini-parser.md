# BACKLOG — Gemini Parser

**Status**: Blocked (Gemini CLI stores tokens in protobuf blobs, no plain-text source)

## Research (2026-07-06)

`~/.gemini/antigravity-cli/`:
- `history.jsonl` — command-level history only (display/timestamp/workspace), **no token data**
- `conversation_summaries.db` — metadata (title, step_count, timestamps), **no token columns**
- `conversations/*.db` — per-conversation SQLite, token usage in `gen_metadata` blob (protobuf), not plain SQL
- `log/*.log` — session-level logs, no per-request token summaries

**Conclusion**: No locally accessible plain-text token data source exists for Gemini CLI. Token data is embedded in protobuf-encoded blobs inside per-conversation SQLite databases. Parsing would require the protobuf schema (not publicly documented) and proto-decoding infrastructure.

## What's Already Done

- `UsageRecordSource.nativeGemini` — enum case added to `UsageModels.swift`
- `availableAgents` — Gemini probe in `UsageView.swift` (checks `~/.gemini/antigravity-cli/conversation_summaries.db`)

## Unblock Conditions

1. Gemini CLI exposes token usage in a parseable format (JSONL, plain SQL, or a documented API)
2. Or: the protobuf schema for `gen_metadata.data` blob is reverse-engineered and stable

## Remaining Agents (same pattern)

| Agent | Path | Format | Status |
|-------|------|--------|--------|
| Aider | `~/.aider/` | ? | Not researched |
| Cursor | `~/Library/Application Support/Cursor/` | SQLite? | Not researched |
| Windsurf | `~/.codeium/windsurf/` | ? | Not researched |
| Copilot | `~/.github-copilot/` | ? | Not researched |
| Cline | `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/` | ? | Not researched |
| Augment | ? | ? | Not researched |
| Qwen Code | ? | ? | Not researched |
| Goose | `~/.config/goose/` | ? | Not researched |

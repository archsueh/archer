# BACKLOG — Antigravity 原生 token 解析（原"Gemini Parser"，已更正）

**2026-07-06 更正**：本文件最初的结论（"Gemini CLI 不落纯文本 token"）**调研对象搞错了**——下方 Research 全部针对 `~/.gemini/antigravity-cli/`，那是 **Antigravity CLI (agy)** 的存储，不是原版 gemini-cli。

**原版 gemini-cli（google-gemini/gemini-cli）落纯 JSON**：`~/.gemini/tmp/<project-hash>/chats/session-*.json`，消息级 `tokens {input, output, cached, thoughts}`。依据：kenn-io/agentsview `internal/parser/gemini.go` + `testdata/gemini/standard_session.json`。**`Usage/Parsers/GeminiParser.swift` 已实现并注册**（thoughts 计入 output，按 output 计费），Gemini 不再是 backlog。本机无此数据仅因未装原版 gemini CLI。

---

以下调研对 **Antigravity CLI** 仍然成立，保留为 Antigravity 原生解析的 backlog：

## Research (2026-07-06, 对象: ~/.gemini/antigravity-cli/)

- `history.jsonl` — command-level history only (display/timestamp/workspace), **no token data**
- `conversation_summaries.db` — metadata (title, step_count, timestamps), **no token columns**
- `conversations/*.db` — per-conversation SQLite, token usage in `gen_metadata` blob (protobuf), not plain SQL
- `log/*.log` — session-level logs, no per-request token summaries

**Conclusion**: Antigravity 的 token 数据嵌在 per-conversation SQLite 的 protobuf blob 里，解析需要未公开的 proto schema。当前 agy 用量经 HermesParser (`~/.hermes/state.db`) 间接覆盖，原生解析价值有限，挂起。

## Unblock Conditions

1. Antigravity CLI exposes token usage in a parseable format (JSONL, plain SQL, or a documented API)
2. Or: the protobuf schema for `gen_metadata.data` blob is reverse-engineered and stable

## Remaining Agents (same pattern)

参考 kenn-io/agentsview `internal/parser/` 的对应 Go parser 可大幅缩短逆向：

| Agent | Path | Format | Status |
|-------|------|--------|--------|
| opencode | `~/.local/share/opencode/` | ? | Not researched |
| amp | ? | ? | Not researched |
| cursor-agent | `~/Library/Application Support/Cursor/` | SQLite? | Not researched |
| copilot | `~/.github-copilot/` | ? | Not researched |
| kimi | ? | ? | Not researched |
| kiro-cli | ? | ? | Not researched |
| droid | ? | ? | Not researched |
| pi | ? | ? | Not researched |

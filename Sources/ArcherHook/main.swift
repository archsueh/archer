import ArcherHookKit
import Darwin
import Foundation

// archer-hook: invoked by an agent's hook system (Claude Code's `--settings`
// hooks, Codex equivalents, …) and the shell precmd hook (`env` mode) to
// ping the running archer app over a unix socket. Payload building +
// stdin parsing live in `ArcherHookKit` so they're unit-testable; this
// file stays a thin dispatcher.
//
// Exit codes:
//   0 — IPC succeeded, OR caller is outside archer (no surface id) / args
//       malformed (programmer error). Both are "no retry needed."
//   1 — IPC failed (archer not listening, socket gone, write error). Shell
//       callers use this to keep their dedup cache un-advanced so the next
//       prompt re-attempts. Without this distinction, a single transient
//       failure (archer restarting, socket recreated) would freeze the env
//       cache permanently.
//
// Usage: archer-hook <agent> <event>
//   <agent> ∈ claude | codex | pi (or any AgentTemplate.id)
//   <event> ∈ running | attention | idle    (lifecycle events)
//           | PreToolUse | PostToolUse      (Claude tool events — stdin JSON)
//           | conversation <id>             (extension-reported resume id — Pi)
//           | tool <pre|post> <id> <name> <identifier> [ok|fail]
//                                            (extension-reported tool call — Pi)
// Usage: archer-hook env <VIRTUAL_ENV> <CONDA_DEFAULT_ENV> <NVM_BIN> <NVM_DIR> <NODE_VERSION> <https_proxy> <http_proxy> <all_proxy>
// Reads:  $ARCHER_SURFACE_ID       UUID of the originating session
// Reads:  stdin                   Claude pipes a JSON object on every
//                                 hook event. For PreToolUse/PostToolUse
//                                 it's the primary input; for lifecycle
//                                 events we use it to mirror `session_id`
//                                 back as a separate `kind: conversationId`
//                                 payload so archer can prepend
//                                 `--resume <id>` on next launch.

let surface = ProcessInfo.processInfo.environment["ARCHER_SURFACE_ID"] ?? ""
guard !surface.isEmpty else { exit(0) }

let socketPath = ArcherHookKit.socketPath

// Drain stdin once up-front so the tool-event parser (PreToolUse /
// PostToolUse) and the conversationId mirror — both reading the same hook
// JSON — don't double-read a single-pass stream. Gated on agents that pipe
// hook stdin (Claude, Grok): each writes one object then closes. Every other
// caller (codex/bracket lifecycle pings, Pi's argv modes, env snapshots)
// sends nothing on stdin, so draining is pointless — and a detached caller can
// hand us a stdin pipe that never EOFs (a broker's JSON-RPC stream that a
// spawned `app-server` inherits, pinged via the wrapper), where readToEnd()
// would block forever. `isatty == 0` still guards the tty case so the "binary
// not installed" branch never strands the tab.
let agentArg = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : ""
let hookStdinAgents: Set<String> = ["claude", "grok"]
let stdinData: Data = (hookStdinAgents.contains(agentArg) && isatty(fileno(stdin)) == 0)
    ? ((try? FileHandle.standardInput.readToEnd()) ?? Data())
    : Data()

let payloadObject: [String: String]
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "env" {
    let envArgs = Array(CommandLine.arguments.dropFirst(2))
    payloadObject = ArcherHookKit.buildEnvPayload(surface: surface, args: envArgs)
} else if CommandLine.arguments.count >= 3 {
    let agent = CommandLine.arguments[1]
    let event = CommandLine.arguments[2]
    if event == "conversation" {
        // Extension-reported conversation id (Pi): the agent's extension hands
        // archer the session id directly as argv[3] — no stdin JSON to parse
        // (unlike Claude's hook mirror below). Reuses the same conversationId
        // payload, so WorkspaceStore persists it + prepends `--session <id>`
        // on next launch.
        let id = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : ""
        guard !id.isEmpty else { exit(0) }
        let payload = ArcherHookKit.buildConversationIdPayload(surface: surface, conversationId: id)
        exit(ArcherHookKit.sendPayload(payload, to: socketPath) ? 0 : 1)
    }
    if event == "tool" {
        // Extension-reported tool call (Pi): the extension hands the already-
        // extracted fields as argv — no stdin JSON to parse (unlike Claude's
        // `parseToolEventPayload`). Funnels through the same
        // `buildToolEventPayload` so the `kind:"tool"` wire shape is identical
        // across agents. argv layout:
        //   archer-hook <agent> tool pre  <toolCallId> <toolName> <identifier>
        //   archer-hook <agent> tool post <toolCallId> <toolName> <identifier> <ok|fail>
        let args = CommandLine.arguments
        func at(_ i: Int) -> String {
            args.indices.contains(i) ? args[i] : ""
        }
        let phase = at(3)
        let toolName = at(5)
        guard phase == "pre" || phase == "post", !toolName.isEmpty else { exit(0) }
        // Any value other than "fail" (incl. missing) is treated as success —
        // the extension sends "ok"/"fail" off pi's `isError`.
        let success: Bool? = phase == "post" ? (at(7) != "fail") : nil
        let toolUseId = at(4)
        let payload = ArcherHookKit.buildToolEventPayload(
            surface: surface,
            agent: agent,
            toolName: toolName,
            identifier: at(6),
            event: phase,
            toolUseId: toolUseId.isEmpty ? nil : toolUseId,
            success: success
        )
        exit(ArcherHookKit.sendPayload(payload, to: socketPath) ? 0 : 1)
    }
    if event == "PreToolUse" || event == "PostToolUse" || event == "PostToolUseFailure" {
        // Tool event: stdin JSON is mandatory. Bail silently if it's
        // missing or malformed — pill UI just won't render this call.
        guard let tool = ArcherHookKit.parseToolEventPayload(
            from: stdinData,
            surface: surface,
            agent: agent
        ) else { exit(0) }
        payloadObject = tool
    } else {
        payloadObject = ArcherHookKit.buildLifecyclePayload(
            agent: agent,
            event: event,
            surface: surface
        )
    }
} else {
    exit(0)
}

let eventSent = ArcherHookKit.sendPayload(payloadObject, to: socketPath)

// Bonus payload: Claude pipes `session_id` on every hook (lifecycle +
// tool). Mirror it so `WorkspaceStore` can persist the conversation id
// on `Session` and prepend `--resume <id>` on next launch. Gated on:
//   1. Agent must pipe session ids on stdin (Claude, Grok)
//   2. `kind != "tool"` — tool payloads fire 10-100× per turn and each one
//      ALSO carries a session id; mirroring on every Pre/PostToolUse would
//      multiply IPC by N tool calls per turn. Lifecycle events carry the
//      same id and fire ~5× per turn — plenty to keep WorkspaceStore's
//      `--resume` field fresh. applyConversationId dedups same-value writes
//      but each call still pays a socket connect+write+close roundtrip.
if payloadObject["kind"] != "tool",
   let agent = payloadObject["agent"]
{
    let conversationId: String? = switch agent {
    case "claude": ArcherHookKit.parseClaudeConversationId(from: stdinData)
    case "grok": ArcherHookKit.parseGrokConversationId(from: stdinData)
    default: nil
    }
    if let conversationId {
        let payload = ArcherHookKit.buildConversationIdPayload(
            surface: surface,
            conversationId: conversationId
        )
        _ = ArcherHookKit.sendPayload(payload, to: socketPath)
    }
}

exit(eventSent ? 0 : 1)

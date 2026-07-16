import Foundation

/// Decodes one-shot JSON event lines from hooks (sent by the `ArcherHook`
/// CLI): agent lifecycle events and prompt-time shell env snapshots. Wire
/// format is one JSON object per line.
///
/// Socket ownership moved to `UnifiedListener` (cmux-style single-socket
/// demux) — the hook path is a symlink to the bridge socket, and `route(_:)`
/// dispatches hook frames here via `parseMessage`. This type is now a pure
/// decoder + payload enum.
///
/// The hooks themselves run as short-lived child processes of the agent (e.g.
/// Claude Code spawns them per Stop / UserPromptSubmit / Notification). They
/// connect, write one line, close — we parse and dispatch in a single pass.
/// Lifecycle signal an agent's hook fired. Wire format is the raw String
/// case names; the enum lets `WorkspaceStore` switch exhaustively.
enum HookEvent: String {
    case running, attention, idle, ended

    var activityState: SessionActivityState {
        switch self {
        case .running: return .running
        case .attention: return .attention
        case .idle, .ended: return .idle
        }
    }
}

/// PreToolUse / PostToolUse phase carried on `HookMessage.toolCall`. Pre
/// fires before Claude runs the tool; Post fires after — duration / orphan
/// timing are computed `WorkspaceStore`-side from the gap between matched
/// events (ArcherHook is fork-per-event and can't keep state).
enum HookToolEvent: String {
    case pre, post
}

enum HookMessage {
    case agent(agent: AgentTemplate, event: HookEvent, sessionId: UUID)
    case shellEnvironment(env: [String: String], sessionId: UUID)
    /// Claude's hook input JSON carries `session_id` (its conversation id).
    /// `ArcherHook` extracts it and emits this message so archer can persist
    /// it on the originating Session and reuse it as `--resume <id>` on
    /// next launch. The agent slug is implicit in the routing (only Claude
    /// pipes session_id today) and the consumer doesn't dispatch per-agent
    /// — so the payload only carries surface + id.
    case conversationId(conversationId: String, sessionId: UUID)
    /// PreToolUse / PostToolUse event for the activity strip. `agent` is
    /// the base AgentTemplate the slug resolves to (Claude builtin today —
    /// custom Claude-based agents share its slug since `from(hookSlug:)`
    /// matches by `initialCommand`). `success` is non-nil only for
    /// `.post` events. `toolUseId` is Claude's per-call stable id when
    /// present (used by `Session.recordToolCallEnd` to match Pre/Post
    /// pairs even when two concurrent calls share `toolName` + truncated
    /// identifier).
    case toolCall(
        agent: AgentTemplate,
        toolName: String,
        identifier: String,
        event: HookToolEvent,
        success: Bool?,
        toolUseId: String?,
        sessionId: UUID
    )
}

/// Hook transport metadata. Socket ownership lives in `UnifiedListener`;
/// `HookServer` is now a stateless decoder namespace. `parseMessage` stays
/// a static so existing tests (and `ArcherHook` payloads) need no changes.
enum HookServer {
    /// Path the `ArcherHook` CLI targets. Kept here for parity, but the live
    /// socket is `UnifiedListener`'s bridge socket, with this path symlinked
    /// to it. Public so the CLI doesn't have to hardcode the string twice.
    static let socketPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Archer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("socket").path
    }()

    private static let envKeys = [
        "VIRTUAL_ENV", "CONDA_DEFAULT_ENV",
        "NVM_BIN", "NVM_DIR", "ARCHER_NODE_VERSION",
        "https_proxy", "http_proxy", "all_proxy",
    ]

    @MainActor
    static func parseMessage(_ data: Data) -> HookMessage? {
        guard
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let surface = dict["surface"] as? String,
            let id = UUID(uuidString: surface)
        else { return nil }

        if dict["kind"] as? String == "env" {
            let env = Dictionary(uniqueKeysWithValues: envKeys.map { key in
                (key, dict[key] as? String ?? "")
            })
            return .shellEnvironment(env: env, sessionId: id)
        }

        if dict["kind"] as? String == "conversationId",
           let conversationId = dict["conversationId"] as? String,
           !conversationId.isEmpty
        {
            return .conversationId(conversationId: conversationId, sessionId: id)
        }

        if dict["kind"] as? String == "tool" {
            guard
                let agentSlug = dict["agent"] as? String,
                let agent = AgentTemplate.from(hookSlug: agentSlug),
                let toolName = dict["tool_name"] as? String, !toolName.isEmpty,
                let identifier = dict["identifier"] as? String,
                let eventRaw = dict["event"] as? String,
                let event = HookToolEvent(rawValue: eventRaw)
            else { return nil }

            // success ships as a literal "true" / "false" string on .post;
            // .pre omits it. Strict equality with "true" — any other value
            // ("TRUE", "1", "yes", "") coerces to false. ArcherHookKit owns
            // the wire shape and ships exactly "true" / "false", so the
            // strict check is a wire-protocol contract not a parse heuristic.
            // Missing field on .post leaves success nil — the consumer
            // (WorkspaceStore.applyToolCallEvent) treats nil as success
            // (rather than guess-fail an unparseable response).
            var success: Bool? = nil
            if event == .post, let s = dict["success"] as? String {
                success = (s == "true")
            }

            // tool_use_id ships only when Claude includes it (recent CLI);
            // nil-tolerant on the consumer side so old payloads still work.
            let toolUseId = (dict["tool_use_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }

            return .toolCall(
                agent: agent,
                toolName: toolName,
                identifier: identifier,
                event: event,
                success: success,
                toolUseId: toolUseId,
                sessionId: id
            )
        }

        guard
            let agentSlug = dict["agent"] as? String,
            let eventName = dict["event"] as? String,
            let agent = AgentTemplate.from(hookSlug: agentSlug),
            let event = HookEvent(rawValue: eventName)
        else { return nil }
        return .agent(agent: agent, event: event, sessionId: id)
    }
}

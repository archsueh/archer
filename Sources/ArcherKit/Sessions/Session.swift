import Foundation

/// Coarse "what's the agent doing" status, surfaced as a sidebar dot. Stage 1
/// is UI-only; Stage 2 will drive these from real agent hooks (Claude Code's
/// `--settings` hooks, Codex equivalents) over a unix socket.
enum SessionActivityState: Equatable {
    case idle
    case running
    case attention
}

/// State of one Claude tool-call event captured by the activity strip.
/// `running` is the in-flight default after PreToolUse; `success` / `failed`
/// transition on PostToolUse with the hook's heuristic success flag;
/// `stalled` is the orphan terminal — set 60s after PreToolUse if no
/// matching PostToolUse arrived (Claude crashed / network dropped / etc.).
enum ToolCallEventState: Equatable {
    case running, success, failed, stalled
}

/// One PreToolUse / PostToolUse pair represented as a single record in
/// `Session.toolCallEvents`. Runtime only — never persisted (`Persistence`
/// drops the field by Codable design: the field doesn't appear in
/// `PersistedTab` so the encoder simply skips it).
///
/// Matched on the post side by `toolUseId` when Claude provided one (the
/// only correct identity for concurrent same-tool calls — two parallel
/// `Grep "TODO"` calls share `toolName` + `identifier`); falls back to
/// (`toolName`, `identifier`) for older Claude versions that omit the id.
/// `toolUseId` nil → fallback path; non-nil → primary key.
struct ToolCallEvent: Identifiable, Equatable {
    let id: UUID
    let toolUseId: String?
    let toolName: String
    let identifier: String
    let startedAt: Date
    var completedAt: Date?
    var state: ToolCallEventState
}

@MainActor
@Observable
final class Session: Identifiable {
    let id: UUID
    let engine: any TerminalEngine
    /// Initial template the tab was opened with. Promoted at runtime when an
    /// agent's hooks fire from a plain `terminal` session — e.g. user types
    /// `claude` inside a Terminal tab → upgraded to `.claudeCode` so the
    /// sidebar / tab icon and agent state-tracking start working.
    var agent: AgentTemplate
    /// Runtime-only agent reported through the terminal byte stream rather
    /// than the local hook socket. This is primarily for ssh remotes: the
    /// remote side can emit an OSC title marker that archer sees locally,
    /// while the persisted launch template remains `terminal`.
    var transientAgent: AgentTemplate?
    var displayAgent: AgentTemplate {
        transientAgent ?? agent
    }

    /// Runtime-only SSH destination (`user@host` or bare `host`) reported by
    /// the ssh wrapper via an OSC title marker, shown in the pane status bar.
    /// Not persisted (like `transientAgent`); cleared only by the wrapper's
    /// logout marker (not OSC 133;D — a remote shell's own integration emits
    /// 133;D through the wire on every remote command).
    var remoteHost: String?
    /// SSH destination this tab was *spawned against* — set only when archer
    /// itself opened the connection (SSH workspace tabs), never by a manually
    /// typed `ssh`. Stable for the tab's lifetime, which makes it the paste
    /// routing signal: "upload pasted files to this host" must not flicker
    /// with `remoteHost`'s marker/logout lifecycle. Not persisted —
    /// restore re-derives it from `Workspace.sshRemoteHost` at spawn.
    var sshWorkspaceHost: String?
    /// Latest Codex account rate-limit usage (5-hour + weekly windows), parsed
    /// from the active session's rollout file by `CodexUsageMonitor` and shown
    /// as a status-bar gauge. Only populated for Codex sessions; `nil` until
    /// the first `token_count` lands. Runtime-only — not persisted (each launch
    /// re-derives it from disk once Codex starts writing again).
    var codexUsage: CodexUsage?
    /// Per-tab cwd. Initialized from the workspace's cwd at spawn, then kept in
    /// sync via OSC 7 (`engine.onPwdChange`). Drives the tab title so users see
    /// where they are, not which agent template the tab was launched from.
    var currentDirectory: URL
    /// Runtime state; not persisted. Resets to `.idle` after relaunch.
    var activityState: SessionActivityState = .idle
    /// Empty / whitespace input via `renameTab` clears this back to `nil` so
    /// the tab title resumes tracking the cwd.
    var customTitle: String?
    /// Title the running program set via `OSC 0` / `OSC 2` (libghostty's
    /// `GHOSTTY_ACTION_SET_TITLE`) — e.g. the `user@host:dir` an `ssh` remote
    /// shell emits. Runtime-only, never persisted. The shell wrapper re-emits
    /// the cwd as the title each prompt (`_archer_title_pwd`), which the path
    /// filter in `onTitleChange` maps back to `nil` — so a leftover `ssh` /
    /// TUI title can't outlive the program once control returns to the prompt.
    var terminalTitle: String?
    /// Last conversation id this tab's agent reported (currently only Claude
    /// — its SessionStart / Stop / SessionEnd hook JSON input carries
    /// `session_id`). Persisted via `PersistedTab.conversationId` so that the
    /// next archer launch can spawn the agent with `--resume <id>` and
    /// continue the conversation where the user left off. Per-Session field
    /// (not per-Pane / per-Workspace) because each tab is its own
    /// conversation — `ARCHER_SURFACE_ID` already routes hook payloads to
    /// the correct Session, so multi-tab Claude users don't cross-attribute.
    var conversationId: String?

    /// Bridge `@label` of the agent that handed this tab off (without `@`),
    /// e.g. `"grok"` or `"claude-code"`. Set by `openAgentTab` / Hand off;
    /// runtime-only, not persisted. GUI shows `←@source` on the tab.
    var drivenByLabel: String?
    /// Exit status of the most recent command — populated from libghostty's
    /// `OSC 133;D` event. `nil` until the shell reports its first finish (or
    /// when it omits the exit field). Not persisted: each launch starts fresh.
    var lastCommandExit: Int?
    /// Wall-clock duration of the most recent command in seconds. Same source
    /// as `lastCommandExit`; `nil` until first OSC 133;D arrives.
    var lastCommandDuration: TimeInterval?

    /// Per-session search state mirrored from libghostty's `start_search` /
    /// `search:<text>` / `navigate_search` / `end_search` action_cbs. Each
    /// surface owns its own search internally, so archer tracks the state per
    /// session — multiple panes can be in search mode at the same time, each
    /// with its own needle and result count. `searchSelected = -1` is
    /// libghostty's "no current match" sentinel.
    var searchActive = false
    var searchNeedle = ""
    var searchTotal = 0
    var searchSelected = -1

    /// Multiline prompt composer state (⌘L). Per-session like search — the
    /// draft survives a tab switch (switching destroys the view; `composerDraft`
    /// re-seeds the `TextEditor` on re-appear). Runtime-only, not persisted.
    var composerActive = false
    var composerDraft = ""

    /// Set true to open the rename popover on this tab from outside the view
    /// (the ⌘R menu command). The active tab's `TabBarItem` observes this,
    /// opens its rename popover, and resets the flag. Runtime-only.
    var renameRequested = false

    /// Latest git status for the session's cwd. `branch == nil` when the cwd
    /// isn't inside a git repo (or git isn't installed). Refreshed by
    /// `WorkspaceStore` on cwd-change + command-finished hooks. Runtime-only;
    /// not persisted.
    var gitStatus: GitStatus = .empty

    /// Project-environment indicators (Python venv name, Node version)
    /// reported by the live shell prompt hook, with project-file fallback.
    var environment: ProjectEnvironment = .empty

    /// Latest live shell env reported by the prompt hook. Kernel proc env
    /// snapshots are not reliable after `nvm use` / `activate` mutate the
    /// running shell, so this takes priority when present.
    var shellEnvironment: [String: String] = [:]

    /// Rolling buffer of recent Claude tool-call events (PreToolUse +
    /// PostToolUse pairs collapsed into one record each), rendered as
    /// pills in the activity strip. Capped at 200 (oldest evicted on
    /// overflow). Runtime only — `Persistence` does not encode this field,
    /// so app restart / `--resume` starts the strip empty.
    var toolCallEvents: [ToolCallEvent] = []
    static let toolCallEventsCap = 200
    /// 60s without a matching PostToolUse → `.running` flips to `.stalled`.
    /// Matches the "Claude crashed mid-tool" case the activity strip's
    /// design doc calls out.
    static let toolCallOrphanThreshold: TimeInterval = 60

    /// Background timer that periodically sweeps `.running` events for
    /// orphan status. Started lazily on first `recordToolCallStart`; ends
    /// itself when the sweep finds no `.running` events left. `[weak self]`
    /// means Session deinit naturally tears it down without explicit
    /// cleanup. Single timer per session (5s tick) regardless of how many
    /// concurrent tool calls are running.
    private var orphanCheckTimer: Task<Void, Never>?

    /// Appends a PreToolUse record (state = .running) and enforces the
    /// rolling cap. Caller (`WorkspaceStore.applyToolCallEvent`) is
    /// `@MainActor`-isolated so direct array mutation is safe.
    func recordToolCallStart(
        toolName: String,
        identifier: String,
        toolUseId: String? = nil,
        startedAt: Date = Date()
    ) {
        appendToolCallEvent(ToolCallEvent(
            id: UUID(),
            toolUseId: toolUseId,
            toolName: toolName,
            identifier: identifier,
            startedAt: startedAt,
            completedAt: nil,
            state: .running
        ))
        scheduleOrphanCheckIfNeeded()
    }

    /// Resolves a PostToolUse: looks up the matching pre record (prefer
    /// `toolUseId` when both sides have one; fall back to oldest
    /// `.running`-or-`.stalled` matching `toolName` + `identifier`) and
    /// flips it to `.success` / `.failed`. The `.stalled` fallback is
    /// deliberate: a Claude tool that ran >60s is marked stalled by the
    /// orphan sweep, but if the Post eventually arrives we'd rather revive
    /// the original record (with accurate completedAt) than synthesise a
    /// 0s ghost record alongside the now-misleading stalled one.
    func recordToolCallEnd(
        toolName: String,
        identifier: String,
        success: Bool,
        toolUseId: String? = nil,
        completedAt: Date = Date()
    ) {
        // Match priority:
        //   1. tool_use_id exact match (any non-terminal state) — Claude's
        //      stable per-call id; only correct option for concurrent
        //      same-tool calls with truncated identifiers
        //   2. oldest (toolName + identifier) running OR stalled — legacy
        //      payloads without tool_use_id, or stalled record revival
        let matchIndex: Int? = {
            if let toolUseId, !toolUseId.isEmpty {
                if let i = toolCallEvents.firstIndex(where: { $0.toolUseId == toolUseId }) {
                    return i
                }
            }
            return toolCallEvents.firstIndex {
                $0.toolName == toolName
                    && $0.identifier == identifier
                    && ($0.state == .running || $0.state == .stalled)
            }
        }()

        if let i = matchIndex {
            toolCallEvents[i].completedAt = completedAt
            toolCallEvents[i].state = success ? .success : .failed
        } else {
            // Orphan post — synthesise a record so the call still appears
            // in the strip. startedAt = completedAt (no duration possible
            // without the pre). Rare; usually means a hook race or archer
            // restart between Pre and Post.
            appendToolCallEvent(ToolCallEvent(
                id: UUID(),
                toolUseId: toolUseId,
                toolName: toolName,
                identifier: identifier,
                startedAt: completedAt,
                completedAt: completedAt,
                state: success ? .success : .failed
            ))
        }
    }

    /// Append + enforce the 200-event rolling cap. Single source of truth
    /// for the cap policy — `recordToolCallStart` and the orphan-post
    /// branch of `recordToolCallEnd` both route through here so a future
    /// change to the eviction rule (ring buffer, eviction-by-state, etc.)
    /// only touches one site.
    private func appendToolCallEvent(_ event: ToolCallEvent) {
        toolCallEvents.append(event)
        if toolCallEvents.count > Self.toolCallEventsCap {
            toolCallEvents.removeFirst(toolCallEvents.count - Self.toolCallEventsCap)
        }
    }

    /// Marks `.running` events older than 60s (`toolCallOrphanThreshold`)
    /// as `.stalled` and stamps `completedAt` with the sweep time so the
    /// duration label freezes at the stall threshold (not the pill's
    /// fallback `Date()` clock that grows forever). Returns true if any
    /// `.running` events survived the sweep — the orphan timer uses this
    /// to decide whether to keep ticking.
    @discardableResult
    func checkStalledToolCallEvents(now: Date = Date()) -> Bool {
        var anyStillRunning = false
        for i in toolCallEvents.indices where toolCallEvents[i].state == .running {
            if now.timeIntervalSince(toolCallEvents[i].startedAt) > Self.toolCallOrphanThreshold {
                toolCallEvents[i].state = .stalled
                toolCallEvents[i].completedAt = now
            } else {
                anyStillRunning = true
            }
        }
        return anyStillRunning
    }

    private func scheduleOrphanCheckIfNeeded() {
        guard orphanCheckTimer == nil else { return }
        orphanCheckTimer = Task { @MainActor [weak self] in
            // 5s tick — coarse enough that 200 events × N sessions stays
            // cheap (single array scan per session) but fine enough that
            // a 60s orphan transitions within ~1 tick of the threshold.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                guard let self else { break }
                let stillRunning = self.checkStalledToolCallEvents()
                if !stillRunning {
                    self.orphanCheckTimer = nil
                    break
                }
            }
        }
    }

    /// Tab-pill name. Precedence: `customTitle` (manual rename) wins, then
    /// `terminalTitle` (OSC title from the running program, e.g. an `ssh`
    /// remote), then `lastPathComponent` of the cwd (`~` for $HOME). An empty
    /// cwd path falls back to the agent name so a degenerate URL doesn't
    /// render as blank.
    var title: String {
        if let custom = customTitle, !custom.isEmpty { return custom }
        if let reported = terminalTitle, !reported.isEmpty { return reported }
        if currentDirectory.standardizedFileURL.path == NSHomeDirectory() { return "~" }
        let last = currentDirectory.lastPathComponent
        return last.isEmpty ? displayAgent.title : last
    }

    init(
        id: UUID = UUID(),
        engine: any TerminalEngine,
        currentDirectory: URL,
        agent: AgentTemplate,
        customTitle: String? = nil,
        conversationId: String? = nil
    ) {
        self.id = id
        self.engine = engine
        self.currentDirectory = currentDirectory
        self.agent = agent
        self.customTitle = customTitle
        self.conversationId = conversationId
    }
}

import Foundation

/// Maps stable `@label` strings to live Sessions so Bridge commands can address
/// panes by name instead of opaque UUIDs. Labels are derived from the session's
/// display agent id ("claude-code", "codex", "hermes", "grok", …).
/// When multiple sessions share the same agent, they get suffixed: "codex",
/// "codex-2", "codex-3".
///
/// Registers **every non-shell tab** (not only the active tab), so background
/// agent tabs stay addressable for handoff / type / read.
///
/// Call `sync(workspace:)` whenever the active workspace or its pane tree changes.
@MainActor
final class PaneRegistry {
    static let shared = PaneRegistry()
    private init() {}

    private(set) var entries: [String: Session] = [:]

    // MARK: - Label helpers

    /// Strip optional leading `@` and whitespace. Bridge wire + CLI accept both
    /// `codex` and `@codex`.
    static func normalizeLabel(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("@") {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    /// Display form with `@` prefix (empty input → empty).
    static func at(_ label: String) -> String {
        let n = normalizeLabel(label)
        return n.isEmpty ? "" : "@\(n)"
    }

    /// Reverse lookup: which `@label` currently points at this session.
    func label(for sessionId: UUID) -> String? {
        entries.first(where: { $0.value.id == sessionId })?.key
    }

    func label(for session: Session) -> String? {
        label(for: session.id)
    }

    // MARK: - Sync

    func sync(workspace: Workspace?) {
        guard let workspace else { entries = [:]; return }
        var newEntries: [String: Session] = [:]
        var agentCounts: [String: Int] = [:]
        // Pane tree order, then tab order — stable suffixes for multi-agent.
        for pane in workspace.root.allPanes {
            for session in pane.tabs where !session.displayAgent.isShell {
                let base = session.displayAgent.id
                let count = agentCounts[base, default: 0]
                let label = count == 0 ? base : "\(base)-\(count + 1)"
                agentCounts[base] = count + 1
                newEntries[label] = session
            }
        }
        entries = newEntries
    }

    // MARK: - Bridge primitives

    /// Resolve label with optional `@` prefix.
    func session(forAddress raw: String) -> Session? {
        entries[Self.normalizeLabel(raw)]
    }

    /// Read the last `lines` rows of the pane's active screen buffer.
    func read(label: String, lines: Int = 20) -> String? {
        guard let session = session(forAddress: label),
              let engine = session.engine as? LibghosttyEngine
        else { return nil }
        return engine.readScreen(lines: lines)
    }

    /// Inject `text` into the pane as if the user typed it.
    func type(label: String, text: String) {
        guard let session = session(forAddress: label) else { return }
        session.engine.sendInput(text)
    }

    /// Send named key sequences into the pane.
    /// Supported names: Enter, Tab, Escape, Backspace, ctrl+c/d/z/l, up/down/left/right.
    func keys(label: String, keys: [String]) {
        guard let session = session(forAddress: label) else { return }
        for key in keys {
            session.engine.sendInput(bytes(for: key))
        }
    }

    // MARK: - Key mapping

    private func bytes(for name: String) -> String {
        switch name.lowercased() {
        case "enter", "return": return "\r"
        case "tab": return "\t"
        case "escape", "esc": return "\u{1B}"
        case "backspace": return "\u{7F}"
        case "ctrl+c", "c-c": return "\u{03}"
        case "ctrl+d", "c-d": return "\u{04}"
        case "ctrl+z", "c-z": return "\u{1A}"
        case "ctrl+l", "c-l": return "\u{0C}"
        case "ctrl+r", "c-r": return "\u{12}"
        case "up": return "\u{1B}[A"
        case "down": return "\u{1B}[B"
        case "right": return "\u{1B}[C"
        case "left": return "\u{1B}[D"
        default: return name
        }
    }
}

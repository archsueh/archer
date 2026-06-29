import Foundation

/// Maps stable `@label` strings to live Sessions so Bridge commands can address
/// panes by name instead of opaque UUIDs. Labels are derived from the session's
/// display agent id ("claude", "codex", "hermes", "gemini", "agents").
/// When multiple panes share the same agent, they get suffixed: "claude",
/// "claude-2", "claude-3".
///
/// Call `sync(workspace:)` whenever the active workspace or its pane tree changes.
@MainActor
final class PaneRegistry {
    static let shared = PaneRegistry()
    private init() {}

    private(set) var entries: [String: Session] = [:]

    // MARK: - Sync

    func sync(workspace: Workspace?) {
        guard let workspace else { entries = [:]; return }
        var newEntries: [String: Session] = [:]
        var agentCounts: [String: Int] = [:]
        for pane in workspace.root.allPanes {
            guard let session = pane.activeTab else { continue }
            let base = session.displayAgent.id
            let count = agentCounts[base, default: 0]
            let label = count == 0 ? base : "\(base)-\(count + 1)"
            agentCounts[base] = count + 1
            newEntries[label] = session
        }
        entries = newEntries
    }

    // MARK: - Bridge primitives

    /// Read the last `lines` rows of the pane's active screen buffer.
    func read(label: String, lines: Int = 20) -> String? {
        guard let session = entries[label],
              let engine = session.engine as? LibghosttyEngine
        else { return nil }
        return engine.readScreen(lines: lines)
    }

    /// Inject `text` into the pane as if the user typed it.
    func type(label: String, text: String) {
        guard let session = entries[label] else { return }
        session.engine.sendInput(text)
    }

    /// Send named key sequences into the pane.
    /// Supported names: Enter, Tab, Escape, Backspace, ctrl+c/d/z/l, up/down/left/right.
    func keys(label: String, keys: [String]) {
        guard let session = entries[label] else { return }
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

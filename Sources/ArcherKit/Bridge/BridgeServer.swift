import Darwin
import Foundation

/// Request/response handler for the `archer-bridge` CLI wire protocol.
///
/// Socket ownership moved to `UnifiedListener` (cmux-style single-socket
/// demux). This class is now a pure handler: `handle(_:)` turns one JSON
/// request line into one JSON response line.
///
/// **@label addressing**: every target is a PaneRegistry label. Wire and CLI
/// accept both `codex` and `@codex`. Log summaries use route form
/// `@from → @to` for handoff / type / keys.
///
///   → {"cmd":"list"}
///   ← {"ok":true,"labels":["claude-code","codex"]}
///
///   → {"cmd":"read","label":"@claude-code","lines":20}
///   ← {"ok":true,"text":"…"}
///
///   → {"cmd":"type","label":"codex","text":"ls -la\n"}
///   ← {"ok":true}
///
///   → {"cmd":"keys","label":"codex","keys":["Enter"]}
///   ← {"ok":true}
///
///   → {"cmd":"sync"}
///   ← {"ok":true,"count":2}
///
///   → {"cmd":"handoff","agent":"@hermes","prompt":"…","from":"@grok"}
///   ← {"ok":true,"label":"hermes","agent":"hermes","sessionId":"…"}
///
///   → {"cmd":"agents"}
///   ← {"ok":true,"agents":[{"id":"hermes","name":"Hermes"},…]}
///
/// Dispatches through PaneRegistry, so all surface access is main-actor-safe.
@MainActor
final class BridgeServer {
    /// Resolved at command time — avoids stale first-window pin and nil-after-close bugs.
    var storeProvider: (() -> WorkspaceStore?)?

    func handle(_ data: Data) -> Data {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = dict["cmd"] as? String
        else { return error("invalid JSON or missing cmd") }

        // Sync registry from active workspace before every command.
        PaneRegistry.shared.sync(workspace: storeProvider?()?.active)

        switch cmd {
        case "list":
            let labels = Array(PaneRegistry.shared.entries.keys).sorted()
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "list → [\(labels.map { PaneRegistry.at($0) }.joined(separator: ", "))]"
            )
            return ok(["labels": labels])

        case "sync":
            let count = PaneRegistry.shared.entries.count
            BridgeEventLog.shared.append(category: .bridge, summary: "sync → \(count) pane(s)")
            return ok(["count": count])

        case "read":
            guard let raw = dict["label"] as? String else { return error("missing label") }
            let label = PaneRegistry.normalizeLabel(raw)
            let lines = (dict["lines"] as? Int) ?? 20
            guard let text = PaneRegistry.shared.read(label: label, lines: lines) else {
                return error("label not found or surface unavailable: \(PaneRegistry.at(label))")
            }
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "read \(PaneRegistry.at(label)) \(lines)L → \(text.count)ch"
            )
            return ok(["text": text])

        case "type":
            guard let raw = dict["label"] as? String else { return error("missing label") }
            guard let text = dict["text"] as? String else { return error("missing text") }
            let label = PaneRegistry.normalizeLabel(raw)
            guard PaneRegistry.shared.session(forAddress: label) != nil else {
                return error("label not found: \(PaneRegistry.at(label))")
            }
            PaneRegistry.shared.type(label: label, text: text)
            let preview = text.prefix(40).replacingOccurrences(of: "\n", with: "↵")
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "type → \(PaneRegistry.at(label)) \"\(preview)\""
            )
            return ok([:])

        case "keys":
            guard let raw = dict["label"] as? String else { return error("missing label") }
            guard let keys = dict["keys"] as? [String] else { return error("missing keys array") }
            let label = PaneRegistry.normalizeLabel(raw)
            guard PaneRegistry.shared.session(forAddress: label) != nil else {
                return error("label not found: \(PaneRegistry.at(label))")
            }
            PaneRegistry.shared.keys(label: label, keys: keys)
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "keys → \(PaneRegistry.at(label)) [\(keys.joined(separator: ", "))]"
            )
            return ok([:])

        case "handoff", "open":
            // Open a new agent tab (optionally with prompt). Does not require
            // a pre-existing pane of that agent.
            guard let agent = (dict["agent"] as? String) ?? (dict["label"] as? String) else {
                return error("missing agent")
            }
            let prompt = dict["prompt"] as? String
            let strict = (dict["strict"] as? Bool) ?? false
            let from = dict["from"] as? String
            guard let store = storeProvider?() else {
                return error("no active store")
            }
            do {
                let result = try store.openAgentTab(
                    agentId: agent,
                    prompt: prompt,
                    sourceLabel: from,
                    strictVisible: strict
                )
                let preview: String
                if let p = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                    preview = String(p.prefix(48)).replacingOccurrences(of: "\n", with: "↵")
                } else {
                    preview = "(no prompt)"
                }
                let route: String
                if let src = result.session.drivenByLabel {
                    route = "\(PaneRegistry.at(src)) → \(PaneRegistry.at(result.label))"
                } else {
                    route = "→ \(PaneRegistry.at(result.label))"
                }
                BridgeEventLog.shared.append(
                    category: .bridge,
                    summary: "handoff \(route) · \(preview)"
                )
                var payload: [String: Any] = [
                    "label": result.label,
                    "agent": result.agentId,
                    "sessionId": result.session.id.uuidString,
                ]
                if let from = result.session.drivenByLabel {
                    payload["from"] = from
                }
                return ok(payload)
            } catch {
                return self.error(error.localizedDescription)
            }

        case "agents":
            let model = ArcherSettingsModel.shared
            let agents: [[String: Any]] = AgentTemplate.visibleOrdered(model: model)
                .filter { !$0.isShell }
                .map { ["id": $0.id, "name": $0.title] }
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "agents → \(agents.count)"
            )
            return ok(["agents": agents])

        default:
            return error("unknown cmd: \(cmd)")
        }
    }

    private func ok(_ extra: [String: Any]) -> Data {
        var d: [String: Any] = ["ok": true]
        extra.forEach { d[$0] = $1 }
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data()
    }

    private func error(_ msg: String) -> Data {
        let d: [String: Any] = ["ok": false, "error": msg]
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data()
    }
}

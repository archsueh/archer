import Darwin
import Foundation

/// Request/response handler for the `archer-bridge` CLI wire protocol.
///
/// Socket ownership moved to `UnifiedListener` (cmux-style single-socket
/// demux). This class is now a pure handler: `handle(_:)` turns one JSON
/// request line into one JSON response line. Wire format is unchanged:
///
///   → {"cmd":"list"}
///   ← {"ok":true,"labels":["claude","codex"]}
///
///   → {"cmd":"read","label":"claude","lines":20}
///   ← {"ok":true,"text":"…last 20 rows…"}
///
///   → {"cmd":"type","label":"claude","text":"ls -la\n"}
///   ← {"ok":true}
///
///   → {"cmd":"keys","label":"claude","keys":["Enter"]}
///   ← {"ok":true}
///
///   → {"cmd":"sync"}
///   ← {"ok":true,"count":2}
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
            BridgeEventLog.shared.append(category: .bridge, summary: "list → [\(labels.joined(separator: ", "))]")
            return ok(["labels": labels])

        case "sync":
            let count = PaneRegistry.shared.entries.count
            BridgeEventLog.shared.append(category: .bridge, summary: "sync → \(count) pane(s)")
            return ok(["count": count])

        case "read":
            guard let label = dict["label"] as? String else { return error("missing label") }
            let lines = (dict["lines"] as? Int) ?? 20
            guard let text = PaneRegistry.shared.read(label: label, lines: lines) else {
                return error("label not found or surface unavailable: \(label)")
            }
            BridgeEventLog.shared.append(category: .bridge, summary: "read \(label) \(lines)L → \(text.count)ch")
            return ok(["text": text])

        case "type":
            guard let label = dict["label"] as? String else { return error("missing label") }
            guard let text = dict["text"] as? String else { return error("missing text") }
            guard PaneRegistry.shared.entries[label] != nil else {
                return error("label not found: \(label)")
            }
            PaneRegistry.shared.type(label: label, text: text)
            let preview = text.prefix(40).replacingOccurrences(of: "\n", with: "↵")
            BridgeEventLog.shared.append(category: .bridge, summary: "type \(label) \"\(preview)\"")
            return ok([:])

        case "keys":
            guard let label = dict["label"] as? String else { return error("missing label") }
            guard let keys = dict["keys"] as? [String] else { return error("missing keys array") }
            guard PaneRegistry.shared.entries[label] != nil else {
                return error("label not found: \(label)")
            }
            PaneRegistry.shared.keys(label: label, keys: keys)
            BridgeEventLog.shared.append(category: .bridge, summary: "keys \(label) [\(keys.joined(separator: ", "))]")
            return ok([:])

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

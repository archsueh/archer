import Foundation

// [archer] Shared dispatch for Bridge GUI console + tests — same semantics
// as BridgeServer type/keys/read/handoff, without needing a socket.

enum BridgeVerb: String, CaseIterable, Identifiable {
    case type
    case keys
    case read
    case handoff

    var id: String {
        rawValue
    }
}

struct BridgeActionError: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String {
        message
    }

    var localizedDescription: String {
        message
    }
}

enum BridgeAction {
    /// Perform one bridge verb against `@label` (or agent id for handoff).
    /// Syncs PaneRegistry from `store.active` first.
    @MainActor
    static func perform(
        verb: BridgeVerb,
        target: String,
        text: String,
        store: WorkspaceStore?,
        readLines: Int = 20
    ) -> Result<String, BridgeActionError> {
        let label = PaneRegistry.normalizeLabel(target)
        guard !label.isEmpty else { return .failure(.init(message: "missing target label")) }

        PaneRegistry.shared.sync(workspace: store?.active)

        switch verb {
        case .type:
            guard PaneRegistry.shared.session(forAddress: label) != nil else {
                return .failure(.init(message: "label not found: \(PaneRegistry.at(label))"))
            }
            let payload = text
            PaneRegistry.shared.type(label: label, text: payload)
            let preview = payload.prefix(40).replacingOccurrences(of: "\n", with: "↵")
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "type → \(PaneRegistry.at(label)) \"\(preview)\""
            )
            return .success("typed → \(PaneRegistry.at(label))")

        case .keys:
            guard PaneRegistry.shared.session(forAddress: label) != nil else {
                return .failure(.init(message: "label not found: \(PaneRegistry.at(label))"))
            }
            let keys = text
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !keys.isEmpty else {
                return .failure(.init(message: "missing keys (e.g. Enter)"))
            }
            PaneRegistry.shared.keys(label: label, keys: keys)
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "keys → \(PaneRegistry.at(label)) [\(keys.joined(separator: ", "))]"
            )
            return .success("keys → \(PaneRegistry.at(label))")

        case .read:
            guard let textOut = PaneRegistry.shared.read(label: label, lines: readLines) else {
                return .failure(.init(
                    message: "label not found or surface unavailable: \(PaneRegistry.at(label))"
                ))
            }
            BridgeEventLog.shared.append(
                category: .bridge,
                summary: "read \(PaneRegistry.at(label)) \(readLines)L → \(textOut.count)ch"
            )
            return .success(textOut)

        case .handoff:
            guard let store else {
                return .failure(.init(message: "no active store"))
            }
            let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let result = try store.openAgentTab(
                    agentId: label,
                    prompt: prompt.isEmpty ? nil : prompt
                )
                let preview = prompt.isEmpty
                    ? "(no prompt)"
                    : String(prompt.prefix(48)).replacingOccurrences(of: "\n", with: "↵")
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
                return .success("opened \(PaneRegistry.at(result.label))")
            } catch {
                return .failure(.init(message: error.localizedDescription))
            }
        }
    }
}

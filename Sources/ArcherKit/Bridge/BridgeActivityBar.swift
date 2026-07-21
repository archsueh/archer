import SwiftUI

// [archer] Main-window Bridge activity strip — design: interface.html `.bridgebar`
// Data source: BridgeEventLog.shared (same ring as Log panel). Collapsed by
// default: "BRIDGE" + newest summary; expand lists recent bridge/hook lines.

struct BridgeActivityBar: View {
    /// Required for ↗ open console — handoff / registry sync need a live store.
    /// ContentView and AppDelegate ⌘⇧B both pass the active window store.
    let store: WorkspaceStore

    @State private var log = BridgeEventLog.shared
    @State private var isOpen = false

    private static let previewLimit = 12

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            header
            if isOpen {
                expandedBody
            }
        }
        .font(Theme.mono(11))
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(Theme.chromeTransition) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("BRIDGE")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.chromeMuted)
                        .tracking(0.8)
                    Text(latestSummary)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.chromeMuted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Collapse Bridge activity" : "Expand Bridge activity")

            Button {
                // Full console — always via launcher so store cannot be omitted.
                BridgeConsoleLauncher.open(store: store)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.chromeMuted)
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Agent Bridge console (⌘⇧B)")
            .padding(.trailing, 6)
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if log.entries.isEmpty {
                        Text("No bridge or hook events yet")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.chromeMuted)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(log.entries.prefix(Self.previewLimit))) { entry in
                            eventRow(entry)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
            }
            .frame(maxHeight: 120)
            Button {
                BridgeConsoleLauncher.open(store: store)
            } label: {
                Text("Open Agent Bridge console…")
                    .font(Theme.mono(10.5, weight: .medium))
                    .foregroundStyle(Theme.activityRunning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .help("⌘⇧B · always opens with this window's store")
        }
    }

    private func eventRow(_ entry: BridgeEventLog.Entry) -> some View {
        let verb = Self.verb(from: entry)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verb.label)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(verb.color)
                .frame(width: 42, alignment: .leading)
            Text(entry.summary)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var latestSummary: String {
        if let first = log.entries.first {
            return first.summary
        }
        return "idle · list / type / keys via archer-bridge"
    }

    /// Map log summary text to design verb colors (read / type / keys / handoff).
    private static func verb(from entry: BridgeEventLog.Entry) -> (label: String, color: Color) {
        if entry.category == .hook {
            return ("hook", Theme.activityAttention)
        }
        let s = entry.summary.lowercased()
        if s.hasPrefix("handoff") {
            return ("handoff", Theme.activityRunning)
        }
        if s.hasPrefix("type ") || s.hasPrefix("type →") {
            return ("type", Theme.activityRunning)
        }
        if s.hasPrefix("keys ") || s.hasPrefix("keys →") {
            return ("keys", Theme.activityAttention)
        }
        if s.hasPrefix("read ") {
            return ("read", Theme.chromeMuted)
        }
        if s.hasPrefix("list") {
            return ("list", Theme.chromeMuted)
        }
        if s.hasPrefix("sync") {
            return ("sync", Theme.chromeMuted)
        }
        return ("cmd", Theme.activityRunning)
    }
}

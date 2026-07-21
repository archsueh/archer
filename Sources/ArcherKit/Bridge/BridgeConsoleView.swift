import Combine
import SwiftUI

// [archer] Agent Bridge console — design bridge.html:
// left roster (@labels), center log, bottom verb + target + send.
// Not a chat room: commands are type / keys / read / handoff on @addresses.

struct BridgeConsoleView: View {
    /// Live store for handoff + registry sync. Nil → type/keys/read still
    /// work if PaneRegistry was filled elsewhere; handoff fails clearly.
    var storeProvider: () -> WorkspaceStore? = { nil }

    @State private var log = BridgeEventLog.shared
    @State private var labels: [String] = []
    @State private var selectedLabel: String?
    @State private var verb: BridgeVerb = .type
    @State private var draft = ""
    @State private var status: String?
    @State private var lastRead: String?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            HStack(spacing: 0) {
                roster
                    .frame(width: 200)
                Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                mainColumn
            }
        }
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onAppear(perform: refreshLabels)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            refreshLabels()
        }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text("Agent Bridge")
                .font(Theme.mono(12, weight: .bold))
                .foregroundStyle(Theme.chromeForeground)
            Text("· @label · type / keys / read / handoff")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
            Spacer()
            Text("\(log.entries.count)")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
            Button("Clear") { log.clear() }
                .buttonStyle(.plain)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.chromeActive)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    // MARK: - Roster

    private var roster: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verb == .handoff ? "AGENTS · HANDOFF" : "PANES · @LABEL")
                .font(Theme.mono(9.5, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            if labels.isEmpty {
                Text(verb == .handoff ? "No launchable agents" : "No agent tabs")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(12)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(labels, id: \.self) { label in
                            rosterRow(label)
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.12))
    }

    private func rosterRow(_ label: String) -> some View {
        let selected = selectedLabel == label
        return Button {
            selectedLabel = label
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.activityRunning)
                    .frame(width: 7, height: 7)
                Text(PaneRegistry.at(label))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.activityRunning.opacity(0.12) : .clear)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle()
                        .fill(Theme.activityRunning)
                        .frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log + composer

    private var mainColumn: some View {
        VStack(spacing: 0) {
            logHeader
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            logBody
            if let lastRead {
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                ScrollView {
                    Text(lastRead)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxHeight: 120)
            }
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            composer
        }
    }

    private var logHeader: some View {
        HStack {
            Text("BRIDGE LOG")
                .font(Theme.mono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.chromeMuted)
            Spacer()
            if let status {
                Text(status)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.activityRunning)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private var logBody: some View {
        Group {
            if log.entries.isEmpty {
                VStack(spacing: 6) {
                    Text("No bridge activity yet")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.chromeMuted)
                    Text("Pick @label · choose verb · send — or use archer-bridge CLI")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeFaint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(log.entries) { entry in
                            consoleLogRow(entry)
                            Rectangle().fill(Theme.chromeHairline.opacity(0.4)).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func consoleLogRow(_ entry: BridgeEventLog.Entry) -> some View {
        let v = Self.verbColor(entry)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
                .frame(width: 56, alignment: .leading)
            Text(v.label)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(v.color)
                .frame(width: 48, alignment: .leading)
            Text(entry.summary)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeForeground.opacity(0.88))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                verbPicker
                targetChip
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.chromeHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Theme.chromeHairline, lineWidth: 1)
                    )
                    .onSubmit { send() }
                Button(action: send) {
                    Text("发送")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.chromeForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.chromeActive)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            Text(hint)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
        }
        .padding(12)
    }

    private var verbPicker: some View {
        HStack(spacing: 0) {
            ForEach(BridgeVerb.allCases) { v in
                Button {
                    verb = v
                    refreshLabels()
                } label: {
                    Text(v.rawValue)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(verb == v ? Theme.chromeForeground : Theme.chromeMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(verb == v ? Theme.chromeActive : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Theme.chromeHairline, lineWidth: 1)
        )
    }

    private var targetChip: some View {
        Text(selectedLabel.map { PaneRegistry.at($0) } ?? "@—")
            .font(Theme.mono(11.5))
            .foregroundStyle(Theme.activityRunning)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Theme.activityRunning.opacity(0.4), lineWidth: 1)
            )
    }

    private var placeholder: String {
        switch verb {
        case .type: return "text to inject…"
        case .keys: return "Enter  or  ctrl+c"
        case .read: return "(optional) leave empty"
        case .handoff: return "optional brief / initial prompt…"
        }
    }

    private var hint: String {
        "Select target on the left · type injects keystrokes · keys sends named keys · read captures screen · handoff opens agent tab"
    }

    // MARK: - Actions

    private func refreshLabels() {
        // Only sync when we have a store. sync(nil) CLEARS the registry and would
        // wipe live CLI/@label state if the window was opened without a provider.
        if let store = storeProvider() {
            PaneRegistry.shared.sync(workspace: store.active)
        }
        let next: [String]
        if verb == .handoff {
            // Handoff opens a *new* tab — list launchable agent ids, not only live panes.
            next = AgentTemplate.visibleOrdered(model: ArcherSettingsModel.shared)
                .filter { !$0.isShell }
                .map(\.id)
        } else {
            next = Array(PaneRegistry.shared.entries.keys).sorted()
        }
        labels = next
        if let sel = selectedLabel, !next.contains(sel) {
            selectedLabel = next.first
        } else if selectedLabel == nil {
            selectedLabel = next.first
        }
    }

    private func send() {
        guard let target = selectedLabel ?? labels.first else {
            status = "no target"
            return
        }
        // For handoff, target is agent id; for others, registry label.
        let result = BridgeAction.perform(
            verb: verb,
            target: target,
            text: draft,
            store: storeProvider()
        )
        switch result {
        case let .success(msg):
            if verb == .read {
                lastRead = msg
                status = "read \(PaneRegistry.at(target))"
            } else {
                lastRead = nil
                status = msg
            }
            if verb == .type || verb == .handoff {
                draft = ""
            }
            refreshLabels()
        case let .failure(err):
            status = err.message
        }
    }

    private static func verbColor(_ entry: BridgeEventLog.Entry) -> (label: String, color: Color) {
        if entry.category == .hook { return ("hook", Theme.activityAttention) }
        let s = entry.summary.lowercased()
        if s.hasPrefix("handoff") { return ("handoff", Theme.activityRunning) }
        if s.hasPrefix("type") { return ("type", Theme.activityRunning) }
        if s.hasPrefix("keys") { return ("keys", Theme.activityAttention) }
        if s.hasPrefix("read") { return ("read", Theme.chromeMuted) }
        return ("cmd", Theme.chromeMuted)
    }
}

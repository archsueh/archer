// [archer] ShowAgent panel — native Archer surface for the vendored
// showagent binary (aytzey/showagent). Lists every local coding-agent
// session and offers convert/branch/resume. All writes are delegated to
// showagent itself (ShowAgentBridge); Archer never re-implements its
// parsers or executes an agent CLI on the user's behalf.
import AppKit
import SwiftUI

// MARK: - Row

private struct ShowAgentRow: View {
    let session: ShowAgentSession

    var body: some View {
        HStack(spacing: 10) {
            AgentIconView(asset: nil, fallbackSymbol: session.symbol, size: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.providerLabel)
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(Theme.chromeForeground)
                    Text(session.workspace)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeMuted)
                        .lineLimit(1)
                }
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - View

@MainActor
struct ShowAgentView: View {
    @State private var sessions: [ShowAgentSession] = []
    @State private var query: String = ""
    @State private var selected: ShowAgentSession?
    @State private var convertTarget: String = "claude"
    @State private var isBusy: Bool = false

    private let targets = ["claude", "codex", "gemini", "opencode", "jcode"]

    private var filtered: [ShowAgentSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sessions }
        return sessions.filter { s in
            [s.provider, s.providerLabel, s.workspace,
             s.firstMessage, s.lastMessage]
                .contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().background(Theme.chromeHairline)
            listArea
            Divider().background(Theme.chromeHairline)
            actionBar
        }
        .frame(width: 680, height: 460)
        .glassWindowBackground(fallback: Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onAppear(perform: load)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.chromeMuted)
            TextField("Search sessions…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.chromeForeground)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var listArea: some View {
        List(selection: $selected) {
            ForEach(filtered) { s in
                ShowAgentRow(session: s).tag(s)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let sel = selected {
                Text(sel.providerLabel)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
                Spacer()
                Button("Branch") { branch(sel) }
                Picker("Convert to", selection: $convertTarget) {
                    ForEach(targets, id: \.self) { Text($0) }
                }
                .frame(width: 110)
                .controlSize(.small)
                Button("Convert") { convert(sel) }
                Button("Resume") { resume(sel) }
            } else {
                Text("Select a session")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
                Spacer()
            }
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func load() {
        Task {
            do { sessions = try ShowAgentBridge.list() }
            catch let e { notify(title: "ShowAgent error", body: errorDesc(e)) }
        }
    }

    private func convert(_ s: ShowAgentSession) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let r = try ShowAgentBridge.convert(sessionId: s.id, to: convertTarget)
                notify(title: "ShowAgent", body: "Converted \(s.provider) → \(r.provider): \(r.id)")
            } catch let e { notify(title: "ShowAgent error", body: errorDesc(e)) }
        }
    }

    private func branch(_ s: ShowAgentSession) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let r = try ShowAgentBridge.branch(sessionId: s.id)
                notify(title: "ShowAgent", body: "Branched → \(r.provider): \(r.id)")
            } catch let e { notify(title: "ShowAgent error", body: errorDesc(e)) }
        }
    }

    private func resume(_ s: ShowAgentSession) {
        Task {
            do {
                let r = try ShowAgentBridge.resumeRecipe(sessionId: s.id)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(r.resumeCommand, forType: .string)
                notify(title: "ShowAgent", body: "Resume command copied: \(r.resumeCommand)")
            } catch let e { notify(title: "ShowAgent error", body: errorDesc(e)) }
        }
    }

    private func notify(title: String, body: String) {
        // [archer] NotificationManager has no shared singleton; it is
        // owned by AppDelegate. A local instance still delivers the
        // banner via UNUserNotificationCenter (doesn't need start()'s
        // delegate wiring, which only routes click-backs to a tab).
        NotificationManager().post(title: title, body: body, sessionId: UUID())
    }

    private func errorDesc(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }
}

// MARK: - Window controller

/// Singleton floating NSPanel host for the ShowAgent surface. Mirrors
/// CommandPaletteWindowController's glass + nonactivating-panel pattern.
@MainActor
final class ShowAgentWindowController: NSWindowController {
    static let shared = ShowAgentWindowController()
    private static let size = NSSize(width: 680, height: 460)

    convenience init() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.appearance = Theme.windowAppearance
        panel.applyGlassBacking()
        self.init(window: panel)
    }

    func show() {
        guard let panel = window else { return }
        panel.contentViewController = NSHostingController(rootView: ShowAgentView())
        panel.setContentSize(Self.size)
        if let anchor = NSApp.keyWindow ?? NSApp.mainWindow {
            let f = anchor.frame
            let x = f.midX - Self.size.width / 2
            let y = f.maxY - 60 - Self.size.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
    }
}

import AppKit
import SwiftUI

// MARK: - Bridge / Log Panel Window Controller

/// Window → Agent Bridge — design `bridge.html` console (roster + log + composer).
/// Replaces the read-only Log panel; title "Agent Bridge".
final class LogPanelWindowController: NSWindowController {
    static let shared = LogPanelWindowController()
    private var host: NSHostingController<BridgeConsoleView>?

    /// Resolved at show time — same pattern as BridgeServer.storeProvider.
    var storeProvider: (() -> WorkspaceStore?)?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Open the Agent Bridge console.
    /// - Parameter storeProvider: **Required.** Active window store for handoff
    ///   and PaneRegistry refresh. Callers must not omit it — `sync(nil)` would
    ///   wipe live @labels (see `testActivityBarOpenPathKeepsStoreAndRegistry`).
    static func show(storeProvider: @escaping () -> WorkspaceStore?) {
        let controller = shared
        controller.storeProvider = storeProvider
        controller.buildWindowIfNeeded()
        if let host = controller.host {
            host.rootView = BridgeConsoleView(storeProvider: storeProvider)
        }
        if controller.window?.isVisible != true { controller.window?.center() }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Test / inspect: last storeProvider installed by `show`.
    static var installedStoreProvider: (() -> WorkspaceStore?)? {
        shared.storeProvider
    }

    private func buildWindowIfNeeded() {
        guard window == nil else { return }
        // storeProvider set by show(storeProvider:) immediately before this.
        let provider = storeProvider ?? { nil }
        let view = BridgeConsoleView(storeProvider: provider)
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Agent Bridge"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 960, height: 620))
        window.minSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        self.window = window
    }
}

// MARK: - Legacy LogPanelView (kept for any external references)

/// Read-only log list — prefer `BridgeConsoleView` for the product window.
struct LogPanelView: View {
    @State private var log = BridgeEventLog.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LOG")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.chromeMuted)
                    .tracking(1.5)
                Spacer()
                Button("Clear") { log.clear() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
            }
            .padding(12)
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            if log.entries.isEmpty {
                Text("No activity yet")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(log.entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeMuted)
                                    .frame(width: 60, alignment: .leading)
                                Text(entry.summary)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.chromeForeground.opacity(0.85))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            Rectangle().fill(Theme.chromeHairline.opacity(0.5)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }
}

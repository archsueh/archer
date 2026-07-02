import AppKit
import SwiftUI

/// Standalone "Sessions" window — mirrors `Bridge/LogPanelView.swift`'s
/// `LogPanelWindowController` shape (singleton, private init, lazy build,
/// `isReleasedWhenClosed = false` so state/frame survive close/reopen).
///
/// Unlike the static `LogPanelView`, rows must live-refresh while the
/// window is open (sessions start/stop/change state continuously). Rather
/// than threading an `@Observable` model into `SessionsDashboardView`, this
/// reassigns `host.rootView` on a timer — `CommandPaletteWindowController`
/// already documents that swapping `rootView` on the same hosting
/// controller preserves SwiftUI `@State` (selection, filter, focus), so a
/// plain refresh loop gets live data without an extra observable layer.
///
/// Takes closures only (`stores`/`tokenLookup`/`onJump`/`onClose`) — zero
/// dependency on `AppDelegate` or `ArcherWindowController` types, matching
/// `CommandPaletteWindowController.show(...)`'s existing decoupling.
@MainActor
final class SessionsWindowController: NSWindowController {
    static let shared = SessionsWindowController()

    private var host: NSHostingController<SessionsDashboardView>?
    private var refreshTask: Task<Void, Never>?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    static func show(
        stores: @escaping () -> [WorkspaceStore],
        tokenLookup: @escaping (String) -> Int?,
        onJump: @escaping (SessionDashboardRow) -> Void,
        onClose: @escaping (SessionDashboardRow) -> Void
    ) {
        let controller = shared
        controller.buildWindowIfNeeded(stores: stores, tokenLookup: tokenLookup, onJump: onJump, onClose: onClose)
        if controller.window?.isVisible != true { controller.window?.center() }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.startRefreshLoop(stores: stores, tokenLookup: tokenLookup, onJump: onJump, onClose: onClose)
    }

    private func buildWindowIfNeeded(
        stores: () -> [WorkspaceStore],
        tokenLookup: (String) -> Int?,
        onJump: @escaping (SessionDashboardRow) -> Void,
        onClose: @escaping (SessionDashboardRow) -> Void
    ) {
        guard window == nil else { return }
        let rows = SessionDashboardIndex.build(stores: stores(), tokenLookup: tokenLookup)
        let view = SessionsDashboardView(rows: rows, onJump: onJump, onClose: onClose)
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Sessions"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 560))
        window.minSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        self.window = window
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window
        )
    }

    @objc private func windowWillClose(_: Notification) {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func startRefreshLoop(
        stores: @escaping () -> [WorkspaceStore],
        tokenLookup: @escaping (String) -> Int?,
        onJump: @escaping (SessionDashboardRow) -> Void,
        onClose: @escaping (SessionDashboardRow) -> Void
    ) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let rows = SessionDashboardIndex.build(stores: stores(), tokenLookup: tokenLookup)
                self.host?.rootView = SessionsDashboardView(rows: rows, onJump: onJump, onClose: onClose)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

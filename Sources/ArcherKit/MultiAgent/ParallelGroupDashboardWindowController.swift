import AppKit
import SwiftUI

// Standalone dashboard for parallel-task groups.
// Drop-in host; wiring to Command Palette / menu can be added later.

final class ParallelGroupDashboardWindowController: NSWindowController {
    static let shared = ParallelGroupDashboardWindowController()

    private var host: NSHostingController<ParallelGroupDashboardView>?
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
        onDrillDown: @escaping (ParallelGroupViewModel) -> Void = { _ in }
    ) {
        let controller = shared
        controller.buildWindowIfNeeded(stores: stores, onDrillDown: onDrillDown)
        if controller.window?.isVisible != true { controller.window?.center() }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.startRefreshLoop(stores: stores, onDrillDown: onDrillDown)
    }

    private func buildWindowIfNeeded(
        stores: @escaping () -> [WorkspaceStore],
        onDrillDown: @escaping (ParallelGroupViewModel) -> Void
    ) {
        guard window == nil else { return }
        let groups = ParallelGroupDashboardIndex.build(stores: stores())
        let view = ParallelGroupDashboardView(groups: groups, onDrillDown: onDrillDown)
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Parallel Groups"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 560))
        window.minSize = NSSize(width: 720, height: 360)
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        self.window = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowWillClose(_: Notification) {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func startRefreshLoop(
        stores: @escaping () -> [WorkspaceStore],
        onDrillDown: @escaping (ParallelGroupViewModel) -> Void
    ) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let groups = ParallelGroupDashboardIndex.build(stores: stores())
                self.host?.rootView = ParallelGroupDashboardView(groups: groups, onDrillDown: onDrillDown)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

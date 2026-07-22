import AppKit
import SwiftUI

/// Standalone Observability window.
/// Mirrors `SessionsWindowController` shape but only launches `ObservabilityView`.
final class ObservabilityWindowController: NSWindowController {
    static let shared = ObservabilityWindowController()

    private var host: NSHostingController<ObservabilityView>?
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
        usageLookup: @escaping (String) -> Int? = { _ in nil },
        bridgeLog: BridgeEventLog? = BridgeEventLog.shared,
        onDrillDown: @escaping (AgentObservabilityRow) -> Void = { _ in }
    ) {
        let controller = shared
        controller.buildWindowIfNeeded(stores: stores, usageLookup: usageLookup, bridgeLog: bridgeLog, onDrillDown: onDrillDown)
        if controller.window?.isVisible != true { controller.window?.center() }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.startRefreshLoop(stores: stores, usageLookup: usageLookup, bridgeLog: bridgeLog, onDrillDown: onDrillDown)
    }

    private func buildWindowIfNeeded(
        stores: @escaping () -> [WorkspaceStore],
        usageLookup: @escaping (String) -> Int?,
        bridgeLog: BridgeEventLog? = BridgeEventLog.shared,
        onDrillDown: @escaping (AgentObservabilityRow) -> Void
    ) {
        guard window == nil else { return }
        let rows = ObservabilityIndex.build(stores: stores(), usageLookup: usageLookup, bridgeLog: bridgeLog)
        let view = ObservabilityView(rows: rows, onDrillDown: onDrillDown)
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Observability"
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
        usageLookup: @escaping (String) -> Int?,
        bridgeLog: BridgeEventLog? = BridgeEventLog.shared,
        onDrillDown: @escaping (AgentObservabilityRow) -> Void
    ) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let rows = ObservabilityIndex.build(stores: stores(), usageLookup: usageLookup, bridgeLog: bridgeLog)
                self.host?.rootView = ObservabilityView(rows: rows, onDrillDown: onDrillDown)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

import AppKit
import SwiftUI

final class UsagePanelWindowController: NSWindowController {
    static let shared = UsagePanelWindowController()
    private var host: NSHostingController<UsageView>?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    static func show() {
        let controller = shared
        controller.buildWindowIfNeeded()
        if controller.window?.isVisible != true {
            controller.window?.center()
        }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindowIfNeeded() {
        guard window == nil else { return }
        let store = WorkspaceStore(persistence: NullPersistence())
        store.activeScreen = .cockpit
        let view = UsageView(store: store)
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Agent Usage"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 860, height: 560))
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        self.window = window
    }
}

// [archer] Cockpit panel window controller
import AppKit
import SwiftUI

final class CockpitPanelWindowController: NSWindowController {
    static let shared = CockpitPanelWindowController()
    private var host: NSHostingController<CockpitView>?

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
        let view = CockpitView()
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Cockpit"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 1200, height: 760))
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        self.window = window
    }
}

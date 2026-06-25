import AppKit
import SwiftUI

final class SkillsPanelWindowController: NSWindowController {
    static let shared = SkillsPanelWindowController()
    private var host: NSHostingController<SkillsView>?

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
        let view = SkillsView(store: store)
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Skills"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 860, height: 560))
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        self.window = window
    }
}

import AppKit
import SwiftUI

// Hosts `ParallelGroupDashboardView` in a standalone window.

final class ParallelGroupDashboardController: NSWindowController {
    static let shared = ParallelGroupDashboardController()

    private static let panelSize = NSSize(width: 980, height: 620)

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Parallel Groups"
        panel.titleVisibility = .visible
        panel.toolbarStyle = .unified
        panel.isReleasedWhenClosed = false
        panel.appearance = Theme.windowAppearance
        panel.applyGlassBacking()
        panel.level = .floating
        self.init(window: panel)
    }

    func show(stores: @escaping () -> [WorkspaceStore]) {
        guard let panel = window else { return }
        panel.contentViewController = NSHostingController(
            rootView: ParallelGroupDashboardView(
                groups: ParallelGroupDashboardIndex.build(stores: stores())
            ) { [weak self] _ in
                // Drill-down is intentionally a no-op in this minimal surface
                // so the controller stays self-contained. Future work can
                // surface a focus target without changing the caller.
            }
        )
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

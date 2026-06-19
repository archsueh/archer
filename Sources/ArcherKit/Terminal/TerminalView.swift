import AppKit
import SwiftUI

struct TerminalView: NSViewRepresentable {
    let engine: any TerminalEngine
    /// Whether this pane is the workspace's active one. Set on the engine
    /// before the view mounts (`makeNSView` runs before `viewDidMoveToWindow`)
    /// so a workspace switch only re-focuses the active pane (issue #24).
    var grabsFocusOnMount = true
    /// Called when scroll position changes — persists to pane
    var onScrollPositionChange: ((_ offset: Int, _ total: Int, _ visible: Int) -> Void)?
    /// Called when new output arrives while scrolled up — shows Jump to Latest
    var onNewOutputWhileScrolledUp: (() -> Void)?

    func makeNSView(context _: Context) -> NSView {
        engine.grabsFocusOnMount = grabsFocusOnMount
        engine.onScrollPositionChange = onScrollPositionChange
        engine.onNewOutputWhileScrolledUp = onNewOutputWhileScrolledUp
        return engine.view
    }

    /// Also on update, not just mount: clicking a sibling pane flips `isFocused`
    /// in place (no re-mount → no `makeNSView`), so this keeps the engine flag in
    /// sync with the pane's active state for the next re-mount.
    func updateNSView(_: NSView, context _: Context) {
        engine.grabsFocusOnMount = grabsFocusOnMount
        engine.onScrollPositionChange = onScrollPositionChange
        engine.onNewOutputWhileScrolledUp = onNewOutputWhileScrolledUp
    }
}

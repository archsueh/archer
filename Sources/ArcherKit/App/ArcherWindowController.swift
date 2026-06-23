import AppKit
import SwiftUI

/// One archer window: an `NSWindow` paired with its own `WorkspaceStore`.
/// `AppDelegate` keeps an array of these — every window is fully
/// independent (own sidebar, own workspaces, own persisted slice keyed by
/// `windowId`).
@MainActor
final class ArcherWindowController: NSWindowController, NSWindowDelegate {
    let windowId: UUID
    let store: WorkspaceStore
    /// Set by `AppDelegate`. Fires from `windowWillClose` so the delegate
    /// can drop this window from its list and decide whether the window's
    /// persisted slot survives (one of several closed) or is discarded.
    var onWillClose: ((ArcherWindowController) -> Void)?
    /// Fires when this window becomes key — lets `AppDelegate` remember the
    /// most-recently-active archer window, so menu actions route there when a
    /// Settings / Update panel is the key window instead.
    var onDidBecomeKey: ((ArcherWindowController) -> Void)?

    init(windowId: UUID, store: WorkspaceStore) {
        self.windowId = windowId
        self.store = store
        super.init(window: Self.makeWindow())
        window?.delegate = self
        // [archer] glass: HUD vibrancy behind the SwiftUI tree (ports the
        // archer-vibrancy-injector into source; injector retired).
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        if let layer = effect.layer {
            layer.masksToBounds = false
            layer.setValue(true, forKey: "caEnableBlur")
            layer.setValue(Theme.chromeBackgroundBlur, forKey: "blurRadius")
            layer.setValue(Theme.chromeBackgroundSaturate, forKey: "saturation")
            layer.setValue(true, forKey: "caEnableColorSaturate")
        }
        let hosting = NSHostingView(rootView: ContentView(store: store))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        // Glass specular overlay: rim highlight + top-edge light catch.
        // Must be added after hosting so it sits above the SwiftUI tree.
        let specular = GlassSpecularView()
        specular.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(specular)
        NSLayoutConstraint.activate([
            specular.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            specular.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            specular.topAnchor.constraint(equalTo: effect.topAnchor),
            specular.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        window?.contentView = effect
        // The last workspace closing leaves an empty window — close it.
        store.onBecameEmpty = { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not a storyboard window")
    }

    /// Builds a archer main window with the standard chrome. Mirrors the
    /// config that used to live inline in `applicationDidFinishLaunching`.
    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ArcherApp.name
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Tab strips sit under the transparent titlebar; only our explicit
        // sidebar handle moves the window so tab DnD never races AppKit.
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.appearance = Theme.windowAppearance
        window.backgroundColor = .clear // [archer] let the HUD vibrancy show through
        // The controller governs the window's lifetime; without this,
        // `close()` would also `release` it out from under the controller.
        window.isReleasedWhenClosed = false
        // Every window's NSWindow title is the app name, so the system
        // Windows-menu / Dock-tile auto window list stacks a useless
        // "archer × N" above our own workspace/tab list. Drop them — the Dock
        // menu's workspace list and ⌘P are the real navigation.
        window.isExcludedFromWindowsMenu = true
        return window
    }

    func windowWillClose(_: Notification) {
        onWillClose?(self)
    }

    func windowDidBecomeKey(_: Notification) {
        onDidBecomeKey?(self)
    }
}

/// Hit-passthrough overlay that renders the liquid-glass specular rim and
/// top-edge highlight. Sits above the SwiftUI tree without consuming mouse events.
private final class GlassSpecularView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draw(_: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds

        // Top-edge highlight — simulates bent glass refracting overhead light.
        // In macOS CA coordinates, b.height is the top Y.
        let topH: CGFloat = 32
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09),
                     CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: b.height - topH, width: b.width, height: topH))
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: b.midX, y: b.height),
                                   end: CGPoint(x: b.midX, y: b.height - topH),
                                   options: [])
            ctx.restoreGState()
        }

        // Specular rim — thin white perimeter, like CSS inset box-shadow.
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20))
        ctx.setLineWidth(1.0)
        ctx.stroke(b.insetBy(dx: 0.5, dy: 0.5))
    }
}

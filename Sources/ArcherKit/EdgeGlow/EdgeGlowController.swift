import AppKit
import SwiftUI

/// Owns one transparent overlay window per in-scope screen and renders the
/// activity glow on them. Reads `ArcherSettingsModel`, reacts to screen
/// hotplug, and lets higher-priority signals win. See docs/edge-glow-plan.md.
@MainActor
final class EdgeGlowController {
    static let shared = EdgeGlowController()

    private var overlays: [EdgeGlowOverlayWindow] = []
    private var current: EdgeGlowState = .idle

    private init() {
        rebuildOverlays()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    private var settings: ArcherSettingsModel {
        .shared
    }

    /// Map a notification kind to a glow and render it. No-op when disabled.
    func handle(kind: SessionAlertKind) {
        guard settings.edgeGlowEnabled else { return }
        apply(EdgeGlow.state(for: kind))
    }

    /// Re-apply settings: rebuild overlays for the current scope; clear if off.
    func refresh() {
        rebuildOverlays()
        current = .idle
    }

    /// Clear a lingering hold — call when archer gains focus.
    func clearHolds() {
        guard current.lingers else { return }
        apply(.idle)
    }

    private func apply(_ state: EdgeGlowState) {
        // A lower-priority signal never overrides a lingering higher one.
        if current.lingers, state.priority < current.priority { return }
        current = state

        let color: NSColor? = state.tone.map { NSColor($0.color) }
        let brightness = CGFloat(settings.edgeGlowBrightness)
        let width = CGFloat(settings.edgeGlowWidth)
        for overlay in overlays {
            overlay.render(state, color: color, brightness: brightness, width: width)
        }
        // A pulse fades itself out — drop back to idle so the next signal wins.
        if case .pulse = state { current = .idle }
    }

    private func scopedScreens() -> [NSScreen] {
        if settings.edgeGlowScope == .currentScreen,
           let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        {
            return [screen]
        }
        return NSScreen.screens
    }

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = scopedScreens().map { EdgeGlowOverlayWindow(screen: $0) }
    }

    @objc private func screensChanged() {
        rebuildOverlays()
    }
}

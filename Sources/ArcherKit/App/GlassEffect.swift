import AppKit
import SwiftUI

// macOS 26 Liquid Glass, opt-in via ghostty's `background-blur = macos-glass-*`.
//
// The real effect is AppKit's `NSGlassEffectView`, which only exists in the
// macOS 26 SDK — so the wrapper below is fenced behind `#if compiler(>=6.2)`
// (the toolchain that ships that SDK) and `@available(macOS 26.0, *)` for the
// runtime check. This is a macOS 26+ feature on purpose: older systems can
// only manage an `NSVisualEffectView` frost that looks nothing like real
// glass, so on macOS 14/15 the chrome stays opaque (no effect) rather than
// shipping a poor imitation.

#if compiler(>=6.2)
    /// One real `NSGlassEffectView` bridged into SwiftUI as a background layer.
    /// Content-less — an empty glass view renders the effect tinted toward
    /// `tint`, which is exactly how ghostty uses it at the window level.
    @available(macOS 26.0, *)
    private struct GlassEffectLayer: NSViewRepresentable {
        let style: Theme.GlassStyle
        let tint: NSColor

        func makeNSView(context _: Context) -> NSGlassEffectView {
            let view = NSGlassEffectView()
            configure(view)
            return view
        }

        func updateNSView(_ view: NSGlassEffectView, context _: Context) {
            configure(view)
        }

        private func configure(_ view: NSGlassEffectView) {
            view.style = style.official
            view.tintColor = tint
        }
    }
#endif

extension View {
    /// Backmost window layer. On macOS 26 with a glass style configured this
    /// is the single real `NSGlassEffectView` that every chrome panel sits in
    /// front of and lets read through. Otherwise (glass off, or any system
    /// below macOS 26) it's the opaque `fallback` — pass the terminal surface
    /// color so the window edge stays seamless with the terminal, matching
    /// archer's pre-glass look exactly.
    func glassWindowBackground(fallback: Color) -> some View {
        // `.ignoresSafeArea()` lets the backing fill the whole window —
        // including under a transparent titlebar — while the foreground
        // content still respects the titlebar safe area. That's what keeps
        // the glass seamless on titled windows (Settings, Update) instead of
        // leaving an unglassed titlebar strip.
        background { GlassWindowBacking(fallback: fallback).ignoresSafeArea() }
    }

    /// Chrome panel background (sidebar, status bar, right panel). When glass
    /// is actively rendering (macOS 26 + a style set) it's a translucent chrome
    /// tint so the window glass shows through; otherwise the opaque chrome
    /// color — identical to archer's pre-glass chrome on every system below
    /// macOS 26.
    func glassChromeBackground() -> some View {
        background(Theme.glassEnabled ? Theme.glassPanelTint : Theme.chromeBackground)
    }
}

/// The window's backmost layer: real glass on macOS 26 (with ghostty-style
/// inactive masking), the opaque `fallback` otherwise. Reads
/// `controlActiveState` so it can cover the glass with the theme tint when the
/// window isn't key — without that, macOS washes inactive glass to a flat gray.
private struct GlassWindowBacking: View {
    let fallback: Color
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *), let style = Theme.glassStyle {
                GlassEffectLayer(style: style, tint: Theme.glassTint)
                    .overlay {
                        // Not the key window → mask the macOS gray with the theme
                        // tint so the whole window dims uniformly to the surface
                        // color instead of going half-gray.
                        if activeState != .key {
                            Theme.glassInactiveTint
                        }
                    }
            } else {
                fallback
            }
        #else
            fallback
        #endif
    }
}

extension NSWindow {
    /// Match the window's backing to the current glass state — non-opaque +
    /// clear so the `NSGlassEffectView` can sample the desktop behind it,
    /// opaque otherwise. Call at window creation and from
    /// `refreshThemeAppearances` so live toggles flip every window in step.
    @MainActor func applyGlassBacking() {
        let glass = Theme.glassEnabled
        isOpaque = !glass
        backgroundColor = glass ? .clear : nil
    }

    /// The glass-titlebar recipe shared by archer's titled auxiliary windows
    /// (Settings, About, Update): a transparent full-size titlebar so the
    /// glass backing runs edge to edge, plus the backing itself. Without the
    /// transparent full-size titlebar the glass leaves an unglassed strip up
    /// top. Callers still set their own `styleMask` base, size, and title.
    @MainActor func configureGlassChrome() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        applyGlassBacking()
    }
}

import AppKit

/// A transparent, click-through window pinned to one screen that draws a
/// hairline activity glow around its edge. No content, no shadow, no titlebar,
/// sharp corners (brutalist). See docs/edge-glow-spec.md / -plan.md.
final class EdgeGlowOverlayWindow: NSWindow {
    private let borderLayer = CAShapeLayer()
    private var strokeWidth: CGFloat = 3

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true // [archer] click-through
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        borderLayer.fillColor = nil
        borderLayer.lineJoin = .miter // sharp corners, no rounding
        borderLayer.opacity = 0
        host.layer?.addSublayer(borderLayer)
        contentView = host
        pin(to: screen)
        orderFrontRegardless()
    }

    /// Reposition/resize to a (possibly changed) screen frame.
    func pin(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        layoutBorder()
    }

    private func layoutBorder() {
        guard let bounds = contentView?.bounds else { return }
        borderLayer.frame = bounds
        let inset = strokeWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        borderLayer.path = CGPath(rect: rect, transform: nil)
        borderLayer.lineWidth = strokeWidth
    }

    /// Render a glow state. `color == nil` (idle) clears it. `brightness` (0...1)
    /// scales peak opacity; `width` sets stroke thickness.
    func render(_ state: EdgeGlowState, color: NSColor?, brightness: CGFloat, width: CGFloat) {
        strokeWidth = max(1, width)
        layoutBorder()

        guard let color else {
            borderLayer.removeAllAnimations()
            borderLayer.opacity = 0
            return
        }
        borderLayer.strokeColor = color.cgColor
        let peak = Float(max(0, min(1, brightness)))

        switch state {
        case .idle:
            borderLayer.removeAllAnimations()
            borderLayer.opacity = 0
        case .pulse:
            // Flash to peak then fade out; settle at 0.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = peak
            fade.toValue = 0
            fade.duration = 0.6
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            borderLayer.opacity = 0
            borderLayer.add(fade, forKey: "glow")
        case .hold, .running:
            // Stay lit at peak (running's marquee animation is PR2).
            borderLayer.removeAllAnimations()
            borderLayer.opacity = peak
        }
    }
}

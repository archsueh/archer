import SwiftUI

/// Square SF-symbol button with a hover-state background tint. Used for the
/// add (+) and close (×) controls in the sidebar and tab bar — keeps the
/// hover affordance consistent and the call sites tiny.
struct HoverableIconButton: View {
    let systemName: String
    let fontSize: CGFloat
    let size: CGFloat
    let help: String?
    let action: () -> Void
    /// Optional rotation in degrees applied to the symbol. Animated via
    /// `easeOut(0.15)` so toggle controls (sidebar disclosure chevron) get
    /// a smooth state transition; default 0 leaves static buttons (× / +)
    /// untouched.
    var rotation: Double = 0

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .medium))
                .rotationEffect(.degrees(rotation))
                .animation(.easeOut(duration: 0.15), value: rotation)
                .frame(width: size, height: size)
                .background(isHovered ? Theme.chromeHover : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(BrutalistIconButtonStyle())
        .onHover { isHovered = $0 }
        .help(help ?? "")
    }
}

struct BrutalistIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

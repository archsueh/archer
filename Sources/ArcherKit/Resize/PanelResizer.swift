import AppKit
import SwiftUI

/// [archer] Invisible panel divider — no visible edge, no line, no border.
/// Occupies 6pt for drag affordance only; hover changes cursor.
public struct PanelResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let panelSide: Edge
    let onCommit: () -> Void

    @State private var dragStart: Double?

    public init(width: Binding<Double>, range: ClosedRange<Double>, panelSide: Edge, onCommit: @escaping () -> Void = {}) {
        _width = width
        self.range = range
        self.panelSide = panelSide
        self.onCommit = onCommit
    }

    private var isVertical: Bool {
        panelSide == .top || panelSide == .bottom
    }

    public var body: some View {
        Color.clear
            .frame(width: isVertical ? nil : 6, height: isVertical ? 6 : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    (isVertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? width
                        if dragStart == nil { dragStart = start }
                        let delta: Double
                        if isVertical {
                            delta = panelSide == .top ? value.translation.height : -value.translation.height
                        } else {
                            delta = panelSide == .leading ? value.translation.width : -value.translation.width
                        }
                        width = PanelWidths.clamp(start + delta, to: range)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit()
                    }
            )
    }
}

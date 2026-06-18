import SwiftUI
import AppKit

// [archer] P2: draggable divider that resizes an adjacent panel. Place between a
// panel and its hairline. Updates `width` live (clamped), persists via onCommit on
// drag end. `edge` = which side of the resizer the panel sits on: .leading means the
// panel is to the left (drag right grows it), .trailing means panel is to the right.
public struct PanelResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let panelSide: Edge
    let onCommit: () -> Void

    @State private var dragStart: Double?

    public init(width: Binding<Double>, range: ClosedRange<Double>, panelSide: Edge, onCommit: @escaping () -> Void = {}) {
        self._width = width
        self.range = range
        self.panelSide = panelSide
        self.onCommit = onCommit
    }

    public var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? width
                        if dragStart == nil { dragStart = start }
                        // panel on the left grows when dragging right; on the right grows when dragging left.
                        let delta = panelSide == .leading ? value.translation.width : -value.translation.width
                        width = PanelWidths.clamp(start + delta, to: range)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit()
                    }
            )
    }
}

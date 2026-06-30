import SwiftUI

// MARK: - Layout types

private struct PlacedNode: Identifiable {
    let id: UUID
    let event: ToolCallEvent
    let column: Int
    let row: Int
    let rect: CGRect
}

// MARK: - Flow canvas

/// Directed-graph visualization of a session's tool-call history.
/// Nodes = individual tool calls; edges = sequential flow between steps.
/// Parallel tool calls (start times within 300 ms) are stacked vertically
/// in the same column. Renders with a Canvas layer for edges + node fills,
/// and SwiftUI overlay views for text labels so font/icon rendering stays
/// native without fighting CoreGraphics text APIs.
struct ToolCallFlowView: View {
    let events: [ToolCallEvent]

    // Layout constants
    private let nodeW: CGFloat = 114
    private let nodeH: CGFloat = 40
    private let colGap: CGFloat = 30
    private let rowGap: CGFloat = 8
    private let pad: CGFloat = 18

    var body: some View {
        let (nodes, canvasSize) = computeLayout()
        let edges = computeEdges(nodes)

        // Capture @MainActor-isolated computed colors before Canvas closure.
        let hairline = Theme.chromeHairline
        let muted = Theme.chromeMuted
        let actRunning = Theme.activityRunning
        let actFailed = Theme.activityFailure
        let actAttention = Theme.activityAttention
        let gitGreen = Theme.gitInsertion

        if nodes.isEmpty {
            emptyState
        } else {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Layer 1: edges + node fills (Canvas — cheap for many paths)
                    Canvas { ctx, _ in
                        // Edges first so nodes sit on top
                        for edge in edges {
                            ctx.stroke(edge, with: .color(hairline.opacity(0.55)), lineWidth: 1.5)
                            // Arrow head at the destination end
                            // (edge destination is the first cubic-curve endpoint)
                        }
                        // Node fills + left accent bar + border
                        for node in nodes {
                            let color = stateColor(node.event.state,
                                                   running: actRunning, failed: actFailed,
                                                   attention: actAttention, green: gitGreen, muted: muted)
                            let isRunning = node.event.state == .running
                            // Fill
                            ctx.fill(
                                Path(roundedRect: node.rect, cornerRadius: 7),
                                with: .color(color.opacity(0.08))
                            )
                            // Border
                            ctx.stroke(
                                Path(roundedRect: node.rect, cornerRadius: 7),
                                with: .color(isRunning ? color.opacity(0.45) : hairline.opacity(0.45)),
                                lineWidth: isRunning ? 1.5 : 0.75
                            )
                            // Left accent bar
                            let barRect = CGRect(
                                x: node.rect.minX + 1,
                                y: node.rect.minY + 7,
                                width: 2.5,
                                height: node.rect.height - 14
                            )
                            ctx.fill(
                                Path(roundedRect: barRect, cornerRadius: 1.25),
                                with: .color(color.opacity(isRunning ? 0.9 : 0.45))
                            )
                        }
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)

                    // Layer 2: text labels as SwiftUI views.
                    // Use .position(midX, midY) — it places the view centre at
                    // that coordinate in the parent's space, which is correct
                    // for absolute placement. .offset() only shifts visually and
                    // leaves all layout frames at (0,0), causing overlap.
                    ForEach(nodes) { node in
                        nodeLabel(node)
                            .frame(width: nodeW, height: nodeH)
                            .position(x: node.rect.midX, y: node.rect.midY)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .padding(.bottom, 4) // breathing room at scroll bottom
            }
        }
    }

    // MARK: - Node label

    @ViewBuilder
    private func nodeLabel(_ node: PlacedNode) -> some View {
        let color = stateColor(node.event.state,
                               running: Theme.activityRunning, failed: Theme.activityFailure,
                               attention: Theme.activityAttention, green: Theme.gitInsertion,
                               muted: Theme.chromeMuted)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: ToolCallActivityPill.toolIcon(node.event.toolName))
                    .imageScale(.small)
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.8))
                Text(node.event.toolName)
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(node.event.state.presentation.glyph)
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(node.event.identifier.isEmpty ? "—" : node.event.identifier)
                .font(Theme.mono(8.5, weight: .regular))
                .foregroundStyle(Theme.chromeMuted.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.right.square")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.chromeMuted.opacity(0.4))
            Text("no tool calls yet")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout

    private func computeLayout() -> ([PlacedNode], CGSize) {
        guard !events.isEmpty else {
            return ([], CGSize(width: 240, height: 80))
        }
        let sorted = events.sorted { $0.startedAt < $1.startedAt }

        // Group into columns: events starting within 300 ms of a column's
        // first event are considered parallel and share a column.
        var columns: [[ToolCallEvent]] = []
        var colStart = sorted[0].startedAt
        var current: [ToolCallEvent] = []

        for event in sorted {
            if current.isEmpty {
                current = [event]
                colStart = event.startedAt
            } else if event.startedAt.timeIntervalSince(colStart) < 0.3 {
                current.append(event)
            } else {
                columns.append(current)
                current = [event]
                colStart = event.startedAt
            }
        }
        if !current.isEmpty { columns.append(current) }

        var nodes: [PlacedNode] = []
        for (col, colEvents) in columns.enumerated() {
            let x = pad + CGFloat(col) * (nodeW + colGap)
            for (row, event) in colEvents.enumerated() {
                let y = pad + CGFloat(row) * (nodeH + rowGap)
                nodes.append(PlacedNode(
                    id: event.id,
                    event: event,
                    column: col,
                    row: row,
                    rect: CGRect(x: x, y: y, width: nodeW, height: nodeH)
                ))
            }
        }

        let maxRows = columns.map(\.count).max() ?? 1
        let totalW = pad * 2 + CGFloat(columns.count) * (nodeW + colGap) - colGap
        let totalH = pad * 2 + CGFloat(maxRows) * (nodeH + rowGap) - rowGap
        return (nodes, CGSize(width: max(totalW, 240), height: max(totalH, 80)))
    }

    // Edges: cubic bezier from right-center of each col-N node to left-center
    // of each col-(N+1) node. Many-to-many when parallel calls fan out/in.
    private func computeEdges(_ nodes: [PlacedNode]) -> [Path] {
        guard let maxCol = nodes.map(\.column).max(), maxCol > 0 else { return [] }
        var paths: [Path] = []

        for col in 0 ..< maxCol {
            let from = nodes.filter { $0.column == col }
            let to = nodes.filter { $0.column == col + 1 }
            for f in from {
                for t in to {
                    let start = CGPoint(x: f.rect.maxX, y: f.rect.midY)
                    let end = CGPoint(x: t.rect.minX, y: t.rect.midY)
                    let midX = (start.x + end.x) / 2
                    var p = Path()
                    p.move(to: start)
                    p.addCurve(to: end,
                               control1: CGPoint(x: midX, y: start.y),
                               control2: CGPoint(x: midX, y: end.y))
                    paths.append(p)
                }
            }
        }
        return paths
    }

    /// Pure function — takes pre-captured colors so it's safe inside Canvas.
    private func stateColor(
        _ state: ToolCallEventState,
        running: Color, failed: Color, attention _: Color, green: Color, muted: Color
    ) -> Color {
        switch state {
        case .running: return running
        case .success: return green
        case .failed: return failed
        case .stalled: return muted
        }
    }
}

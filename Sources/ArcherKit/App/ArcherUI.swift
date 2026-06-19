import AppKit
import SwiftUI

// MARK: - Collapsible Sidebar

struct ArcherCollapsibleSidebar<Sidebar: View, Detail: View>: View {
    @Binding var layout: ArcherSplitLayout
    let detailMinWidth: CGFloat
    let sidebar: Sidebar
    let detail: Detail

    init(
        layout: Binding<ArcherSplitLayout>,
        detailMinWidth: CGFloat,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        _layout = layout
        self.detailMinWidth = detailMinWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        ZStack {
            if layout.isSidebarCollapsed {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            } else {
                ArcherPersistentSidebarSplitView(layout: $layout, detailMinWidth: detailMinWidth) {
                    sidebar
                } detail: {
                    detail
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(Theme.collapseAnimation, value: layout.isSidebarCollapsed)
    }
}

struct ArcherSplitLayout: Equatable {
    let minSidebarWidth: CGFloat
    let defaultSidebarWidth: CGFloat
    let maxSidebarWidth: CGFloat
    var sidebarWidth: CGFloat?
    var isSidebarCollapsed: Bool

    init(
        minSidebarWidth: CGFloat = 160,
        defaultSidebarWidth: CGFloat = 220,
        maxSidebarWidth: CGFloat = 320,
        isSidebarCollapsed: Bool = false
    ) {
        self.minSidebarWidth = minSidebarWidth
        self.defaultSidebarWidth = defaultSidebarWidth
        self.maxSidebarWidth = max(maxSidebarWidth, minSidebarWidth)
        self.isSidebarCollapsed = isSidebarCollapsed
    }

    var preferredSidebarWidth: CGFloat {
        clamped(sidebarWidth ?? defaultSidebarWidth)
    }

    mutating func rememberSidebarWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let clampedWidth = clamped(width)
        if let sidebarWidth, abs(sidebarWidth - clampedWidth) < 1 { return }
        sidebarWidth = clampedWidth
    }

    private func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minSidebarWidth), maxSidebarWidth)
    }
}

struct ArcherPersistentSidebarSplitView<Sidebar: View, Detail: View>: NSViewRepresentable {
    @Binding var layout: ArcherSplitLayout
    let detailMinWidth: CGFloat
    let sidebar: Sidebar
    let detail: Detail

    init(
        layout: Binding<ArcherSplitLayout>,
        detailMinWidth: CGFloat,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        _layout = layout
        self.detailMinWidth = detailMinWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let sidebarHost = NSHostingView(rootView: sidebar)
        sidebarHost.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.clipsToBounds = true

        let detailHost = NSHostingView(rootView: detail)
        detailHost.translatesAutoresizingMaskIntoConstraints = false
        detailHost.clipsToBounds = true

        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(detailHost)

        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost
        context.coordinator.layout = $layout
        context.coordinator.detailMinWidth = detailMinWidth

        context.coordinator.applyLayout(in: splitView)
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.sidebarHost?.rootView = sidebar
        context.coordinator.detailHost?.rootView = detail
        context.coordinator.layout = $layout
        context.coordinator.detailMinWidth = detailMinWidth
        context.coordinator.applyLayout(in: splitView)
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var sidebarHost: NSHostingView<Sidebar>?
        var detailHost: NSHostingView<Detail>?
        var layout: Binding<ArcherSplitLayout>?
        var detailMinWidth: CGFloat = 0
        private var isRestoringDivider = false
        private var hasRestoredDivider = false

        func applyLayout(in splitView: NSSplitView) {
            guard splitView.subviews.count > 1, let layout else { return }

            if layout.wrappedValue.isSidebarCollapsed {
                collapseSidebar(in: splitView)
                hasRestoredDivider = true
                return
            }

            if sidebarHost?.isHidden == true {
                isRestoringDivider = true
                sidebarHost?.isHidden = false
                splitView.adjustSubviews()
                splitView.needsDisplay = true
                isRestoringDivider = false
            }

            restoreDividerPosition(in: splitView)
        }

        private func collapseSidebar(in splitView: NSSplitView) {
            guard splitView.subviews.count > 1 else { return }
            isRestoringDivider = true
            sidebarHost?.isHidden = true
            splitView.setPosition(0, ofDividerAt: 0)
            splitView.adjustSubviews()
            splitView.needsDisplay = true
            isRestoringDivider = false
        }

        func restoreDividerPosition(in splitView: NSSplitView) {
            guard splitView.subviews.count > 1, let layout else { return }

            if splitView.bounds.width <= 0 {
                DispatchQueue.main.async { [weak self, weak splitView] in
                    guard let self, let splitView else { return }
                    self.restoreDividerPosition(in: splitView)
                }
                return
            }

            let preferredWidth = layout.wrappedValue.preferredSidebarWidth
            let maxSidebarWidth = min(splitView.bounds.width - detailMinWidth, layout.wrappedValue.maxSidebarWidth)
            let targetWidth = max(preferredWidth, layout.wrappedValue.minSidebarWidth)
            let finalWidth = min(targetWidth, maxSidebarWidth)

            if !isRestoringDivider {
                let currentPosition = splitView.subviews[0].frame.width
                if abs(currentPosition - finalWidth) > 1 {
                    isRestoringDivider = true
                    splitView.setPosition(finalWidth, ofDividerAt: 0)
                    splitView.adjustSubviews()
                    isRestoringDivider = false
                }
            }

            if !hasRestoredDivider, finalWidth > layout.wrappedValue.minSidebarWidth {
                layout.wrappedValue.rememberSidebarWidth(finalWidth)
                hasRestoredDivider = true
            }
        }

        func splitView(_: NSSplitView,
                       constrainMinCoordinate proposedMinimum: CGFloat,
                       ofSubviewAt _: Int) -> CGFloat
        {
            guard let layout else { return proposedMinimum }
            return max(proposedMinimum, layout.wrappedValue.minSidebarWidth)
        }

        func splitView(_ splitView: NSSplitView,
                       constrainMaxCoordinate proposedMaximum: CGFloat,
                       ofSubviewAt _: Int) -> CGFloat
        {
            return min(proposedMaximum, splitView.bounds.width - detailMinWidth)
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  splitView.subviews.count > 1,
                  let layout,
                  !isRestoringDivider,
                  !layout.wrappedValue.isSidebarCollapsed else { return }

            let sidebarWidth = splitView.subviews[0].frame.width
            if sidebarWidth > layout.wrappedValue.minSidebarWidth {
                layout.wrappedValue.rememberSidebarWidth(sidebarWidth)
            }
        }
    }
}

// MARK: - Toolbar Controls

struct ArcherCollapseToolbarButton: View {
    let systemImage: String
    let isActive: Bool
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .symbolVariant(isActive ? .fill : .none)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Theme.chromeHover : .clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isActive ? Theme.chromeHairline : .clear, lineWidth: 1)
                }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isActive ? Theme.chromeForeground
            : Theme.chromeForeground.opacity(isEnabled ? 0.82 : 0.32))
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

// MARK: - Toast

struct ArcherStatusToast: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

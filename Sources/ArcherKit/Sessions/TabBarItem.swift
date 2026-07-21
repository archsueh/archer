import SwiftUI

struct TabBarItem: View {
    @Bindable var tab: Session
    let isActive: Bool
    let canCloseToRight: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseToRight: () -> Void
    let onDuplicate: () -> Void
    let onRename: (String) -> Void
    let onSplit: (SplitOrientation) -> Void
    let onMoveToNewWindow: () -> Void

    @State private var isHovered = false
    @State private var isContextMenuOpen = false
    @State private var isRenameOpen = false
    @State private var pendingRename = ""

    var body: some View {
        HStack(spacing: 7) {
            commandStatusDot
            AgentIconView(asset: tab.displayAgent.iconAsset, fallbackSymbol: tab.displayAgent.symbol, size: 15)
            Text(tab.title)
                .font(Theme.display(12, weight: .regular))
                .lineLimit(1)
            // [archer] Bridge @label addressing — registry label (e.g. @codex-2)
            // when multi-instance; shell tabs stay clean.
            if !tab.displayAgent.isShell {
                Text(PaneRegistry.at(bridgeLabel))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.activityRunning)
                    .lineLimit(1)
                    .help("Bridge address · archer-bridge type \(PaneRegistry.at(bridgeLabel)) …")
                if let src = tab.drivenByLabel, !src.isEmpty {
                    Text("←\(PaneRegistry.at(src))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.activityRunning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Theme.activityRunning.opacity(0.45), lineWidth: 1)
                        )
                        .help("Handed off from \(PaneRegistry.at(src))")
                }
            }
            HoverableIconButton(
                systemName: "xmark",
                fontSize: 9,
                size: 16,
                help: "Close tab",
                action: onClose
            )
            .opacity(isHovered || isActive ? 1 : 0)
            .allowsHitTesting(isHovered || isActive)
        }
        .foregroundStyle(isActive ? Theme.chromeForeground : Theme.chromeForeground.opacity(0.6))
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { isHovered = $0 }
        .overlay(RightClickCatcher { _ in isContextMenuOpen = true })
        .popover(isPresented: $isContextMenuOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ArcherMenuRow(title: "Close Tab", shortcut: "⌘W") {
                    isContextMenuOpen = false
                    onClose()
                }
                ArcherMenuRow(title: "Close Other Tabs") {
                    isContextMenuOpen = false
                    onCloseOthers()
                }
                ArcherMenuRow(title: "Close Tabs to the Right", isDisabled: !canCloseToRight) {
                    isContextMenuOpen = false
                    onCloseToRight()
                }
                ArcherMenuDivider()
                ArcherMenuRow(title: "Split Right", shortcut: "⌘D") {
                    isContextMenuOpen = false
                    onSplit(.horizontal)
                }
                ArcherMenuRow(title: "Split Down", shortcut: "⌘⇧D") {
                    isContextMenuOpen = false
                    onSplit(.vertical)
                }
                ArcherMenuRow(title: "Move to New Window") {
                    isContextMenuOpen = false
                    onMoveToNewWindow()
                }
                ArcherMenuDivider()
                ArcherMenuRow(title: "Rename Tab…", shortcut: "⌘R") {
                    isContextMenuOpen = false
                    beginRename(deferred: true)
                }
                ArcherMenuRow(title: "Duplicate Tab") {
                    isContextMenuOpen = false
                    onDuplicate()
                }
                ArcherMenuDivider()
                ArcherMenuRow(title: "Reveal in Finder") {
                    isContextMenuOpen = false
                    NSWorkspace.shared.activateFileViewerSelecting([tab.currentDirectory])
                }
            }
            .padding(Theme.space1)
            .frame(minWidth: 240)
            .background(Theme.chromeBackground)
        }
        .popover(isPresented: $isRenameOpen, arrowEdge: .bottom) {
            ArcherRenameField(placeholder: "Tab title", text: $pendingRename) {
                onRename(pendingRename)
                isRenameOpen = false
            }
        }
        .onChange(of: tab.renameRequested) { _, requested in
            // ⌘R routes here via `Session.renameRequested`. Consume the flag
            // so the next ⌘R re-fires.
            guard requested else { return }
            tab.renameRequested = false
            beginRename(deferred: false)
        }
    }

    /// Seed the edit field from the current title and open the rename popover.
    /// `deferred` waits one runloop tick — needed from the context menu, where
    /// that popover is mid-dismiss and back-to-back popovers off the same
    /// anchor glitch; the ⌘R path opens synchronously. Skips when already open
    /// so a re-trigger mid-edit can't wipe what the user is typing.
    private func beginRename(deferred: Bool) {
        guard !isRenameOpen else { return }
        pendingRename = tab.customTitle ?? tab.title
        if deferred {
            DispatchQueue.main.async { isRenameOpen = true }
        } else {
            isRenameOpen = true
        }
    }

    private var rowBackground: Color {
        if isActive { return Theme.chromeActive }
        if isHovered { return Theme.chromeHover }
        return .clear
    }

    /// Live PaneRegistry label when synced; falls back to template id.
    private var bridgeLabel: String {
        PaneRegistry.shared.label(for: tab) ?? tab.displayAgent.id
    }

    /// Shows only on non-zero exit. Successful runs intentionally leave the
    /// row clean — a green dot on every command would dominate the chrome.
    @ViewBuilder
    private var commandStatusDot: some View {
        if let exit = tab.lastCommandExit, exit != 0 {
            Circle()
                .fill(Theme.activityFailure)
                .frame(width: 5, height: 5)
                .help(Self.statusTooltip(exit: exit, duration: tab.lastCommandDuration))
        }
    }

    private static func statusTooltip(exit: Int, duration: TimeInterval?) -> String {
        guard let duration else { return "exit \(exit)" }
        return "exit \(exit) · \(formatDuration(duration))"
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "\(Int((seconds * 1000).rounded()))ms" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds / 60)
        let rem = Int(seconds.truncatingRemainder(dividingBy: 60).rounded())
        return "\(minutes)m \(rem)s"
    }
}

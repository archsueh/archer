import AppKit
import SwiftUI

/// Top-chrome "Open in <app>" split control, modelled on codex's. The left
/// zone shows the last-used (or first available) app's icon — clicking it
/// opens the active tab's cwd in that app. The right zone is a chevron that
/// opens the full picker. State (order / hidden / last-used) lives in
/// `ArcherSettingsModel`; the directory comes from the active session.
struct OpenInButton: View {
    @Bindable var store: WorkspaceStore
    private var model: ArcherSettingsModel {
        ArcherSettingsModel.shared
    }

    @State private var isMenuOpen = false
    @State private var iconHovered = false
    @State private var chevronHovered = false

    var body: some View {
        let visible = OpenInResolver.visibleApps(model: model)
        let primary = OpenInApp.effectiveDefault(lastUsedId: model.lastOpenInAppId, visible: visible)
        let dir = currentDirectory
        let canOpen = dir != nil && primary != nil

        HStack(spacing: 0) {
            Button {
                if let dir, let primary { choose(primary, dir: dir) }
            } label: {
                Group {
                    if let primary {
                        OpenInAppIcon(app: primary, size: 16)
                    } else {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .frame(width: 24, height: 26)
                .background(iconHovered ? Color.white.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .onHover { iconHovered = $0 }
            .help(primary.map { "Open in \($0.title)" } ?? "Open in…")

            Button {
                if !visible.isEmpty {
                    OpenInResolver.invalidate()
                    isMenuOpen.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 15, height: 26)
                    .background(chevronHovered ? Color.white.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(visible.isEmpty)
            .onHover { chevronHovered = $0 }
            .help("Open in…")
            .popover(isPresented: $isMenuOpen, arrowEdge: .bottom) {
                picker(visible: visible, dir: dir)
            }
        }
        .foregroundStyle(Theme.chromeForeground)
        // Dim only when no apps are installed at all (cwd-independent —
        // `primary != nil` already implies `!visible.isEmpty`).
        .opacity(visible.isEmpty ? 0.4 : 1)
    }

    /// `visible` is computed once in `body`; the chevron handler `invalidate()`s
    /// before opening, so that value is already the fresh post-invalidate list —
    /// no need to recompute it here.
    private func picker(visible: [OpenInApp], dir: URL?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if visible.isEmpty {
                Text("No supported apps found")
                    .font(Theme.display(12.5, weight: .regular))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.horizontal, Theme.space2 + 2)
                    .padding(.vertical, 8)
            } else {
                ForEach(visible) { app in
                    ArcherMenuRow(title: app.title) {
                        OpenInAppIcon(app: app, size: 16)
                    } action: {
                        isMenuOpen = false
                        if let dir { choose(app, dir: dir) }
                    }
                }
            }
        }
        .padding(Theme.space1)
        .frame(minWidth: 220)
        .background(Theme.chromeBackground)
    }

    /// Remember the app (so the split button's icon + plain-click target track
    /// the user's last choice) and open the directory in it. Saves imperatively
    /// rather than through the Settings `.onChange` autosave chain, because that
    /// chain is only mounted while the Settings window is open — this fires from
    /// the top-chrome button with Settings closed.
    private func choose(_ app: OpenInApp, dir: URL) {
        if model.lastOpenInAppId != app.id {
            model.lastOpenInAppId = app.id
            model.scheduleSave()
        }
        OpenInResolver.open(directory: dir, with: app)
    }

    private var currentDirectory: URL? {
        let url = store.active?.activeSession?.currentDirectory ?? store.active?.workingDirectory
        return url?.standardizedFileURL
    }
}

/// Renders an `OpenInApp`'s real macOS icon (falls back to a generic app
/// glyph if the app went missing between resolution and render).
struct OpenInAppIcon: View {
    let app: OpenInApp
    let size: CGFloat

    var body: some View {
        if let icon = OpenInResolver.icon(for: app) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(Theme.chromeMuted)
        }
    }
}

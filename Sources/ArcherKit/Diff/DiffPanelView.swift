import SwiftUI

/// Right-side Git Diff panel: visualizes uncommitted changes in the active workspace.
/// Fits a 280px-wide sidebar using a stacked List -> Detail navigation pattern.
public struct DiffPanelView: View {
    @StateObject private var model: DiffModel
    @State private var showingDetail = false
    let rootURL: URL
    var width: Double

    public init(rootURL: URL, width: Double = 280) {
        self.rootURL = rootURL
        self.width = width
        _model = StateObject(wrappedValue: DiffModel(rootURL: rootURL))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            
            Group {
                if model.isLoading && model.modifiedFiles.isEmpty {
                    loadingView
                } else if model.modifiedFiles.isEmpty {
                    emptyView
                } else if showingDetail, let selected = model.selectedFile {
                    diffDetailView(for: selected)
                } else {
                    fileListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: CGFloat(width))
        .background(Theme.chromeBackground)
        .onDisappear {
            model.teardown()
        }
    }

    // MARK: - Views

    private var header: some View {
        HStack(spacing: 6) {
            if showingDetail {
                HoverableIconButton(systemName: "chevron.left", fontSize: 11, size: 24, help: "Back to list") {
                    withAnimation(Theme.chromeTransition) {
                        showingDetail = false
                    }
                }
            }
            
            Text(showingDetail ? "DIFF" : "CHANGES")
                .font(Theme.display(12, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
            
            Spacer()
            
            if !showingDetail {
                Text("\(model.modifiedFiles.count) files")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
            }
            
            HoverableIconButton(systemName: "arrow.clockwise", fontSize: 11, size: 24, help: "Refresh") {
                model.refresh()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.chromeMuted)
            Text("No uncommitted changes")
                .font(Theme.display(11))
                .foregroundStyle(Theme.chromeMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(model.modifiedFiles) { file in
                    FileListRow(file: file, isSelected: model.selectedFile?.url == file.url) {
                        model.select(file)
                        withAnimation(Theme.chromeTransition) {
                            showingDetail = true
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func diffDetailView(for file: ModifiedFile) -> some View {
        VStack(spacing: 0) {
            // File header strip
            HStack {
                Text(file.url.lastPathComponent)
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                Spacer()
                statusBadge(file.status)
            }
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, 6)
            .background(Theme.chromeHairline.opacity(0.3))
            
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            
            if model.activeDiffLines.isEmpty {
                VStack {
                    Spacer()
                    Text("No diff content")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeMuted)
                    Spacer()
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.activeDiffLines) { line in
                            DiffLineRow(line: line)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func statusBadge(_ status: GitFileStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .added:
            text = "ADDED"
            color = Theme.gitInsertion
        case .deleted:
            text = "DELETED"
            color = Theme.gitDeletion
        case .modified:
            text = "MODIFIED"
            color = Theme.activityAttention
        }
        return Text(text)
            .font(Theme.mono(8.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .bracketBorder()
    }
}

// MARK: - Row Components

private struct FileListRow: View {
    let file: ModifiedFile
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator(file.status)
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                Text(file.url.deletingLastPathComponent().lastPathComponent)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeMuted)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 6)
        .background(isSelected ? Theme.chromeActive : (hovered ? Theme.chromeHover : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { action() }
    }

    private func statusIndicator(_ status: GitFileStatus) -> some View {
        let symbol: String
        let color: Color
        switch status {
        case .added:
            symbol = "plus.circle.fill"
            color = Theme.gitInsertion
        case .deleted:
            symbol = "minus.circle.fill"
            color = Theme.gitDeletion
        case .modified:
            symbol = "pencil.circle.fill"
            color = Theme.activityAttention
        }
        return Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(color)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 8) {
            // Line counters
            HStack(spacing: 4) {
                Text(line.oldLineNum.map(String.init) ?? "")
                    .frame(width: 20, alignment: .trailing)
                Text(line.newLineNum.map(String.init) ?? "")
                    .frame(width: 20, alignment: .trailing)
            }
            .font(Theme.mono(8.5))
            .foregroundStyle(Theme.chromeMuted.opacity(0.5))
            
            // Code Content
            Text(line.content)
                .font(Theme.mono(10))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(backgroundColor)
    }

    private var textColor: Color {
        switch line.type {
        case .added: return Theme.gitInsertion
        case .deleted: return Theme.gitDeletion
        case .header: return Theme.chromeMuted
        case .context: return Theme.chromeForeground.opacity(0.85)
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return Theme.gitInsertion.opacity(0.08)
        case .deleted: return Theme.gitDeletion.opacity(0.08)
        case .header: return Theme.chromeHairline.opacity(0.15)
        case .context: return Color.clear
        }
    }
}

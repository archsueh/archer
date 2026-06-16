import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - File tree item

struct FileTreeItem: Identifiable, Equatable {
    let id: URL
    let url: URL
    let isDirectory: Bool
    var children: [FileTreeItem] = []

    static func == (lhs: FileTreeItem, rhs: FileTreeItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Root file tree list (replaces workspace rows when active)

struct SidebarFileTreeList: View {
    let rootURL: URL
    let onOpenInFinder: (URL) -> Void

    var body: some View {
        ScrollViewReader { _ in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    FileTreeRow(
                        item: FileTreeItem(id: rootURL, url: rootURL, isDirectory: true),
                        depth: 0,
                        onOpenInFinder: onOpenInFinder
                    )
                }
                .padding(.horizontal, Theme.space2)
                .padding(.vertical, Theme.space2)
            }
        }
    }
}

// MARK: - File tree row (recursive)

struct FileTreeRow: View {
    let item: FileTreeItem
    let depth: Int
    let onOpenInFinder: (URL) -> Void

    @State private var isExpanded: Bool
    @State private var children: [FileTreeItem] = []

    init(item: FileTreeItem, depth: Int, onOpenInFinder: @escaping (URL) -> Void) {
        self.item = item
        self.depth = depth
        self.onOpenInFinder = onOpenInFinder
        _isExpanded = State(initialValue: depth == 0) // root auto-expand
    }

    private var indent: CGFloat {
        Theme.space2 + CGFloat(depth) * Theme.space3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.space2) {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.chromeForeground.opacity(item.isDirectory ? 0.92 : 0.68))
                    .frame(width: 16, height: 16)

                Text(item.url.lastPathComponent)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeForeground.opacity(item.isDirectory ? 0.92 : 0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if item.isDirectory {
                    HoverableIconButton(
                        systemName: "arrow.up.right.square",
                        fontSize: 10,
                        size: 18,
                        help: "Open in Finder"
                    ) {
                        onOpenInFinder(item.url)
                    }
                    .opacity(0.65)
                }
            }
            .padding(.leading, indent)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                pastePathToActivePane(item.url.path)
            }

            // Children loaded on-demand after first expand
            Group {
                if isExpanded && !children.isEmpty {
                    disclosureHints()
                    ForEach(children) { child in
                        FileTreeRow(
                            item: child,
                            depth: depth + 1,
                            onOpenInFinder: onOpenInFinder
                        )
                    }
                }
            }
        }
        // Load children lazily
        .task(id: "load-\(item.id.path)") {
            if item.isDirectory && children.isEmpty {
                loadChildren()
            }
        }
    }

    // MARK: - Helpers

    private func loadChildren() {
        let fm = FileManager.default
        guard isDirectory(item.url),
              let urls = try? fm.contentsOfDirectory(
                  at: item.url,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return }

        let sorted = urls.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir && !bIsDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }

        children = sorted.map { url -> FileTreeItem in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileTreeItem(id: url, url: url, isDirectory: isDir)
        }

        withAnimation(.easeOut(duration: 0.12)) {
            isExpanded = true
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func disclosureHints() -> some View {
        // Lightweight section verbose hint — matches SidebarWorkspaceRow's
        // rowFill so collapsed state still "breathes" even without content.
        EmptyView()
    }

    private func pastePathToActivePane(_ fullPath: String) {
        // Pipeline: path → pasteboard → Ghostty bracketed-paste path.
        // Ghostty handles bracketed paste natively; no raw write to shell
        // avoids breaking the line when the target is deep in an agent run.
        let escaped = fullPath.replacingOccurrences(of: " ", with: "\\ ")
        guard let data = "\(escaped)\n".data(using: .utf8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .string)
        // UX note: focus remains on the file pane so the user can keep
        // browsing. Paste is invoked through archer's ghostty surface when
        // they click back into that pane — we do NOT synthesize Cmd+V here.
    }
}

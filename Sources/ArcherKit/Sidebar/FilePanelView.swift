import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FilePanelLayout: String, Codable { case tree, grid }

/// Right-side file panel: a live mirror of the active workspace's directory.
/// Tree view or icon grid (with up/breadcrumb nav); drag a row onto a folder to
/// move it on disk; a kqueue watcher keeps it aligned with external changes.
struct FilePanelView: View {
    @StateObject private var model: FileTreeModel
    @AppStorage("filePanelLayout") private var layout: FilePanelLayout = .tree
    @State private var currentDir: URL
    @State private var watcher: DirectoryWatcher?
    /// [archer] kqueue on .git/HEAD+index so badges refresh after agent commits/stages.
    @State private var gitWatcher: GitWatcher?
    let rootURL: URL
    var width: Double

    init(rootURL: URL, width: Double = 280) {
        self.rootURL = rootURL
        self.width = width
        _model = StateObject(wrappedValue: FileTreeModel(rootURL: rootURL))
        _currentDir = State(initialValue: rootURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            Group {
                if layout == .tree { treeBody } else { gridBody }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: CGFloat(width))
        .background(Theme.chromeBackground)
        .onAppear {
            let w = DirectoryWatcher { dir in
                model.refresh(dir)
                model.refreshGitStatus()
            }
            watcher = w
            let gw = GitWatcher { model.refreshGitStatus() }
            gw.watch(cwd: rootURL)
            gitWatcher = gw
            enter(rootURL)
            model.refreshGitStatus()
        }
        .onDisappear {
            watcher?.cancel()
            gitWatcher?.cancel()
        }
        .onChange(of: currentDir) { _, dir in enter(dir) }
        .onChange(of: rootURL) { _, newRoot in
            // Workspace switched: re-home watchers + status map.
            gitWatcher?.cancel()
            let gw = GitWatcher { model.refreshGitStatus() }
            gw.watch(cwd: newRoot)
            gitWatcher = gw
            model.refreshGitStatus()
        }
    }

    /// Track + watch a directory so both views stay aligned with disk.
    private func enter(_ dir: URL) {
        model.expand(dir)
        watcher?.add(dir)
    }

    /// Move source (or all selected items if source is in the selection) into dest.
    private func move(_ source: URL, into dest: URL) {
        let targets = model.selection.contains(source) ? Array(model.selection) : [source]
        for url in targets {
            _ = try? model.move(url, into: dest)
        }
        model.clearSelection()
        model.refreshGitStatus()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            HoverableIconButton(systemName: "chevron.up", fontSize: 11, size: 24, help: "Up") {
                if currentDir.standardizedFileURL != rootURL.standardizedFileURL {
                    currentDir = currentDir.deletingLastPathComponent()
                }
            }
            breadcrumb
            Spacer(minLength: 0)
            HoverableIconButton(
                systemName: layout == .tree ? "square.grid.2x2" : "list.bullet",
                fontSize: 11, size: 24, help: "Toggle view"
            ) {
                layout = layout == .tree ? .grid : .tree
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var breadcrumb: some View {
        let comps = pathChain()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(comps.enumerated()), id: \.offset) { idx, url in
                    Button(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent) {
                        currentDir = url
                        if layout == .tree { layout = .grid }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11, weight: idx == comps.count - 1 ? .medium : .regular))
                    .foregroundStyle(idx == comps.count - 1 ? Theme.chromeForeground : Theme.chromeMuted)
                    .lineLimit(1)
                    if idx < comps.count - 1 {
                        Text("›").font(Theme.mono(10)).foregroundStyle(Theme.chromeMuted.opacity(0.6))
                    }
                }
            }
        }
    }

    private func pathChain() -> [URL] {
        var chain: [URL] = []
        var u = currentDir.standardizedFileURL
        let root = rootURL.standardizedFileURL
        while u.path.count >= root.path.count {
            chain.insert(u, at: 0)
            if u == root { break }
            let parent = u.deletingLastPathComponent()
            if parent == u { break }
            u = parent
        }
        return chain.isEmpty ? [root] : chain
    }

    // MARK: Tree

    private var treeBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.childrenByDir[rootURL.standardizedFileURL] ?? [], id: \.id) { item in
                    FileTreeNodeView(model: model, item: item, depth: 0, onMove: move)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Grid

    private var gridBody: some View {
        let items = model.childrenByDir[currentDir.standardizedFileURL] ?? []
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 10) {
                ForEach(items, id: \.id) { item in
                    FileGridCell(
                        item: item,
                        isSelected: model.selection.contains(item.url),
                        gitStatus: model.gitStatus(for: item.url),
                        onOpen: {
                            if item.isDirectory { currentDir = item.url }
                            else { pasteFilePath(item.url.path) }
                        },
                        onMove: move,
                        onSelect: { extend in
                            if extend { model.toggleSelect(item.url) }
                            else { model.setSelection(item.url) }
                        },
                        onDuplicate: {
                            _ = try? model.duplicate(item.url)
                            model.refreshGitStatus()
                        }
                    )
                }
            }
            .padding(10)
        }
    }
}

// MARK: - Git status badge (file-tree / grid)

/// Compact M/A/D letter badge — reuses Diff panel token colors, no new hues.
struct FileGitStatusBadge: View {
    let status: GitFileStatus
    var compact: Bool = true

    var body: some View {
        Text(label)
            .font(Theme.mono(compact ? 9 : 10, weight: .bold))
            .foregroundStyle(color)
            .help(help)
    }

    private var label: String {
        switch status {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        }
    }

    private var color: Color {
        switch status {
        case .modified: return Theme.activityAttention
        case .added: return Theme.gitInsertion
        case .deleted: return Theme.gitDeletion
        }
    }

    private var help: String {
        switch status {
        case .modified: return "Modified"
        case .added: return "Added / untracked"
        case .deleted: return "Deleted"
        }
    }
}

// MARK: - Recursive tree row

private struct FileTreeNodeView: View {
    @ObservedObject var model: FileTreeModel
    let item: FileTreeItem
    let depth: Int
    let onMove: (URL, URL) -> Void
    @State private var hovered = false
    @State private var targeted = false

    private var key: URL {
        item.url.standardizedFileURL
    }

    private var isExpanded: Bool {
        model.expanded.contains(key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if item.isDirectory && isExpanded {
                ForEach(model.childrenByDir[key] ?? [], id: \.id) { child in
                    FileTreeNodeView(model: model, item: child, depth: depth + 1, onMove: onMove)
                }
            }
        }
    }

    private var isSelected: Bool {
        model.selection.contains(item.url)
    }

    private var row: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isDirectory ? (isExpanded ? "folder.fill" : "folder") : iconName(item.url))
                .font(.system(size: 11))
                .foregroundStyle(item.isDirectory ? Theme.chromeForeground.opacity(0.85) : Theme.chromeMuted)
                .frame(width: 14)
            Text(item.url.lastPathComponent)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeForeground.opacity(item.isDirectory ? 0.9 : 0.72))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if let status = model.gitStatus(for: item.url) {
                FileGitStatusBadge(status: status, compact: true)
            }
            if isSelected && model.selection.count > 1 {
                Text("\(model.selection.count)")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.trailing, 4)
            }
        }
        .padding(.leading, CGFloat(depth) * 12 + 8)
        .padding(.vertical, 4).padding(.trailing, 8)
        .background(
            targeted ? Theme.chromeHover
                : isSelected ? Theme.chromeHover.opacity(0.75)
                : hovered ? Theme.chromeHover.opacity(0.5)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                model.toggleSelect(item.url)
            } else {
                model.setSelection(item.url)
                if item.isDirectory {
                    isExpanded ? model.collapse(item.url) : model.expand(item.url)
                } else {
                    pasteFilePath(item.url.path)
                }
            }
        }
        .contextMenu {
            if !item.isDirectory {
                Button("Duplicate") { _ = try? model.duplicate(item.url) }
                Divider()
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .modifier(FolderDrop(isDir: item.isDirectory, dest: item.url, targeted: $targeted, onMove: onMove))
    }
}

// MARK: - Grid cell

private struct FileGridCell: View {
    let item: FileTreeItem
    let isSelected: Bool
    /// Optional git badge for the cell (passed from parent so grid stays pure).
    var gitStatus: GitFileStatus? = nil
    let onOpen: () -> Void
    let onMove: (URL, URL) -> Void
    let onSelect: (_ extend: Bool) -> Void
    let onDuplicate: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.isDirectory ? "folder.fill" : iconName(item.url))
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(item.isDirectory ? Theme.chromeForeground.opacity(0.8) : Theme.chromeMuted)
                    .frame(height: 30)
                if let gitStatus {
                    FileGitStatusBadge(status: gitStatus, compact: true)
                        .offset(x: 6, y: -2)
                }
            }
            Text(item.url.lastPathComponent)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeForeground.opacity(0.8))
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(width: 74, height: 66)
        .padding(4)
        .background(
            targeted ? Theme.chromeHover
                : isSelected ? Theme.chromeHover.opacity(0.75)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            let extend = NSEvent.modifierFlags.contains(.command)
            onSelect(extend)
            if !extend { onOpen() }
        }
        .contextMenu {
            if !item.isDirectory {
                Button("Duplicate") { onDuplicate() }
                Divider()
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .modifier(FolderDrop(isDir: item.isDirectory, dest: item.url, targeted: $targeted, onMove: onMove))
    }
}

// MARK: - Drop only onto folders

private struct FolderDrop: ViewModifier {
    let isDir: Bool
    let dest: URL
    @Binding var targeted: Bool
    let onMove: (URL, URL) -> Void

    func body(content: Content) -> some View {
        if isDir {
            content.onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                loadURLs(providers) { urls in for u in urls {
                    onMove(u, dest)
                } }
                return true
            }
        } else {
            content
        }
    }
}

// MARK: - Helpers

private func iconName(_ url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "swift": return "swift"
    case "md", "txt", "rtf": return "doc.text"
    case "json", "yml", "yaml", "toml", "plist": return "curlybraces"
    case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
    case "sh", "zsh", "bash": return "terminal"
    default: return "doc"
    }
}

private func loadURLs(_ providers: [NSItemProvider], _ completion: @escaping ([URL]) -> Void) {
    final class URLCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func append(_ url: URL) {
            lock.withLock { urls.append(url) }
        }

        var result: [URL] {
            lock.withLock { urls }
        }
    }
    let collector = URLCollector()
    let group = DispatchGroup()
    for p in providers {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { collector.append(url) }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(collector.result) }
}

/// Drop the file's escaped path on the pasteboard so it can be pasted into the
/// active terminal pane (matches the original SidebarFileTree behavior).
private func pasteFilePath(_ path: String) {
    let escaped = path.replacingOccurrences(of: " ", with: "\\ ")
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(escaped + "\n", forType: .string)
}

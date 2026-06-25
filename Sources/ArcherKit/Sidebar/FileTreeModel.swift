import Combine
import Foundation

/// SSOT for the file-tree panel. Replaces the per-row `@State` children cache in
/// `SidebarFileTree`: a single owner lets a move update both the source and the
/// destination directory at once, and lets the external-change watcher push
/// refreshes — neither is possible when each row caches its own children in
/// isolation (the old WIP went stale the moment anything changed on disk).
final class FileTreeModel: ObservableObject {
    let rootURL: URL

    /// Children per directory, kept only for dirs the tree has loaded.
    @Published private(set) var childrenByDir: [URL: [FileTreeItem]] = [:]
    /// Directories currently expanded in the UI.
    @Published var expanded: Set<URL> = []
    /// Currently selected items (cmd-click to multi-select).
    @Published var selection: Set<URL> = []

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func setSelection(_ url: URL) {
        selection = [url]
    }

    func toggleSelect(_ url: URL) {
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
    }

    func clearSelection() {
        selection = []
    }

    /// Copy `source` in-place with a collision-free name, then refresh the parent dir.
    @discardableResult
    func duplicate(_ source: URL) throws -> URL {
        let dest = collisionFreeURL(for: source.lastPathComponent, in: source.deletingLastPathComponent())
        try FileManager.default.copyItem(at: source, to: dest)
        refresh(source.deletingLastPathComponent())
        return dest
    }

    /// Directory listing: directories first, then files, each localized-standard
    /// sorted ("file2" before "file10"). Hidden files skipped.
    func children(of dir: URL) -> [FileTreeItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return urls
            .map { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileTreeItem(id: url, url: url, isDirectory: isDir)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                return a.url.lastPathComponent
                    .localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
            }
    }

    /// Move `source` into `destDir`, renaming on name collision instead of
    /// overwriting. No-op when `source` already lives in `destDir`. Returns the
    /// final URL and refreshes both affected directories so the tree stays
    /// aligned with disk.
    @discardableResult
    func move(_ source: URL, into destDir: URL) throws -> URL {
        if source.deletingLastPathComponent().standardizedFileURL == destDir.standardizedFileURL {
            return source
        }
        let dest = collisionFreeURL(for: source.lastPathComponent, in: destDir)
        try FileManager.default.moveItem(at: source, to: dest)
        refresh(source.deletingLastPathComponent())
        refresh(destDir)
        return dest
    }

    /// Expand a directory: remember it and load its children.
    func expand(_ dir: URL) {
        let key = dir.standardizedFileURL
        expanded.insert(key)
        childrenByDir[key] = children(of: key)
    }

    /// Collapse a directory (keeps its cached children; cheap to re-show).
    func collapse(_ dir: URL) {
        expanded.remove(dir.standardizedFileURL)
    }

    /// Re-read a directory's children if the tree is showing it. Called after a
    /// move and by the external-change watcher → this is the "alignment" seam.
    func refresh(_ dir: URL) {
        let key = dir.standardizedFileURL
        guard key == rootURL.standardizedFileURL || expanded.contains(key)
            || childrenByDir[key] != nil else { return }
        childrenByDir[key] = children(of: key)
    }

    /// `x.txt` → `x 2.txt` → `x 3.txt`; extension-less `sub` → `sub 2`.
    private func collisionFreeURL(for name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        let first = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: first.path) else { return first }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var n = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}

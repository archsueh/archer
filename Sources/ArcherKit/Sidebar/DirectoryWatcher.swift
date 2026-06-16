import Darwin
import Foundation

/// kqueue watcher on directory fds — fires `onChange(dir)` (debounced) when a
/// watched directory's contents change externally. The tree's read-alignment seam.
@MainActor
final class DirectoryWatcher {
    private var watches: [URL: DispatchSourceFileSystemObject] = [:]
    private var pending: [URL: DispatchWorkItem] = [:]
    private let onChange: (URL) -> Void

    init(onChange: @escaping (URL) -> Void) {
        self.onChange = onChange
    }

    /// Start watching `dir` (idempotent). Call when a directory is expanded.
    func add(_ dir: URL) {
        let key = dir.standardizedFileURL
        guard watches[key] == nil else { return }
        let fd = open(key.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.schedule(key) }
        src.setCancelHandler { close(fd) }
        src.resume()
        watches[key] = src
    }

    /// Stop watching `dir` (call when a directory is collapsed).
    func remove(_ dir: URL) {
        let key = dir.standardizedFileURL
        watches[key]?.cancel()
        watches[key] = nil
        pending[key]?.cancel()
        pending[key] = nil
    }

    /// Tear down every watch. MUST be called before dropping the watcher — a
    /// `@MainActor` deinit runs nonisolated in Swift 6 and kqueue fds leak.
    func cancel() {
        for src in watches.values { src.cancel() }
        watches.removeAll()
        for work in pending.values { work.cancel() }
        pending.removeAll()
    }

    // Coalesce bursts (a multi-file copy fires many NOTE_WRITEs) into one refresh.
    private func schedule(_ dir: URL) {
        pending[dir]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending[dir] = nil
            self?.onChange(dir)
        }
        pending[dir] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}

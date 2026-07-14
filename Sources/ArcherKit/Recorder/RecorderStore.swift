// [archer] Recorder output directory + listing. Recordings live in
// ~/.archer/recordings/ and are per-session `.termctrl` JSON Lines files.

import Foundation

enum RecorderStore {
    /// Default recordings root: `~/.archer/recordings/`.
    static var defaultDirectory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(".archer/recordings", isDirectory: true)
    }

    /// All recorded `.termctrl` files, newest first.
    static func listRecordings() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: defaultDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "termctrl" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    /// Loads a `.termctrl` file into its raw lines (strings). Used by tools /
    /// tests; the export step hands the file path to `termctrl video` directly.
    static func readLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

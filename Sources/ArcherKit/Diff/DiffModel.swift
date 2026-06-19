import Combine
import Foundation

/// Git change status types for individual files.
public enum GitFileStatus: String, Sendable, Codable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
}

/// A parsed line of a git diff output.
public enum DiffLineType: String, Sendable, Codable {
    case added // starts with "+"
    case deleted // starts with "-"
    case context // starts with " " or empty
    case header // starts with "diff", "index", "---", "+++", or "@@"
}

public struct DiffLine: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let type: DiffLineType
    public let content: String
    public let oldLineNum: Int?
    public let newLineNum: Int?

    public init(type: DiffLineType, content: String, oldLineNum: Int?, newLineNum: Int?) {
        self.type = type
        self.content = content
        self.oldLineNum = oldLineNum
        self.newLineNum = newLineNum
    }
}

public struct ModifiedFile: Identifiable, Sendable, Hashable {
    public var id: URL {
        url
    }

    public let url: URL
    public let status: GitFileStatus

    public init(url: URL, status: GitFileStatus) {
        self.url = url
        self.status = status
    }
}

/// Stateful parser for unified git diff output.
public enum DiffParser {
    public static func parse(_ raw: String) -> [DiffLine] {
        guard !raw.isEmpty else { return [] }
        var lines: [DiffLine] = []
        let inputLines = raw.split(separator: "\n", omittingEmptySubsequences: false)

        var oldLineCounter: Int? = nil
        var newLineCounter: Int? = nil

        for line in inputLines {
            let str = String(line)
            if str.hasPrefix("diff --git") || str.hasPrefix("index ") || str.hasPrefix("--- ") || str.hasPrefix("+++ ") {
                lines.append(DiffLine(type: .header, content: str, oldLineNum: nil, newLineNum: nil))
            } else if str.hasPrefix("@@") {
                // Parse @@ -26,3 +26,10 @@
                let parts = str.split(separator: " ")
                if parts.count >= 3 {
                    let oldPart = parts[1].replacingOccurrences(of: "-", with: "")
                    let oldRange = oldPart.split(separator: ",")
                    if let first = oldRange.first.flatMap({ Int($0) }) {
                        oldLineCounter = first
                    }

                    let newPart = parts[2].replacingOccurrences(of: "+", with: "")
                    let newRange = newPart.split(separator: ",")
                    if let first = newRange.first.flatMap({ Int($0) }) {
                        newLineCounter = first
                    }
                }
                lines.append(DiffLine(type: .header, content: str, oldLineNum: nil, newLineNum: nil))
            } else if str.hasPrefix("+") {
                lines.append(DiffLine(type: .added, content: str, oldLineNum: nil, newLineNum: newLineCounter))
                if let val = newLineCounter {
                    newLineCounter = val + 1
                }
            } else if str.hasPrefix("-") {
                lines.append(DiffLine(type: .deleted, content: str, oldLineNum: oldLineCounter, newLineNum: nil))
                if let val = oldLineCounter {
                    oldLineCounter = val + 1
                }
            } else {
                lines.append(DiffLine(type: .context, content: str, oldLineNum: oldLineCounter, newLineNum: newLineCounter))
                if let oVal = oldLineCounter {
                    oldLineCounter = oVal + 1
                }
                if let nVal = newLineCounter {
                    newLineCounter = nVal + 1
                }
            }
        }
        return lines
    }
}

/// SSOT model for the Diff panel.
@MainActor
public final class DiffModel: ObservableObject {
    public let rootURL: URL
    @Published public private(set) var modifiedFiles: [ModifiedFile] = []
    @Published public var selectedFile: ModifiedFile?
    @Published public private(set) var activeDiffLines: [DiffLine] = []
    @Published public private(set) var isLoading = false

    private var gitWatcher: GitWatcher?

    public init(rootURL: URL) {
        self.rootURL = rootURL
        gitWatcher = GitWatcher { [weak self] in
            self?.refresh()
        }
        gitWatcher?.watch(cwd: rootURL)
        refresh()
    }

    public func teardown() {
        gitWatcher?.cancel()
        gitWatcher = nil
    }

    public func refresh() {
        isLoading = true
        let path = rootURL.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = Self.fetchModifiedFiles(cwd: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.modifiedFiles = files
                self.isLoading = false

                // Keep selected file if it's still modified, or select first available
                if let selected = self.selectedFile, !files.contains(where: { $0.url == selected.url }) {
                    self.selectedFile = nil
                    self.activeDiffLines = []
                } else if self.selectedFile == nil, let first = files.first {
                    self.select(first)
                } else if let selected = self.selectedFile {
                    self.select(selected)
                }
            }
        }
    }

    public func select(_ file: ModifiedFile) {
        selectedFile = file
        let rootPath = rootURL.path
        let fileRelPath = file.url.path.replacingOccurrences(of: rootURL.path + "/", with: "")

        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rawDiff = Self.fetchDiff(cwd: rootPath, fileRelPath: fileRelPath)
            let parsedLines = DiffParser.parse(rawDiff)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.selectedFile?.url == file.url {
                    self.activeDiffLines = parsedLines
                }
                self.isLoading = false
            }
        }
    }

    private nonisolated static func fetchModifiedFiles(cwd: String) -> [ModifiedFile] {
        guard let output = GitStatusFetcher.runGit(["-C", cwd, "--no-optional-locks", "status", "--porcelain", "-z"]) else {
            return []
        }
        var files: [ModifiedFile] = []
        // Split by null characters
        let parts = output.components(separatedBy: "\0")
        for part in parts {
            let line = part.trimmingCharacters(in: .whitespaces)
            guard line.count > 3 else { continue }

            let xCode = line[line.startIndex]
            let yCode = line[line.index(after: line.startIndex)]

            // Extract the path (index offset 3 onwards)
            let relativePath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !relativePath.isEmpty else { continue }

            let url = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL

            let status: GitFileStatus
            if xCode == "A" || xCode == "?" || yCode == "?" || yCode == "A" {
                status = .added
            } else if xCode == "D" || yCode == "D" {
                status = .deleted
            } else {
                status = .modified
            }
            files.append(ModifiedFile(url: url, status: status))
        }
        return files.sorted { a, b in
            a.url.path.localizedStandardCompare(b.url.path) == .orderedAscending
        }
    }

    private nonisolated static func fetchDiff(cwd: String, fileRelPath: String) -> String {
        // Run git diff HEAD to show combined staged + unstaged changes
        let args = ["-C", cwd, "--no-optional-locks", "diff", "HEAD", "--no-color", "-U3", "--", fileRelPath]
        if let diff = GitStatusFetcher.runGit(args), !diff.isEmpty {
            return diff
        }

        // Fallback for newly added/untracked files
        let fullPath = URL(fileURLWithPath: fileRelPath, relativeTo: URL(fileURLWithPath: cwd)).path
        if FileManager.default.fileExists(atPath: fullPath) {
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                let contentLines = content.components(separatedBy: "\n")
                var lines = [
                    "diff --git a/\(fileRelPath) b/\(fileRelPath)",
                    "new file mode 100644",
                    "--- /dev/null",
                    "+++ b/\(fileRelPath)",
                    "@@ -0,0 +1,\(contentLines.count) @@",
                ]
                for line in contentLines {
                    lines.append("+" + line)
                }
                return lines.joined(separator: "\n")
            }
        }
        return ""
    }
}

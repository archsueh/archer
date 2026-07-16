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

/// One workspace in a source↔worktree family, fed into the Diff panel
/// overview (BACKLOG A.1②). Paths are disk roots (`Workspace.diskPath`).
public struct WorktreeDiffMember: Identifiable, Sendable, Hashable {
    public var id: URL {
        rootURL
    }

    public let rootURL: URL
    public let title: String
    public let branch: String?
    /// True when this member is the currently active workspace in the store.
    public let isActive: Bool

    public init(rootURL: URL, title: String, branch: String?, isActive: Bool = false) {
        self.rootURL = rootURL.standardizedFileURL
        self.title = title
        self.branch = branch
        self.isActive = isActive
    }
}

/// Aggregated dirty-file snapshot for one family member.
public struct WorktreeDiffSummary: Identifiable, Sendable, Hashable {
    public var id: URL {
        rootURL
    }

    public let rootURL: URL
    public let title: String
    public let branch: String?
    public let isActive: Bool
    public let files: [ModifiedFile]

    public var fileCount: Int {
        files.count
    }

    public var modifiedCount: Int {
        files.filter { $0.status == .modified }.count
    }

    public var addedCount: Int {
        files.filter { $0.status == .added }.count
    }

    public var deletedCount: Int {
        files.filter { $0.status == .deleted }.count
    }

    public init(
        rootURL: URL,
        title: String,
        branch: String?,
        isActive: Bool,
        files: [ModifiedFile]
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.title = title
        self.branch = branch
        self.isActive = isActive
        self.files = files
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
///
/// Single-root mode (default): same as historically — one `rootURL`.
/// Family mode (BACKLOG A.1②): `family` lists every source + satellite
/// worktree; `summaries` holds per-tree dirty counts; `focusedRootURL`
/// drives the file list + detail views.
@MainActor
public final class DiffModel: ObservableObject {
    /// Initial / default root (active workspace). May differ from
    /// `focusedRootURL` after the user picks another tree in the overview.
    public let rootURL: URL
    public let family: [WorktreeDiffMember]

    @Published public private(set) var summaries: [WorktreeDiffSummary] = []
    @Published public private(set) var focusedRootURL: URL
    @Published public private(set) var modifiedFiles: [ModifiedFile] = []
    @Published public var selectedFile: ModifiedFile?
    @Published public private(set) var activeDiffLines: [DiffLine] = []
    @Published public private(set) var isLoading = false

    private var gitWatcher: GitWatcher?

    /// True when the panel has more than one family member to overview.
    public var showsFamilyOverview: Bool {
        family.count > 1
    }

    public var totalDirtyFileCount: Int {
        summaries.reduce(0) { $0 + $1.fileCount }
    }

    public init(rootURL: URL, family: [WorktreeDiffMember] = []) {
        let standardized = rootURL.standardizedFileURL
        self.rootURL = standardized
        if family.isEmpty {
            self.family = [
                WorktreeDiffMember(
                    rootURL: standardized,
                    title: standardized.lastPathComponent,
                    branch: nil,
                    isActive: true
                ),
            ]
        } else {
            self.family = family.map {
                WorktreeDiffMember(
                    rootURL: $0.rootURL.standardizedFileURL,
                    title: $0.title,
                    branch: $0.branch,
                    isActive: $0.isActive
                )
            }
        }
        // Prefer the active member as the initial focus; fall back to rootURL.
        if let active = self.family.first(where: \.isActive) {
            focusedRootURL = active.rootURL
        } else {
            focusedRootURL = standardized
        }
        installWatcher(for: focusedRootURL)
        refresh()
    }

    public func teardown() {
        gitWatcher?.cancel()
        gitWatcher = nil
    }

    /// Switch the file list to another family member without leaving the panel.
    public func focus(rootURL: URL) {
        let next = rootURL.standardizedFileURL
        guard next != focusedRootURL else { return }
        focusedRootURL = next
        selectedFile = nil
        activeDiffLines = []
        installWatcher(for: next)
        applyFocusedFiles()
    }

    public func refresh() {
        isLoading = true
        let members = family
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let built: [WorktreeDiffSummary] = members.map { member in
                let files = Self.fetchModifiedFiles(cwd: member.rootURL.path)
                return WorktreeDiffSummary(
                    rootURL: member.rootURL,
                    title: member.title,
                    branch: member.branch,
                    isActive: member.isActive,
                    files: files
                )
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.summaries = built
                self.isLoading = false
                self.applyFocusedFiles()
            }
        }
    }

    public func select(_ file: ModifiedFile) {
        selectedFile = file
        let rootPath = focusedRootURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let fileRelPath: String
        if file.url.path.hasPrefix(prefix) {
            fileRelPath = String(file.url.path.dropFirst(prefix.count))
        } else {
            fileRelPath = file.url.lastPathComponent
        }

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

    private func installWatcher(for cwd: URL) {
        gitWatcher?.cancel()
        gitWatcher = GitWatcher { [weak self] in
            self?.refresh()
        }
        gitWatcher?.watch(cwd: cwd)
    }

    private func applyFocusedFiles() {
        // Focused path vanished (worktree closed mid-session) — snap to first.
        if !summaries.contains(where: { $0.rootURL == focusedRootURL }),
           let first = summaries.first
        {
            focusedRootURL = first.rootURL
        }
        let resolved = summaries.first(where: { $0.rootURL == focusedRootURL })?.files ?? []
        modifiedFiles = resolved

        if let selected = selectedFile, !resolved.contains(where: { $0.url == selected.url }) {
            selectedFile = nil
            activeDiffLines = []
        } else if selectedFile == nil, let first = resolved.first {
            select(first)
        } else if let selected = selectedFile {
            select(selected)
        }
    }

    private nonisolated static func fetchModifiedFiles(cwd: String) -> [ModifiedFile] {
        // [archer] Shared with FileTree badges — see GitPorcelain.
        GitPorcelain.modifiedFiles(cwd: cwd)
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

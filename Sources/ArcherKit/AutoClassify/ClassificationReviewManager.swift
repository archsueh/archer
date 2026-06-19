import Foundation

/// A pending file classification move awaiting user approval.
public struct PendingMove: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let source: URL
    public let destination: URL
    public let rule: ClassifyRule

    public init(source: URL, destination: URL, rule: ClassifyRule) {
        self.source = source
        self.destination = destination
        self.rule = rule
    }
}

/// Memory Bank integration: writes Fanbox post metadata to Archer's memory bank.
/// Directory: ~/Library/Application Support/Archer/memory/claude/<branch>/
@MainActor
private struct MemoryBankWriter {
    static func recordFanboxPost(
        postId: String,
        title: String,
        files: [URL],
        destination: URL,
        classifierBranch: String
    ) {
        let fm = FileManager.default
        let memoryRoot = URL(fileURLWithPath: "~/Library/Application Support/Archer/memory/claude", isDirectory: true)
            .standardizedFileURL
        let branchDir = memoryRoot.appendingPathComponent(classifierBranch, isDirectory: true)

        do {
            try fm.createDirectory(at: branchDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safePostId = postId.replacingOccurrences(of: "/", with: "_")
        let fileName = "fanbox-\(safePostId)-\(timestamp).json"
        let fileURL = branchDir.appendingPathComponent(fileName)

        let metadata: [String: Any] = [
            "source": "fanbox",
            "postId": postId,
            "title": title,
            "downloadedAt": timestamp,
            "files": files.map { $0.lastPathComponent },
            "destination": destination.path,
            "classifierBranch": classifierBranch,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent fail - memory bank is best-effort
        }
    }
}

/// MainActor-isolated manager that holds files awaiting classification approval.
@MainActor
public final class ClassificationReviewManager: ObservableObject {
    public static let shared = ClassificationReviewManager()

    @Published public private(set) var pendingMoves: [PendingMove] = []

    private init() {}

    public func addPendingMove(source: URL, destination: URL, rule: ClassifyRule) {
        let move = PendingMove(source: source, destination: destination, rule: rule)
        // Avoid duplicate pending moves for the same source
        if !pendingMoves.contains(where: { $0.source.standardizedFileURL == source.standardizedFileURL }) {
            pendingMoves.append(move)
        }
    }

    public func approve(_ move: PendingMove, onFinished: @escaping () -> Void = {}) {
        let fm = FileManager.default
        do {
            let destDir = move.destination.deletingLastPathComponent()
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: move.destination.path) {
                try fm.removeItem(at: move.destination)
            }
            try fm.moveItem(at: move.source, to: move.destination)
        } catch {
            NSLog("[archer] Failed to execute classification move: \(error.localizedDescription)")
        }
        // Record to Memory Bank for discoverability in sidebar
        // Extract post ID from file name: fanbox-<postId>-<timestamp>.ext
        let postId = move.source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "fanbox-", with: "")
            .split(separator: "-").first.map(String.init) ?? move.source.lastPathComponent
        MemoryBankWriter.recordFanboxPost(
            postId: postId,
            title: move.source.deletingPathExtension().lastPathComponent,
            files: [move.destination],
            destination: move.destination,
            classifierBranch: move.rule.folder
        )
        pendingMoves.removeAll { $0.id == move.id }
        onFinished()
    }

    public func approveAll(onFinished: @escaping () -> Void = {}) {
        let moves = pendingMoves
        for move in moves {
            approve(move)
        }
        onFinished()
    }

    public func decline(_ move: PendingMove) {
        pendingMoves.removeAll { $0.id == move.id }
    }

    public func declineAll() {
        pendingMoves.removeAll()
    }
}

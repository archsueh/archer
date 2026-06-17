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

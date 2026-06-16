import Foundation

/// A lightweight serial execution queue for download tasks.
///
/// This is a minimal skeleton: in the real implementation it would be
/// backed by `URLSessionDownloadTask` and coordinate writes into
/// `<directory>/fanbox/<postId>/`.  For now it preserves API surface only.
public actor DownloadQueue {
    private let session: URLSession
    private var tasks: [UUID: Task<Void, Error>] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func enqueue(postIds: [String], to directory: URL) async -> [FanboxPost] {
        do {
            return try await Downloader.download(postIds: postIds, to: directory)
        } catch {
            // Swallow under skeleton; real implementation would propagate/retry.
            return []
        }
    }
}

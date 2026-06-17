import Foundation

/// Status of a download job.
public enum DownloadJobStatus: String, Sendable, Codable {
    case queued
    case downloading
    case completed
    case failed
}

/// A single download job.
public struct DownloadJob: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let postId: String
    public var title: String
    public var status: DownloadJobStatus
    public var filesCount: Int

    public init(postId: String, title: String, status: DownloadJobStatus, filesCount: Int = 0) {
        self.postId = postId
        self.title = title
        self.status = status
        self.filesCount = filesCount
    }
}

/// A MainActor-isolated queue manager that coordinates and reports download progress.
@MainActor
public final class DownloadQueueManager: ObservableObject {
    public static let shared = DownloadQueueManager()

    @Published public private(set) var activeJobs: [DownloadJob] = []

    private init() {}

    /// Enqueue post IDs for download into the target directory. Calls `onFinished` when
    /// the batch is done so the views can trigger a refresh.
    public func downloadPosts(postIds: [String], targetDir: URL, onFinished: @escaping () -> Void = {}) {
        for id in postIds {
            let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty else { continue }

            if let existingIndex = activeJobs.firstIndex(where: { $0.postId == trimmedId }) {
                let existing = activeJobs[existingIndex]
                if existing.status == .downloading || existing.status == .queued {
                    continue
                }
                activeJobs[existingIndex].status = .queued
                activeJobs[existingIndex].filesCount = 0
            } else {
                let job = DownloadJob(postId: trimmedId, title: "Post \(trimmedId)", status: .queued)
                activeJobs.append(job)
            }
        }

        Task {
            let queuedIds = activeJobs.filter { $0.status == .queued }.map { $0.postId }
            for postId in queuedIds {
                guard let idx = activeJobs.firstIndex(where: { $0.postId == postId }) else { continue }
                activeJobs[idx].status = .downloading

                do {
                    let posts = try await Downloader.download(postIds: [postId], to: targetDir)
                    guard let idx2 = activeJobs.firstIndex(where: { $0.postId == postId }) else { continue }
                    if let firstPost = posts.first {
                        activeJobs[idx2].status = .completed
                        activeJobs[idx2].title = firstPost.title
                        activeJobs[idx2].filesCount = firstPost.files.count
                    } else {
                        activeJobs[idx2].status = .failed
                    }
                } catch {
                    guard let idx2 = activeJobs.firstIndex(where: { $0.postId == postId }) else { continue }
                    activeJobs[idx2].status = .failed
                }
            }
            onFinished()
        }
    }
}

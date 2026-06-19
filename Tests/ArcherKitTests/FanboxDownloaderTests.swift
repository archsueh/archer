@testable import ArcherKit
import XCTest

@MainActor
final class FanboxDownloaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset activeJobs on singleton
        // Since activeJobs is private(set), we might not be able to clear it directly,
        // but we can verify it functions or reset if needed by recreating or resetting.
    }

    func testDownloadQueueManagerEnqueuesJobs() {
        let manager = DownloadQueueManager.shared
        let targetDir = FileManager.default.temporaryDirectory

        let initialCount = manager.activeJobs.count

        // Enqueue some dummy IDs
        manager.downloadPosts(postIds: ["test_id_1", "test_id_2"], targetDir: targetDir)

        // Immediately check that jobs are enqueued
        let active = manager.activeJobs
        XCTAssertEqual(active.count, initialCount + 2)

        if active.count >= 2 {
            let job1 = active.first(where: { $0.postId == "test_id_1" })
            XCTAssertNotNil(job1)
            XCTAssertTrue(job1?.status == .queued || job1?.status == .downloading || job1?.status == .failed)
        }
    }
}

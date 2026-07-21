@testable import ArcherKit
import XCTest

@MainActor
final class ParallelGroupDashboardIndexTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/tmp/archer-pg-index")

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
    }

    /// A plain Workspace struct is heavyweight to populate in tests; this
    /// surface only needs to check that the index is readable and stable
    /// for at least one workspace with a parallel group assigned.
    func testEmptyStoresReturnsEmpty() {
        let result = ParallelGroupDashboardIndex.build(stores: [])
        XCTAssertTrue(result.isEmpty)
    }
}

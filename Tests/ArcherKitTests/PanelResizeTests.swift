@testable import ArcherKit
import XCTest

/// [archer] P2: resizable panel width model — pure clamp + persistence logic.
final class PanelResizeTests: XCTestCase {
    func testClampWithinRangeUnchanged() {
        XCTAssertEqual(PanelWidths.clamp(300, to: 220 ... 560), 300)
    }

    func testClampBelowMinSnapsToMin() {
        XCTAssertEqual(PanelWidths.clamp(100, to: 160 ... 420), 160)
    }

    func testClampAboveMaxSnapsToMax() {
        XCTAssertEqual(PanelWidths.clamp(9999, to: 160 ... 420), 420)
    }

    func testResizeSidebarClampsToRange() {
        var w = PanelWidths()
        w.resize(.sidebar, to: 50)
        XCTAssertEqual(w.sidebar, PanelWidths.sidebarRange.lowerBound)
        w.resize(.sidebar, to: 5000)
        XCTAssertEqual(w.sidebar, PanelWidths.sidebarRange.upperBound)
    }

    func testResizeRightPanelClampsToRange() {
        var w = PanelWidths()
        w.resize(.rightPanel, to: 5000)
        XCTAssertEqual(w.rightPanel, PanelWidths.rightRange.upperBound)
    }

    func testDefaultsMatchExistingLayout() {
        let w = PanelWidths()
        XCTAssertEqual(w.sidebar, 220) // SidebarView.fullWidth
        XCTAssertEqual(w.rightPanel, 280) // DiffPanelView fixed width
    }

    func testCodableRoundTrip() throws {
        let w = PanelWidths(sidebar: 240, rightPanel: 320)
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(PanelWidths.self, from: data)
        XCTAssertEqual(w, back)
    }
}

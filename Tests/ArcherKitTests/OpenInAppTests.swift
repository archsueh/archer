@testable import ArcherKit
import XCTest

final class OpenInAppTests: XCTestCase {
    private func app(_ id: String) -> OpenInApp {
        OpenInApp.catalogById[id] ?? OpenInApp(id: id, title: id, bundleIdentifiers: [])
    }

    func testCatalogIdsAreUnique() {
        let ids = OpenInApp.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "catalog ids must be unique")
        XCTAssertEqual(OpenInApp.catalogById.count, OpenInApp.catalog.count)
    }

    func testCatalogAlwaysIncludesFinder() {
        // Finder always resolves on macOS, so it guarantees the picker is
        // never empty — pin it in the catalog.
        XCTAssertNotNil(OpenInApp.catalogById["finder"])
    }

    func testEveryCatalogAppHasABundleId() {
        for app in OpenInApp.catalog {
            XCTAssertFalse(app.title.isEmpty, "\(app.id) missing title")
            XCTAssertFalse(app.bundleIdentifiers.isEmpty, "\(app.id) missing bundle ids")
        }
    }

    func testOrderedRespectsUserOrderThenCatalog() {
        let apps = [app("vscode"), app("cursor"), app("finder")]
        let ordered = OpenInApp.ordered(apps, order: ["finder", "vscode"])
        XCTAssertEqual(ordered.map(\.id), ["finder", "vscode", "cursor"])
    }

    func testOrderedIgnoresUnknownAndUninstalledIds() {
        let apps = [app("vscode"), app("finder")]
        // "zed" isn't in `apps` (not installed), "bogus" isn't a real id —
        // both are dropped; the present apps keep catalog order.
        let ordered = OpenInApp.ordered(apps, order: ["bogus", "zed", "finder"])
        XCTAssertEqual(ordered.map(\.id), ["finder", "vscode"])
    }

    func testOrderedEmptyOrderIsCatalogOrder() {
        let apps = [app("cursor"), app("vscode"), app("finder")]
        XCTAssertEqual(OpenInApp.ordered(apps, order: []).map(\.id), apps.map(\.id))
    }

    func testEffectiveDefaultPrefersVisibleLastUsed() {
        let visible = [app("vscode"), app("cursor"), app("finder")]
        XCTAssertEqual(OpenInApp.effectiveDefault(lastUsedId: "cursor", visible: visible)?.id, "cursor")
    }

    func testEffectiveDefaultFallsBackToFirstWhenLastUsedHidden() {
        let visible = [app("vscode"), app("finder")]
        // last-used "cursor" isn't visible (hidden / uninstalled) → first visible.
        XCTAssertEqual(OpenInApp.effectiveDefault(lastUsedId: "cursor", visible: visible)?.id, "vscode")
    }

    func testEffectiveDefaultFirstWhenNoLastUsed() {
        let visible = [app("finder"), app("vscode")]
        XCTAssertEqual(OpenInApp.effectiveDefault(lastUsedId: nil, visible: visible)?.id, "finder")
    }

    func testEffectiveDefaultNilWhenNothingVisible() {
        XCTAssertNil(OpenInApp.effectiveDefault(lastUsedId: "vscode", visible: []))
    }
}

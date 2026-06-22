@testable import ArcherKit
import XCTest

final class EdgeGlowStateTests: XCTestCase {
    func testCompletedMapsToRunningPulse() {
        XCTAssertEqual(EdgeGlow.state(for: .completed), .pulse(.running))
    }

    func testAttentionMapsToAttentionHold() {
        XCTAssertEqual(EdgeGlow.state(for: .attention), .hold(.attention))
    }

    func testFailureMapsToFailureHold() {
        XCTAssertEqual(EdgeGlow.state(for: .failure), .hold(.failure))
    }

    func testHoldStatesLingerPulseDoesNot() {
        XCTAssertTrue(EdgeGlow.state(for: .attention).lingers)
        XCTAssertTrue(EdgeGlow.state(for: .failure).lingers)
        XCTAssertFalse(EdgeGlow.state(for: .completed).lingers)
    }

    func testPriorityOrder() {
        XCTAssertGreaterThan(EdgeGlowState.hold(.failure).priority,
                             EdgeGlowState.hold(.attention).priority)
        XCTAssertGreaterThan(EdgeGlowState.hold(.attention).priority,
                             EdgeGlowState.running.priority)
        XCTAssertGreaterThan(EdgeGlowState.running.priority,
                             EdgeGlowState.pulse(.running).priority)
        XCTAssertGreaterThan(EdgeGlowState.pulse(.running).priority,
                             EdgeGlowState.idle.priority)
    }

    func testTone() {
        XCTAssertNil(EdgeGlowState.idle.tone)
        XCTAssertEqual(EdgeGlowState.running.tone, .running)
        XCTAssertEqual(EdgeGlowState.pulse(.failure).tone, .failure)
        XCTAssertEqual(EdgeGlowState.hold(.attention).tone, .attention)
    }
}

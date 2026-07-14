// [archer] TDD for SessionRecorder — verifies the coordinator wires engine
// events into the `.termctrl` timeline correctly (input frame + marker +
// finalize), without touching libghostty's PTY path.

import AppKit
@testable import ArcherKit
import Foundation
import Testing

@Suite("SessionRecorder")
@MainActor
struct SessionRecorderTests {
    @MainActor
    final class FakeEngine: TerminalEngine {
        let view: NSView = .init()
        var backgroundColor: NSColor {
            .black
        }

        var onPwdChange: ((String) -> Void)?
        var onTitleChange: ((String) -> Void)?
        var onFocus: (() -> Void)?
        var onCommandFinished: ((Int?, TimeInterval) -> Void)?
        var onUserInput: (() -> Void)?
        var onProcessExitedCleanly: (() -> Void)?
        var onScrollPositionChange: ((Int, Int, Int) -> Void)?
        var onNewOutputWhileScrolledUp: (() -> Void)?
        var onSearchStart: ((String) -> Void)?
        var onSearchEnd: (() -> Void)?
        var onSearchTotal: ((Int) -> Void)?
        var onSearchSelected: ((Int) -> Void)?
        var foregroundPid: pid_t? {
            nil
        }

        var grabbedFocusOnMount: Bool = true
        var grabsFocusOnMount: Bool = true
        func start(config _: TerminalSessionConfig) {}
        func terminate() {}
        var suspendsSizePropagation: Bool {
            false
        }

        func beginSizePropagationSuspension() {}
        func endSizePropagationSuspension() {}
        func flushSize() {}
        @discardableResult func performAction(_: String) -> Bool {
            true
        }

        // Captured screen snapshot returned to the recorder.
        var screenText: String?
        func sendInput(_: String) {}
        func paste(_: String) {}
        func readSelection() -> String? {
            nil
        }

        var nextScreen: String?
        func readScreen(lines _: Int) -> String? {
            nextScreen ?? screenText
        }

        var recorder: SessionRecorder?
    }

    @Test("input + marker produce schema-clean entries and finalize closes the file")
    func inputAndMarker() throws {
        let engine = FakeEngine()
        engine.nextScreen = "user@host:~$ ls\nfile1  file2\n"
        let rec = try #require(SessionRecorder(sessionID: UUID(), cols: 80, rows: 24, engine: engine))
        rec.recordClientInput("ls")
        rec.mark("step-1")
        rec.stop()

        let lines = RecorderStore.readLines(rec.url)
        #expect(lines.count == 4) // header + input + output(snapshot) + marker

        let kinds = lines.dropFirst().compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["type"] as? String
        }
        #expect(kinds.contains("input"))
        #expect(kinds.contains("output"))
        #expect(kinds.contains("marker"))

        // File must be readable after finalize (handle closed cleanly).
        #expect(FileManager.default.fileExists(atPath: rec.url.path))
    }

    @Test("marker name round-trips in the marker entry")
    func markerName() throws {
        let engine = FakeEngine()
        let rec = try #require(SessionRecorder(sessionID: UUID(), cols: 80, rows: 24, engine: engine))
        rec.mark("my-clip")
        rec.stop()

        let lines = RecorderStore.readLines(rec.url)
        let markerLine = try #require(lines.last)
        let marker = try #require(try? JSONSerialization.jsonObject(with: Data(markerLine.utf8)) as? [String: Any])
        #expect(marker["type"] as? String == "marker")
        #expect(marker["name"] as? String == "my-clip")
    }
}

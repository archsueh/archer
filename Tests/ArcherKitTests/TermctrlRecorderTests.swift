// [archer] TDD for TermctrlRecorder — verifies the `.termctrl` output is
// schema-compatible with terminal-control's recording-entry-v1 (so `termctrl
// video` can consume it) and obeys the security red lines (0o600, never
// auto-record — callers gate that).

@testable import ArcherKit
import Foundation
import Testing

@Suite("TermctrlRecorder")
struct TermctrlRecorderTests {
    /// Isolated temp dir so we never touch ~/.archer/recordings during tests.
    let tmp: URL

    init() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-recorder-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    @Test("header line matches termctrl schema")
    func headerSchema() throws {
        let rec = try #require(TermctrlRecorder(
            sessionID: UUID(), cols: 80, rows: 24, baseDir: tmp
        ))
        rec.finalize()

        let lines = RecorderStore.readLines(rec.url)
        #expect(lines.count == 1)
        let header = try #require(try? JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(header["type"] as? String == "header")
        #expect(header["version"] as? Int == 1)
        #expect(header["cols"] as? Int == 80)
        #expect(header["rows"] as? Int == 24)
        #expect(header["cell_width"] as? Int == 9)
        #expect(header["cell_height"] as? Int == 18)
    }

    @Test("output/input/marker entries carry correct fields")
    func entryShapes() throws {
        let rec = try #require(TermctrlRecorder(
            sessionID: UUID(), cols: 80, rows: 24, baseDir: tmp
        ))
        rec.recordOutput("hello\n")
        rec.recordInput("ls", origin: .client)
        rec.recordMarker("step-1")
        rec.finalize()

        let lines = RecorderStore.readLines(rec.url)
        #expect(lines.count == 4) // header + 3

        let output = try #require(try? JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        #expect(output["type"] as? String == "output")
        #expect((output["at_ms"] as? NSNumber)?.intValue ?? -1 >= 0)
        #expect(output["text"] as? String == "hello\n")

        let input = try #require(try? JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any])
        #expect(input["type"] as? String == "input")
        #expect(input["origin"] as? String == "client")
        #expect(input["text"] as? String == "ls")

        let marker = try #require(try? JSONSerialization.jsonObject(with: Data(lines[3].utf8)) as? [String: Any])
        #expect(marker["type"] as? String == "marker")
        #expect(marker["name"] as? String == "step-1")
    }

    @Test("empty text is dropped, file stays schema-clean")
    func dropsEmpty() throws {
        let rec = try #require(TermctrlRecorder(
            sessionID: UUID(), cols: 80, rows: 24, baseDir: tmp
        ))
        rec.recordOutput("")
        rec.recordInput("", origin: .client)
        rec.recordMarker("   ")
        rec.finalize()

        let lines = RecorderStore.readLines(rec.url)
        #expect(lines.count == 1) // only header
    }

    @Test("file is created 0o600")
    func filePermissions() throws {
        let rec = try #require(TermctrlRecorder(
            sessionID: UUID(), cols: 80, rows: 24, baseDir: tmp
        ))
        rec.finalize()

        var st = stat()
        #expect(stat((rec.url.path as NSString).fileSystemRepresentation, &st) == 0)
        let perms = st.st_mode & 0o777
        #expect(perms == 0o600, "expected 0o600, got \(String(perms, radix: 8))")
    }

    @Test("markers are sorted by timestamp, never reordered")
    func markerOrder() throws {
        let rec = try #require(TermctrlRecorder(
            sessionID: UUID(), cols: 80, rows: 24, baseDir: tmp
        ))
        rec.recordMarker("a")
        rec.recordMarker("b")
        rec.recordMarker("c")
        rec.finalize()

        let lines = RecorderStore.readLines(rec.url)
        let names = lines.dropFirst().compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["name"] as? String
        }
        #expect(names == ["a", "b", "c"])
    }
}

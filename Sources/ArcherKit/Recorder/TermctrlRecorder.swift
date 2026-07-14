// [archer] Session recorder — writes `.termctrl` JSON Lines compatible with
// kitlangton/terminal-control's recording-entry-v1 schema, so `termctrl video`
// can consume archer-recorded sessions directly (no PTY re-drive).
//
// Design: archer does NOT use GHOSTTY_SURFACE_IO_MANUAL on the main path
// (that mode is only exercised by TerminalKeyRoutingTests and would bypass
// libghostty's default PTY write path — unverified for production rendering).
// Instead the recorder collects screen snapshots (via readScreen) + input
// echoes (via sendInput/paste bypasses) + explicit markers, each timestamped,
// and replays them into a structured timeline. This is a safe superset of what
// termctrl needs for its `video` export: it reads the file, never the live PTY.

import Foundation

/// Who produced a byte event. Mirrors termctrl's `InputOrigin` (client/host).
enum RecorderInputOrigin: String, Codable {
    case client // typed/pasted by the user through archer
    case host // output from the program/shell
}

/// One timeline entry. Field names + shape match terminal-control's
/// recording-entry-v1 JSON schema (deny_unknown_fields on their side), so the
/// file round-trips through `termctrl` unchanged.
/// Namespaced entry payloads. Each is independently Codable + carries a constant
/// `type` string so the JSON Lines file is schema-identical to termctrl's
/// recording-entry-v1 (its decoder uses `deny_unknown_fields`).
enum RecorderEntry {
    /// Each entry encodes a constant `type` string and decodes it as well
    /// (termctrl's schema is `deny_unknown_fields`, so the literal must match).
    struct Header: Codable {
        let type: String
        let version: UInt8
        let cols: UInt16
        let rows: UInt16
        let cell_width: UInt16
        let cell_height: UInt16
        init(version: UInt8, cols: UInt16, rows: UInt16, cell_width: UInt16, cell_height: UInt16) {
            type = "header"
            self.version = version; self.cols = cols; self.rows = rows
            self.cell_width = cell_width; self.cell_height = cell_height
        }
    }

    struct Output: Codable {
        let type: String
        let at_ms: UInt64
        let text: String
        init(at_ms: UInt64, text: String) {
            type = "output"; self.at_ms = at_ms; self.text = text
        }
    }

    struct Input: Codable {
        let type: String
        let at_ms: UInt64
        let origin: String
        let text: String
        init(at_ms: UInt64, origin: String, text: String) {
            type = "input"; self.at_ms = at_ms; self.origin = origin; self.text = text
        }
    }

    struct Resize: Codable {
        let type: String
        let at_ms: UInt64
        let cols: UInt16
        let rows: UInt16
        let cell_width: UInt16
        let cell_height: UInt16
        init(at_ms: UInt64, cols: UInt16, rows: UInt16, cell_width: UInt16, cell_height: UInt16) {
            type = "resize"; self.at_ms = at_ms
            self.cols = cols; self.rows = rows
            self.cell_width = cell_width; self.cell_height = cell_height
        }
    }

    struct Marker: Codable {
        let type: String
        let at_ms: UInt64
        let name: String
        init(at_ms: UInt64, name: String) {
            type = "marker"; self.at_ms = at_ms; self.name = name
        }
    }
}

/// Writes a `.termctrl` timeline. Each entry is one line of JSON; the first
/// line is always the header. File is created `0o600` (terminal content is
/// potentially sensitive — hook payloads, secrets on the prompt, etc.).
///
/// Not `@MainActor`: the recorder only does file IO + `Date()` (both
/// thread-safe), so callers can write from any context (e.g. a libghostty
/// callback thread) without bouncing to main.
final class TermctrlRecorder {
    static let formatVersion: UInt8 = 1

    let sessionID: UUID
    private let fileURL: URL
    private let start: Date
    private let fileHandle: FileHandle
    private var finalized = false

    // Geometry at open; resize events update the live snapshot.
    private var cols: UInt16
    private var rows: UInt16
    private let cellWidth: UInt16 = 9
    private let cellHeight: UInt16 = 18

    /// Creates the recorder and writes the header line. Fails (returns nil) if
    /// the output directory can't be prepared or the file can't be opened.
    init?(sessionID: UUID, cols: Int, rows: Int, baseDir: URL = RecorderStore.defaultDirectory) {
        self.sessionID = sessionID
        self.cols = UInt16(clamping: cols)
        self.rows = UInt16(clamping: rows)
        start = Date()

        let dir = baseDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("archer-recorder: cannot create \(dir.path): \(error)")
            return nil
        }

        let stamp = ISO8601DateFormatter().string(from: start)
        fileURL = dir.appendingPathComponent("\(stamp)-\(sessionID.uuidString.prefix(8)).termctrl")

        do {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: fileURL)
            fileHandle = handle
        } catch {
            NSLog("archer-recorder: cannot open \(fileURL.path): \(error)")
            return nil
        }

        write(RecorderEntry.Header(version: Self.formatVersion, cols: self.cols, rows: self.rows, cell_width: cellWidth, cell_height: cellHeight))
    }

    var url: URL {
        fileURL
    }

    func elapsedMs() -> UInt64 {
        UInt64((Date().timeIntervalSince(start)) * 1000)
    }

    /// Program output, captured as a discrete screen snapshot.
    func recordOutput(_ text: String) {
        guard !text.isEmpty else { return }
        write(RecorderEntry.Output(at_ms: elapsedMs(), text: text))
    }

    /// User or program input. `origin` discriminates typed (client) vs
    /// program-driven (host) writes.
    func recordInput(_ text: String, origin: RecorderInputOrigin = .client) {
        guard !text.isEmpty else { return }
        write(RecorderEntry.Input(at_ms: elapsedMs(), origin: origin.rawValue, text: text))
    }

    /// Explicit named marker — the unit the user clicks to flag an important
    /// moment for later `termctrl video` clip selection.
    func recordMarker(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        write(RecorderEntry.Marker(at_ms: elapsedMs(), name: trimmed))
    }

    func recordResize(cols: Int, rows: Int) {
        self.cols = UInt16(clamping: cols)
        self.rows = UInt16(clamping: rows)
        write(RecorderEntry.Resize(at_ms: elapsedMs(), cols: self.cols, rows: self.rows, cell_width: cellWidth, cell_height: cellHeight))
    }

    /// Flushes + closes the file. Idempotent.
    func finalize() {
        guard !finalized else { return }
        finalized = true
        try? fileHandle.synchronize()
        try? fileHandle.close()
    }

    private func write<T: Encodable>(_ value: T) {
        guard !finalized else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try fileHandle.write(contentsOf: data)
            try fileHandle.write(contentsOf: Data("\n".utf8))
        } catch {
            NSLog("archer-recorder: write failed: \(error)")
        }
    }

    deinit {
        try? fileHandle.close()
    }
}

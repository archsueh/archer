// [archer] SessionRecorder — per-surface coordinator that turns archer's
// existing terminal events (user input, command finish, explicit markers,
// resize) into a `.termctrl` timeline via TermctrlRecorder. Reads screen
// snapshots through the surface's `readScreen`, never touches libghostty's
// PTY IO path (so it can't destabilise rendering). The resulting file is
// directly consumable by `termctrl video` for clip export.

import Foundation

@MainActor
final class SessionRecorder {
    /// Factory lets the engine reference the recorder without importing the
    /// concrete surface type (avoids a circular dependency). Wired up by
    /// `GhosttySurfaceView` which owns the readScreen capability.
    private let underlying: TermctrlRecorder
    private weak var engine: (any TerminalEngine)?

    init?(sessionID: UUID, cols: Int, rows: Int, engine: any TerminalEngine) {
        guard let rec = TermctrlRecorder(sessionID: sessionID, cols: cols, rows: rows) else {
            return nil
        }
        underlying = rec
        self.engine = engine
    }

    var url: URL {
        underlying.url
    }

    /// Capture the current screen as an `output` frame. Called on semantic
    /// events (command finished, user input) rather than every render tick,
    /// mirroring termctrl's "store a frame only on change" economy.
    func captureScreen() {
        guard let text = engine?.readScreen(lines: Int.max) else { return }
        underlying.recordOutput(text)
    }

    /// User typed/pasted through archer — an `input` frame from the client.
    func recordClientInput(_ text: String) {
        underlying.recordInput(text, origin: .client)
        captureScreen()
    }

    /// A command finished (OSC 133;D) — snapshot the result.
    func recordCommandFinished() {
        captureScreen()
    }

    /// Explicit named marker — the clip anchor for `termctrl video`.
    func mark(_ name: String) {
        underlying.recordMarker(name)
    }

    func recordResize(cols: Int, rows: Int) {
        underlying.recordResize(cols: cols, rows: rows)
        captureScreen()
    }

    func stop() {
        underlying.finalize()
    }
}

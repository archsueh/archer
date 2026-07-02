import Foundation

/// Single source of truth for product metadata — surfaced by the About panel,
/// Help menu, and window title. Bump `displayVersion` on every release so the
/// About panel matches the latest CHANGELOG `vX.Y` tag.
enum ArcherApp {
    static let name = "Archer" // [archer] display name; internal id stays ArcherApp
    static let displayVersion = "1.0.6"
    static let tagline = "A minimal modern terminal for AI coding"
    static let author = "archsueh"
    static let authorURL = URL(string: "https://github.com/archsueh/archer")!
    static let copyrightYear = "2026"

    static let repositoryURL = URL(string: "https://github.com/archsueh/archer")!
    static let issuesURL = URL(string: "https://github.com/archsueh/archer/issues")!
    /// Mirrors `repositoryURL`; update both if the repo is ever renamed.
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/archsueh/archer/releases/latest")!
}

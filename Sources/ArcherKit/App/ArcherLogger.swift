import os

/// Shared `os.Logger` instances, one per functional category.
/// Usage: `ArcherLogger.skills.info("Loaded \(count) skills")`
/// Filter in Terminal: `log stream --predicate 'subsystem == "com.archsueh.archer"'`
enum ArcherLogger {
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let terminal = Logger(subsystem: subsystem, category: "terminal")
    static let hooks = Logger(subsystem: subsystem, category: "hooks")
    static let skills = Logger(subsystem: subsystem, category: "skills")
    static let usage = Logger(subsystem: subsystem, category: "usage")
    static let cli = Logger(subsystem: subsystem, category: "cli")
    static let fonts = Logger(subsystem: subsystem, category: "fonts")

    private static let subsystem = "com.archsueh.archer"
}

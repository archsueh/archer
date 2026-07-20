import AppKit
import ArcherKit

let app = NSApplication.shared
// [archer] ported from iAmCorey/kooky (v0.31.6): reroute stderr to a
// crash log before the app object is constructed, so a low-level panic
// during launch isn't lost to /dev/null.
CrashForensics.install()
let delegate = AppDelegate()
app.delegate = delegate
app.run()

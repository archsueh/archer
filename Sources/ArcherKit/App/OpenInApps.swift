import AppKit

/// A known external application archer can hand the current directory to via
/// the top-chrome "Open in" control. Detection is by bundle id — an app only
/// appears in the picker when at least one of its candidate bundle ids
/// resolves on this machine (Finder always resolves). Icons come from the
/// installed `.app` via `NSWorkspace`, so VS Code / Cursor / Finder show their
/// real marks with no bundled PNGs.
///
/// The struct itself is plain (not `@MainActor`) so its pure ordering helpers
/// are reachable from tests without hopping to the main actor; the
/// `NSWorkspace`-touching resolution lives in `OpenInResolver`.
struct OpenInApp: Identifiable, Hashable {
    let id: String
    let title: String
    /// Candidate bundle ids, tried in order — the first that resolves wins.
    /// Apps with stable/insider/CE variants list several so any installed
    /// flavour is detected.
    let bundleIdentifiers: [String]

    static func == (lhs: OpenInApp, rhs: OpenInApp) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension OpenInApp {
    /// Curated catalog. The order here is the default picker / Settings order
    /// before the user reorders: editors / IDEs first, then terminals, then
    /// Finder. Bundle ids verified against real installs; an unknown id simply
    /// doesn't resolve and the app stays hidden.
    static let catalog: [OpenInApp] = [
        // Editors / IDEs
        OpenInApp(id: "vscode", title: "VS Code", bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]),
        OpenInApp(id: "cursor", title: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]),
        OpenInApp(id: "windsurf", title: "Windsurf", bundleIdentifiers: ["com.exafunction.windsurf"]),
        OpenInApp(id: "zed", title: "Zed", bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview"]),
        OpenInApp(id: "sublime", title: "Sublime Text", bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"]),
        OpenInApp(id: "antigravity", title: "Antigravity", bundleIdentifiers: ["com.google.antigravity"]),
        OpenInApp(id: "trae", title: "Trae", bundleIdentifiers: ["com.trae.app", "cn.trae.app"]),
        OpenInApp(id: "kiro", title: "Kiro", bundleIdentifiers: ["dev.kiro.desktop"]),
        OpenInApp(id: "xcode", title: "Xcode", bundleIdentifiers: ["com.apple.dt.Xcode"]),
        OpenInApp(id: "intellij", title: "IntelliJ IDEA", bundleIdentifiers: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]),
        OpenInApp(id: "pycharm", title: "PyCharm", bundleIdentifiers: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]),
        OpenInApp(id: "webstorm", title: "WebStorm", bundleIdentifiers: ["com.jetbrains.WebStorm"]),
        // Terminals
        OpenInApp(id: "terminal", title: "Terminal", bundleIdentifiers: ["com.apple.Terminal"]),
        OpenInApp(id: "iterm", title: "iTerm", bundleIdentifiers: ["com.googlecode.iterm2"]),
        OpenInApp(id: "ghostty", title: "Ghostty", bundleIdentifiers: ["com.mitchellh.ghostty"]),
        OpenInApp(id: "warp", title: "Warp", bundleIdentifiers: ["dev.warp.Warp-Stable"]),
        // File manager — always installed, so the picker is never empty.
        OpenInApp(id: "finder", title: "Finder", bundleIdentifiers: ["com.apple.finder"]),
    ]

    static let catalogById: [String: OpenInApp] =
        Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Apply the user's saved order to a set of apps (typically the installed
    /// subset). Apps named in `order` come first in that order; the rest follow
    /// in catalog order. Unknown ids in `order` are ignored. Mirrors
    /// `AgentTemplate.ordered`.
    static func ordered(_ apps: [OpenInApp], order: [String]) -> [OpenInApp] {
        let byId = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let userOrderIds = order.filter { byId.keys.contains($0) }
        let userOrderSet = Set(userOrderIds)
        let missing = apps.filter { !userOrderSet.contains($0.id) }
        return userOrderIds.compactMap { byId[$0] } + missing
    }

    /// The app the split button shows / a plain click opens. Preference: the
    /// persisted last-used app while it's still visible, else the first visible
    /// app, else nil. `visible` is the already installed-and-not-hidden,
    /// ordered list.
    static func effectiveDefault(lastUsedId: String?, visible: [OpenInApp]) -> OpenInApp? {
        if let lastUsedId, let hit = visible.first(where: { $0.id == lastUsedId }) { return hit }
        return visible.first
    }
}

/// `NSWorkspace`-backed resolution for the `OpenInApp` catalog: which apps are
/// installed, their icons, and the open action. Caches both the app-URL
/// resolution and the decoded icon (SwiftUI re-runs the button body on hover /
/// theme change); `invalidate()` drops the caches so a freshly-installed app
/// is picked up the next time the picker opens.
@MainActor
enum OpenInResolver {
    /// `URL?` value type (not `URL`) so a *miss* is cached too — otherwise every
    /// SwiftUI body pass (hover, theme repaint) re-queries LaunchServices for
    /// the dozen-plus uninstalled catalog entries. `invalidate()` drops the
    /// whole map, so fresh-install detection is unaffected.
    private static var urlCache: [String: URL?] = [:]
    private static var iconCache: [String: NSImage] = [:]

    /// First candidate bundle id that resolves to an installed app, if any.
    static func appURL(for app: OpenInApp) -> URL? {
        if let cached = urlCache[app.id] { return cached }
        for bid in app.bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                urlCache.updateValue(url, forKey: app.id)
                return url
            }
        }
        urlCache.updateValue(nil, forKey: app.id)
        return nil
    }

    static func isInstalled(_ app: OpenInApp) -> Bool {
        appURL(for: app) != nil
    }

    /// 16×16-sized icon of the installed app (pixel data stays native so a
    /// `.resizable()` SwiftUI caller renders sharp at any frame size).
    static func icon(for app: OpenInApp) -> NSImage? {
        if let hit = iconCache[app.id] { return hit }
        guard let url = appURL(for: app) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        iconCache[app.id] = image
        return image
    }

    /// Installed catalog apps in the user's order, then catalog order. Backs
    /// the Settings reorder list (shows installed apps, hidden or not).
    static func installedApps(model: ArcherSettingsModel) -> [OpenInApp] {
        let installed = OpenInApp.catalog.filter { isInstalled($0) }
        return OpenInApp.ordered(installed, order: model.openInAppOrder)
    }

    /// Installed and not hidden — what the picker shows.
    static func visibleApps(model: ArcherSettingsModel) -> [OpenInApp] {
        installedApps(model: model).filter { !model.hiddenOpenInApps.contains($0.id) }
    }

    /// Open `directory` in `app`. Editors open the folder as a project,
    /// terminals open a new session there, Finder opens the folder window.
    static func open(directory: URL, with app: OpenInApp) {
        guard var resolved = appURL(for: app) else { return }
        // The cached URL can point at an app moved/uninstalled mid-session. If
        // it's gone, bust the cache and re-resolve once so a plain left-zone
        // click doesn't silently no-op (the picker self-heals via invalidate(),
        // but the left zone never calls it).
        if !FileManager.default.fileExists(atPath: resolved.path) {
            urlCache.removeValue(forKey: app.id)
            guard let fresh = appURL(for: app) else { return }
            resolved = fresh
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: resolved, configuration: config)
    }

    static func invalidate() {
        urlCache.removeAll()
        iconCache.removeAll()
    }
}

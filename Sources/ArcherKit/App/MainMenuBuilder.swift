// [archer] MainMenuBuilder.swift
//
// Extracted from AppDelegate to shrink its God-Object surface (codeflow
// health pass flagged AppDelegate as a >1200-line hotspot). Holds the menu
// DSL (MenuRow / MenuEntry / row builders / buildMenu / submenu) and the
// OpenRecentMenuDelegate used by File → Open Recent.
//
// The `installMainMenu()` method itself stays in AppDelegate — its `#selector`
// references resolve against AppDelegate's own @objc handlers there. Only the
// declarative DSL and the delegate class moved here.
//
// Ported-from-kooky recent-folders wiring (the rebuild closure calling
// handleOpenRecentFolder/handleClearRecentFolders) lives in AppDelegate; only
// the OpenRecentMenuDelegate *class* is defined here.

import AppKit

// MARK: - Menu DSL

struct MenuRow {
    let title: String
    let selector: Selector
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let target: AnyObject?
    let tag: Int
}

enum MenuEntry {
    case row(MenuRow)
    case separator
    /// [archer] nest an already-built submenu (e.g. File → Open Recent).
    case submenu(NSMenu)
}

enum MainMenuBuilder {
    /// Item routed to a concrete `target` — used for AppDelegate `handle*`
    /// methods that need an explicit target.
    static func selfRow(_ title: String, _ selector: Selector, _ key: String = "",
                        target: AnyObject?,
                        modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> MenuEntry
    {
        .row(MenuRow(title: title, selector: selector, key: key,
                     modifiers: modifiers, target: target, tag: tag))
    }

    /// Item with `target: nil` — AppKit dispatches via the responder chain.
    /// Used for system selectors like `NSWindow.performZoom(_:)` and
    /// `NSText.cut(_:)`, which let libghostty / the active window handle them.
    static func responderRow(_ title: String, _ selector: Selector, _ key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command) -> MenuEntry
    {
        .row(MenuRow(title: title, selector: selector, key: key,
                     modifiers: modifiers, target: nil, tag: 0))
    }

    static func buildMenu(title: String, entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu(title: title)
        for entry in entries {
            switch entry {
            case let .row(row):
                let item = NSMenuItem(title: L10n.string(row.title), action: row.selector, keyEquivalent: row.key) // [archer] localize
                item.keyEquivalentModifierMask = row.modifiers
                item.target = row.target
                item.tag = row.tag
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            case let .submenu(sub):
                let item = NSMenuItem()
                item.title = sub.title
                item.submenu = sub
                menu.addItem(item)
            }
        }
        return menu
    }

    /// Wrap an NSMenu as a menu-bar NSMenuItem. AppKit renders the item's own
    /// title (submenu.title is not a fallback), so copy it across.
    static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = L10n.string(menu.title) // [archer] localize bar title
        item.submenu = menu
        return item
    }
}

// MARK: - Open Recent menu delegate

/// Rebuilds File → Open Recent from `RecentFolders` on every open (the menu
/// is a stable shell; items are regenerated each time). Ported from
/// iAmCorey/kooky (v0.35, issue #28).
final class OpenRecentMenuDelegate: NSObject, NSMenuDelegate {
    var rebuild: (NSMenu) -> Void = { _ in }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    func menuHasKeyEquivalent(
        _: NSMenu,
        for _: NSEvent,
        target _: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        action _: UnsafeMutablePointer<Selector?>
    ) -> Bool {
        false // recent items never carry key equivalents
    }
}

import AppKit
import Sparkle
import SwiftUI

/// Namespace for the View menu's Tab/Workspace switch items. Tags share a
/// single integer field on `NSMenuItem`, so we partition them: 1...9 for tabs
/// (matching ⌘N), 101...109 for workspaces (⌥⌘N). The 100 offset keeps both
/// sets identifiable from `menuNeedsUpdate`.
private enum MenuTag {
    static let tabRange = 1 ... 9
    static let workspaceRange = 101 ... 109
    static func tab(_ n: Int) -> Int {
        n
    }

    static func workspace(_ n: Int) -> Int {
        100 + n
    }

    static func tabIndex(from tag: Int) -> Int {
        tag - 1
    }

    static func workspaceIndex(from tag: Int) -> Int {
        tag - 101
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windowControllers: [ArcherWindowController] = [] {
        // Every window add/remove flows through this one property, so bump the
        // agent monitor here — the right sidebar re-aggregates over the new
        // window set, and no future mutation site can forget to.
        didSet { AgentMonitor.shared.windowGeneration += 1 }
    }

    /// [archer] File → Open Recent. Items are rebuilt from `RecentFolders`
    /// on every open via the dedicated delegate — the menu itself is a
    /// stable shell. Ported from iAmCorey/kooky (v0.35, issue #28).
    private let openRecentMenu = NSMenu(title: "Open Recent")
    private let openRecentMenuDelegate = OpenRecentMenuDelegate()

    private let appPersistence = AppPersistence()
    /// Set in `applicationShouldTerminate` so `windowWillClose` (fired for
    /// every window during ⌘Q) can tell "app quitting" from "user closed
    /// one window" — the former keeps each window's persisted slot.
    private var isTerminating = false
    private var cliDetectionController: CLIDetectionWindowController?
    /// Walks the macOS window cascade so a `⌘⇧N` window doesn't land
    /// exactly on top of the previous one.
    private var cascadePoint = NSPoint.zero
    /// The archer window that was key most recently. `activeStore` routes
    /// here (not an arbitrary array slot) when a Settings / Update panel is
    /// the key window. Weak so a closed window doesn't pin its store.
    private weak var lastKeyController: ArcherWindowController?
    /// Posts macOS notifications when a backgrounded agent needs attention or
    /// a command fails. Bundle-gated, so it no-ops under `swift run`.
    private let notificationManager = NotificationManager()
    /// cmux-style unified local listener: serves the bridge (archer-bridge CLI)
    /// and hook (ArcherHook CLI) protocols on ONE unix socket, demuxing by
    /// first-frame JSON keys. Replaces the old separate BridgeServer +
    /// HookServer sockets (see UnifiedListener for the symlink-compat detail).
    private lazy var unifiedListener: UnifiedListener = {
        UnifiedListener(
            hookHandler: { [weak self] message in
                guard let self else { return }
                switch message {
                case let .agent(agent, event, _):
                    BridgeEventLog.shared.append(category: .hook, summary: "\(agent.id) \(event.rawValue)")
                case let .toolCall(agent, toolName, identifier, event, success, _, _):
                    let result = success.map { $0 ? " ✓" : " ✗" } ?? ""
                    BridgeEventLog.shared.append(category: .hook,
                                                 summary: "\(agent.id) \(toolName)\(identifier.isEmpty ? "" : " \(identifier)")\(result) [\(event.rawValue)]")
                default:
                    break
                }
                for controller in self.windowControllers {
                    let store = controller.store
                    switch message {
                    case let .agent(agent, event, sessionId):
                        store.applyHookEvent(agent: agent, event: event, sessionId: sessionId)
                    case let .shellEnvironment(env, sessionId):
                        store.applyShellEnvironment(env, sessionId: sessionId)
                    case let .conversationId(conversationId, sessionId):
                        store.applyConversationId(conversationId: conversationId, sessionId: sessionId)
                    case let .toolCall(agent, toolName, identifier, event, success, toolUseId, sessionId):
                        store.applyToolCallEvent(
                            agent: agent,
                            toolName: toolName,
                            identifier: identifier,
                            event: event,
                            success: success,
                            toolUseId: toolUseId,
                            sessionId: sessionId
                        )
                    }
                }
            },
            storeProvider: { [weak self] in self?.activeController?.store }
        )
    }

    /// State shared between Sparkle's callbacks and Archer's glass-styled
    /// update window — see `ArcherUpdateUserDriver` and `UpdatePromptView`.
    private let updateFlow = UpdateFlowController()
    private lazy var updateDriver = ArcherUpdateUserDriver(flow: updateFlow)
    /// `SUEnableAutomaticChecks=false` in Info.plist keeps this manual-only:
    /// no startup poll, no background schedule, no permission prompt.
    private lazy var updater = SPUUpdater(
        hostBundle: Bundle.main,
        applicationBundle: Bundle.main,
        userDriver: updateDriver,
        delegate: nil
    )

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_: Notification) {
        do {
            try updater.start()
        } catch {
            ArcherLogger.updates.error("Sparkle updater failed to start: \(error, privacy: .public)")
        }
        ArcherFonts.registerOnce()
        // First-launch onboarding (blocking NSAlert if a ghostty config exists)
        // — must run before any window is created and before any libghostty
        // surface is spawned, since `LibghosttyApp` reads `~/.archer/settings.json`
        // at process init when the first surface is created.
        ArcherOnboarding.runIfNeeded()
        let settings = ArcherSettingsModel.shared
        // Capture value-typed settings before leaving the main actor so the
        // detached task can't race on @Observable state.
        let sshRemote = settings.sshRemoteAgentDetection
        let customAgents = settings.customAgents
        // Hook file writes are pure disk I/O and don't need to block the
        // window. Shell processes that read these files only spawn after the
        // window is visible, so running in parallel with restoreWindows() is
        // safe — and the previous on-disk files remain valid in the meantime.
        Task.detached(priority: .userInitiated) {
            ArcherShellIntegration.installAgentHooks(sshRemoteAgentDetection: sshRemote)
            ArcherShellIntegration.refreshClaudeCustomSettings(customAgents: customAgents)
        }

        restoreWindows()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installMainMenu()
        // [archer] Open Recent submenu rebuilds from RecentFolders on open.
        openRecentMenu.delegate = openRecentMenuDelegate
        openRecentMenuDelegate.rebuild = { [weak self] menu in
            guard let self else { return }
            menu.removeAllItems()
            let folders = RecentFolders.shared.existing
            if folders.isEmpty {
                let empty = NSMenuItem(title: "No Recent Folders", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
                return
            }
            for url in folders {
                let item = NSMenuItem(
                    title: (url.path as NSString).abbreviatingWithTildeInPath,
                    action: #selector(self.handleOpenRecentFolder(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = url
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(
                title: "Clear Recent Folders",
                action: #selector(self.handleClearRecentFolders),
                keyEquivalent: ""
            )
            menu.addItem(clear)
        }
        showCLIDetectionIfNeeded()
        unifiedListener.start()
        notificationManager.onActivate = { [weak self] sessionId in
            self?.activateFromNotification(sessionId)
        }
        notificationManager.start()
        // The right-side agent overview reads the global AgentMonitor; give it
        // the live window stores to aggregate + the same reveal-tab jump.
        AgentMonitor.shared.storesProvider = { [weak self] in
            self?.windowControllers.map(\.store) ?? []
        }
        AgentMonitor.shared.onActivate = { [weak self] sessionId in
            self?.activateFromNotification(sessionId)
        }

        // Sweep paste-image cache off the launch hot path. macOS's
        // own Caches eviction is unreliable; without this a heavy
        // Cmd+V-screenshots workflow accumulates GBs over months.
        Task.detached(priority: .utility) {
            ArcherShellIntegration.prunePastesCache()
        }

        // Follow the macOS system appearance. `AppleInterfaceThemeChangedNotification`
        // (posted by the OS on dark/light toggle) updates the auto-theme source
        // of truth; if the user picked "Auto（跟随系统）", re-saving re-resolves
        // the concrete theme + reloads the libghostty surface live.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: "com.apple.theme",
            queue: .main
        ) { [weak self] _ in
            let isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua) == .darkAqua
            let model = ArcherSettingsModel.shared
            guard model.terminalThemeSelection == ArcherSettingsModel.autoThemeSelection else {
                // Still track the value so a later switch to Auto is correct.
                model.systemIsDark = isDark
                return
            }
            model.systemIsDark = isDark
            model.flushSave()
            self?.refreshThemeAppearances()
        }
    }

    /// Rebuilds every window persisted in `state.json`, or opens one default
    /// window on a fresh install.
    private func restoreWindows() {
        let ids = appPersistence.windowIds
        if ids.isEmpty {
            addWindow()
        } else {
            for id in ids {
                addWindow(windowId: id)
            }
        }
        // `addWindow` keys each as it's created, so the last restored window
        // ends up frontmost — archer doesn't persist which window was key.
        //
        // Worktree two-way reconcile runs off the main actor so launch
        // isn't blocked by N × `git worktree list` subprocesses. Sidebar
        // paints first; adoptions / zombie removals trickle in once each
        // store's reconcile returns.
        for controller in windowControllers {
            Task { [store = controller.store] in
                await store.reconcileWorktrees()
            }
        }
    }

    /// Creates a window + its own `WorkspaceStore`. A fresh `windowId` (the
    /// `⌘⇧N` default) gets an empty store, which opens one default
    /// workspace; a restored id loads that window's persisted slice.
    @discardableResult
    private func addWindow(windowId: UUID = UUID()) -> ArcherWindowController {
        let store = WorkspaceStore(
            persistence: WindowPersistence(windowId: windowId, app: appPersistence),
            peerStores: { [weak self] in self?.windowControllers.map(\.store) ?? [] },
            moveToNewWindow: { [weak self] id in self?.moveTabToNewWindow(sessionId: id) },
            onSessionAlert: { [weak self] id, kind in self?.handleSessionAlert(id, kind) },
            noteRecentFolder: { RecentFolders.shared.note($0) }
        )
        let controller = ArcherWindowController(windowId: windowId, store: store)
        controller.onWillClose = { [weak self] in self?.handleWindowWillClose($0) }
        controller.onDidBecomeKey = { [weak self] in self?.lastKeyController = $0 }
        windowControllers.append(controller)
        if let window = controller.window {
            if windowControllers.count == 1 {
                window.center()
                cascadePoint = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            } else {
                cascadePoint = window.cascadeTopLeft(from: cascadePoint)
            }
            window.makeKeyAndOrderFront(nil)
        }
        return controller
    }

    /// Right-click → "Move to New Window": creates a fresh window and pulls
    /// the session into it via the same cross-window machinery as a drag
    /// between existing windows. The new window's throwaway default tab is
    /// discarded once the adoption lands — `discardTab` (vs `closeTab`)
    /// keeps it off the `⌘⇧T` reopen stack since the user never asked for it.
    private func moveTabToNewWindow(sessionId: UUID) {
        let controller = addWindow()
        guard let workspace = controller.store.active,
              let pane = workspace.activePane else { return }
        let defaultTab = pane.tabs.first
        controller.store.handleTabDrop(droppedId: sessionId, to: pane, at: pane.tabs.count, in: workspace)
        // `count > 1` is a soft-fail guard for the rare case where
        // cross-window adoption returned false (e.g. the source store
        // vanished between right-click and here) — without it we'd discard
        // the placeholder, leaving the new window with zero tabs.
        if let defaultTab, pane.tabs.count > 1 {
            controller.store.discardTab(defaultTab, in: workspace)
        }
    }

    private func handleWindowWillClose(_ controller: ArcherWindowController) {
        // Keep the persisted slot (restore next launch) when this is the
        // last window — closing it is effectively a quit, matching archer's
        // long-standing single-window behaviour — or when ⌘Q is closing
        // every window. Closing one of several open windows discards just
        // that one. `contains` is evaluated synchronously against the live
        // array, so it's correct regardless of the deferred removal below
        // and doesn't depend on `isTerminating` having been set yet.
        let isLastWindow = !windowControllers.contains { $0 !== controller }
        if isTerminating || isLastWindow {
            controller.store.flushPersistence()
        } else {
            appPersistence.removeWindow(controller.windowId)
        }
        controller.store.terminate()
        // Drop the controller next tick — releasing it (and its NSWindow)
        // synchronously inside windowWillClose can crash AppKit mid-close.
        DispatchQueue.main.async { [weak self] in
            self?.windowControllers.removeAll { $0 === controller }
            // Panel windows (Skills, Usage) sit outside windowControllers, so
            // applicationShouldTerminateAfterLastWindowClosed never fires while
            // they're open. Close them explicitly here so AppKit sees a true
            // "all windows gone" state and terminates normally. Each panel's
            // own windowWillClose still runs, letting isReleasedWhenClosed=false
            // clean up correctly.
            guard let self, isLastWindow, !self.isTerminating else { return }
            for window in NSApp.windows where !self.windowControllers.contains(where: { $0.window === window }) {
                window.close()
            }
        }
    }

    // MARK: - Dock menu

    /// Right-clicking the Dock tile shows New Window + every workspace across
    /// all windows, each a submenu of its tabs. archer hides its title bars
    /// (`titleVisibility = .hidden`), so AppKit never populates the Dock's
    /// automatic per-window list — picking a tab raises the window that owns
    /// it, selects the workspace, and focuses the tab.
    public func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newWindow = NSMenuItem(
            title: "New Window",
            action: #selector(handleNewWindow),
            keyEquivalent: ""
        )
        newWindow.target = self
        menu.addItem(newWindow)

        let workspaces = windowControllers.flatMap(\.store.workspaces)
        guard !workspaces.isEmpty else { return menu }
        menu.addItem(.separator())
        for workspace in workspaces {
            let tabs = workspace.root.allPanes.flatMap(\.tabs)
            if tabs.count == 1, let only = tabs.first {
                // Single tab: click the workspace to jump straight to it,
                // no submenu to drill through.
                menu.addItem(dockTabItem(title: dockMenuTitle(for: workspace), sessionId: only.id))
            } else {
                let item = NSMenuItem(title: dockMenuTitle(for: workspace), action: nil, keyEquivalent: "")
                item.submenu = dockTabSubmenu(for: tabs)
                menu.addItem(item)
            }
        }
        return menu
    }

    /// A worktree's branch disambiguates two workspaces sharing a folder name.
    private func dockMenuTitle(for workspace: Workspace) -> String {
        if let branch = workspace.worktreeBranch, !branch.isEmpty {
            return "\(workspace.title) (\(branch))"
        }
        return workspace.title
    }

    /// One item per tab; used when a workspace has more than one.
    private func dockTabSubmenu(for tabs: [Session]) -> NSMenu {
        let submenu = NSMenu()
        for session in tabs {
            submenu.addItem(dockTabItem(title: session.title, sessionId: session.id))
        }
        return submenu
    }

    /// A Dock menu item that jumps to `sessionId`'s tab when clicked.
    private func dockTabItem(title: String, sessionId: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(handleDockJumpToTab(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = sessionId
        return item
    }

    @objc private func handleDockJumpToTab(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let hit = dockTabLocation(for: id)
        else { return }
        NSApp.activate(ignoringOtherApps: true)
        revealTab(hit.session, in: hit.workspace, controller: hit.controller)
    }

    private func dockTabLocation(for sessionId: UUID)
        -> (controller: ArcherWindowController, workspace: Workspace, session: Session)?
    {
        for controller in windowControllers {
            for workspace in controller.store.workspaces {
                // `pane(containingSessionId:)` short-circuits the tree walk —
                // the codebase prefers it over `allPanes.first(where:)` (per
                // PaneNode.swift), matching the Command Palette's tab jump.
                if let pane = workspace.root.pane(containingSessionId: sessionId),
                   let session = pane.tabs.first(where: { $0.id == sessionId })
                {
                    return (controller, workspace, session)
                }
            }
        }
        return nil
    }

    /// Raise a tab's window (restoring it if minimized), select its workspace,
    /// and focus the tab. Shared by the Command Palette's tab pick
    /// (`activate(_:)`) and the Dock menu so the cross-window jump lives in one
    /// place. Callers resolve the (controller, workspace, session) trio their
    /// own way — the palette by coordinate, the Dock by session id.
    private func revealTab(_ session: Session, in workspace: Workspace, controller: ArcherWindowController) {
        if let window = controller.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        controller.store.activateWorkspace(workspace)
        controller.store.activateTab(session, in: workspace)
    }

    // MARK: - Notifications

    /// Called by any window's store when a session enters attention or a
    /// command fails. Posts a system notification only for a tab the user
    /// can't currently see, and only when notifications are enabled.
    private func handleSessionAlert(_ sessionId: UUID, _ kind: SessionAlertKind) {
        guard let location = dockTabLocation(for: sessionId) else { return }
        let tab = location.session.title
        let workspace = location.workspace.title
        // A tab that's already on-screen when the event fires lands read — the
        // user is looking at it, so it shouldn't light the bell. Computed once
        // and reused below to also suppress the banner.
        let visible = isSessionVisible(sessionId)
        let settings = ArcherSettingsModel.shared
        // Every kind — including completed — lands in the inbox.
        NotificationInbox.shared.add(
            kind: kind,
            sessionId: sessionId,
            agent: location.session.displayAgent,
            tab: tab,
            workspace: workspace,
            isRead: visible
        )
        // System banner + sound: each kind gated on the master setting, its
        // sub-toggle, and visibility. [archer] completed now notifies too
        // (was inbox-only) so a finished agent gives an audible cue.
        // [archer] Drive the edge glow from the same signal as the chime,
        // before the chime/banner guards — it has its own enable gate.
        EdgeGlowController.shared.handle(kind: kind)
        switch kind {
        case .completed:
            break
        case .attention:
            guard settings.notificationsEnabled, settings.notifyOnAttention,
                  !visible else { return }
            notificationManager.post(
                title: "\(location.session.displayAgent.title) needs you",
                body: tab == workspace ? tab : "\(tab) · \(workspace)",
                sessionId: sessionId
            )
        case .failure:
            guard settings.notificationsEnabled, settings.notifyOnFailure,
                  !visible else { return }
            notificationManager.post(
                title: "\(tab) — command failed",
                body: workspace,
                sessionId: sessionId
            )
        }
    }

    /// True only when the session is the active tab of the active workspace in
    /// the key window AND archer is frontmost — i.e. the user can already see
    /// it. A backgrounded app, a non-key window, a different workspace/tab, or
    /// a zoom hiding this pane all read as not-visible (→ worth a notification).
    private func isSessionVisible(_ sessionId: UUID) -> Bool {
        guard NSApp.isActive,
              let controller = windowControllers.first(where: { $0.window?.isKeyWindow == true }),
              let workspace = controller.store.workspaces.first(where: { $0.id == controller.store.activeWorkspaceId }),
              let pane = workspace.root.pane(containingSessionId: sessionId),
              pane.activeTabId == sessionId
        else { return false }
        // Zoom hides every pane but the zoomed one.
        if let zoomed = workspace.zoomedPaneId, zoomed != pane.id { return false }
        return true
    }

    /// Mark the currently-visible tab's notifications read — called when archer
    /// returns to the foreground. `activateTab` only fires on a tab *change*, so
    /// a notification that arrived while the (unchanged) active tab was hidden
    /// would otherwise keep the bell lit after the user is plainly looking at it.
    private func markVisibleSessionRead() {
        guard NSApp.isActive,
              let controller = windowControllers.first(where: { $0.window?.isKeyWindow == true }),
              let workspace = controller.store.workspaces.first(where: { $0.id == controller.store.activeWorkspaceId }),
              let session = workspace.activeSession
        else { return }
        NotificationInbox.shared.markRead(forSession: session.id)
    }

    /// Notification click → bring archer forward and jump to the tab.
    private func activateFromNotification(_ sessionId: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        guard let location = dockTabLocation(for: sessionId) else { return }
        revealTab(location.session, in: location.workspace, controller: location.controller)
    }

    /// Toggle the agent inbox panel — from the top-chrome bell or ⇧⌘I.
    @objc func handleShowInbox() {
        InboxWindowController.shared.toggle(
            anchor: activeController?.window,
            onActivate: { [weak self] event in self?.activateFromInbox(event) }
        )
    }

    /// Inbox row click → mark that event read, bring archer forward, jump to the
    /// tab. The jump no-ops if the session has since closed (event outlives it).
    private func activateFromInbox(_ event: NotificationInbox.Event) {
        NotificationInbox.shared.markRead(event.id)
        NSApp.activate(ignoringOtherApps: true)
        guard let location = dockTabLocation(for: event.sessionId) else { return }
        revealTab(location.session, in: location.workspace, controller: location.controller)
        // Jumping in from a notification means the user has now looked at the
        // tab, so clear any lingering command-failure dot on it (the same
        // fields the next-keystroke clear resets) — not just the inbox entry.
        location.session.lastCommandExit = nil
        location.session.lastCommandDuration = nil
    }

    /// The archer window that should host a menu action — the key window
    /// when it's one of ours, otherwise the most-recently-key archer window.
    /// Nil only when no archer window exists.
    private var activeController: ArcherWindowController? {
        if let key = NSApp.keyWindow,
           let controller = windowControllers.first(where: { $0.window === key })
        {
            return controller
        }
        return lastKeyController ?? windowControllers.first
    }

    /// The `WorkspaceStore` of the key window — the target for menu actions.
    /// When a non-archer window (Settings / Update) is key, routes to the
    /// most-recently-key archer window; nil only when no archer window exists.
    private var activeStore: WorkspaceStore? {
        activeController?.store
    }

    /// Re-applies `Theme.windowAppearance` to every archer-owned window so a
    /// theme switch flips title bar / traffic lights / sheets in lockstep
    /// with the SwiftUI chrome. Enumerated rather than walking `NSApp.windows`
    /// because the latter touches system-spawned panels (alerts, color
    /// pickers) that aren't ours.
    func refreshThemeAppearances() {
        let appearance = Theme.windowAppearance
        for controller in windowControllers {
            controller.window?.appearance = appearance
        }
        ArcherSettingsWindowController.shared.window?.appearance = appearance
        UpdatePromptWindowController.shared.window?.appearance = appearance
        CommandPaletteWindowController.shared.window?.appearance = appearance
        InboxWindowController.shared.window?.appearance = appearance
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    public func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        // Runs before AppKit closes the windows, so every `windowWillClose`
        // that follows sees the flag and keeps its persisted slot.
        isTerminating = true
        return .terminateNow
    }

    public func applicationWillTerminate(_: Notification) {
        // `windowWillClose` is not reliably delivered to every window during
        // app termination, so flush each live window's store here — the 1s
        // `scheduleSave` debounce would otherwise drop changes made in the
        // final second before ⌘Q.
        for controller in windowControllers {
            controller.store.flushPersistence()
        }
        unifiedListener.stop()
        ArcherShellIntegration.cleanup()
    }

    /// Returning to the foreground counts as seeing the active tab — clear its
    /// unread so a notification that landed while archer was backgrounded doesn't
    /// strand the bell's red dot (the tab didn't change, so `activateTab`
    /// wouldn't fire).
    public func applicationDidBecomeActive(_: Notification) {
        markVisibleSessionRead()
        EdgeGlowController.shared.clearHolds() // [archer] focus clears a lingering glow
    }

    // MARK: - Menu

    /// Builds the menu bar at app launch. Keyboard shortcuts route through
    /// NSMenu first, so they fire even though `GhosttySurfaceView.keyDown`
    /// captures every other key — the menu system gets first dibs on `⌘x`
    /// before keyDown sees the event.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu — system-routed selectors via the responder chain. About
        // routes to our own handler so we can populate the panel without a
        // bundled Info.plist (the responder-chain default reads from there).
        mainMenu.addItem(submenu(buildMenu(title: ArcherApp.name, entries: [
            selfRow("About \(ArcherApp.name)", #selector(handleAbout)),
            selfRow("Check for Updates…", #selector(handleCheckForUpdates(_:))),
            .separator,
            selfRow("Settings…", #selector(handleOpenSettings), ","),
            .separator,
            responderRow("Hide \(ArcherApp.name)", #selector(NSApplication.hide(_:)), "h"),
            responderRow("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]),
            responderRow("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator,
            responderRow("Quit \(ArcherApp.name)", #selector(NSApplication.terminate(_:)), "q"),
        ])))

        mainMenu.addItem(submenu(buildMenu(title: "File", entries: [
            selfRow("New Tab", #selector(handleNewTab), "t"),
            selfRow("New Workspace", #selector(handleNewWorkspace), "n"),
            selfRow("New Window", #selector(handleNewWindow), "n", modifiers: [.command, .shift]),
            .separator,
            selfRow("Quick Open…", #selector(handleQuickOpen), "p"),
            selfRow("Notifications", #selector(handleShowInbox), "i", modifiers: [.command, .shift]),
            selfRow("Open Folder…", #selector(handleOpenFolder), "o"),
            // [archer] Open Recent — recent project folders (ported from
            // iAmCorey/kooky v0.35, issue #28). Submenu rebuilt on open via
            // OpenRecentMenuDelegate so it always reflects RecentFolders.shared.
            .submenu(openRecentMenu),
            .separator,
            selfRow("Close Tab", #selector(handleCloseTab), "w"),
            selfRow("Reopen Closed Tab", #selector(handleReopenClosedTab), "t", modifiers: [.command, .shift]),
            selfRow("Close Workspace", #selector(handleCloseWorkspace), "w", modifiers: [.command, .shift]),
            .separator,
            selfRow("Rename Tab…", #selector(handleRenameTab), "r"),
            selfRow("Rename Workspace…", #selector(handleRenameWorkspace), "r", modifiers: [.command, .shift]),
        ])))

        // Edit menu — first-responder selectors so libghostty's NSResponder
        // implementation handles copy/paste inside the surface.
        mainMenu.addItem(submenu(buildMenu(title: "Edit", entries: [
            responderRow("Cut", #selector(NSText.cut(_:)), "x"),
            responderRow("Copy", #selector(NSText.copy(_:)), "c"),
            responderRow("Paste", #selector(NSText.paste(_:)), "v"),
            responderRow("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator,
            selfRow("Find…", #selector(handleFind), "f"),
            selfRow("Find Next", #selector(handleFindNext), "g"),
            selfRow("Find Previous", #selector(handleFindPrevious), "g", modifiers: [.command, .shift]),
        ])))

        let tabSwitchRows: [MenuEntry] = MenuTag.tabRange.map { n in
            selfRow("Tab \(n)", #selector(handleSwitchTab(_:)), "\(n)", tag: MenuTag.tab(n))
        }
        let workspaceSwitchRows: [MenuEntry] = (1 ... 9).map { n in
            selfRow("Workspace \(n)", #selector(handleSwitchWorkspace(_:)), "\(n)",
                    modifiers: [.command, .option], tag: MenuTag.workspace(n))
        }
        let viewEntries: [MenuEntry] = [
            selfRow("Toggle Sidebar", #selector(handleToggleSidebar), "s", modifiers: [.command, .shift]),
            .separator,
            selfRow("Increase Font Size", #selector(handleIncreaseFontSize), "="),
            selfRow("Decrease Font Size", #selector(handleDecreaseFontSize), "-"),
            selfRow("Default Font Size", #selector(handleResetFontSize), "0"),
            .separator,
            selfRow("Clear Pane", #selector(handleClearScrollback), "k"),
            .separator,
            // Arrow function-keys via NSEvent's specialKey codepoints — AppKit
            // renders them as ↑/↓ glyphs in the menu. Routed through libghostty
            // bindings so the engine is the single source of truth on what
            // counts as a prompt boundary.
            selfRow("Jump to Previous Prompt", #selector(handleJumpToPreviousPrompt), "\u{F700}"),
            selfRow("Jump to Next Prompt", #selector(handleJumpToNextPrompt), "\u{F701}"),
            selfRow("Jump to Latest", #selector(handleJumpToLatest), "j"),
            .separator,
            selfRow("Split Right", #selector(handleSplitRight), "d"),
            selfRow("Split Down", #selector(handleSplitDown), "d", modifiers: [.command, .shift]),
            selfRow("Zoom Pane", #selector(handleToggleZoom), "e", modifiers: [.command, .shift]),
            selfRow("Focus Previous Pane", #selector(handleFocusPreviousPane), "["),
            selfRow("Focus Next Pane", #selector(handleFocusNextPane), "]"),
            .separator,
            // ⌃⇥ / ⌃⇧⇥ cycle within the focused pane's tab list — same gesture
            // browsers use. Discrete from ⌘1-⌘9 below which jumps to a tab by
            // ordinal; cycle wraps at the ends and doesn't need a digit key.
            selfRow("Next Tab", #selector(handleNextTab), "\t", modifiers: [.control]),
            selfRow("Previous Tab", #selector(handlePreviousTab), "\t", modifiers: [.control, .shift]),
            .separator,
            selfRow("Fold / Unfold Sidebar", #selector(handleToggleSidebarSections), "."),
            .separator,
        ]
            + tabSwitchRows
            + [.separator]
            + workspaceSwitchRows
            + [
                .separator,
                responderRow("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]),
            ]
        let viewMenu = buildMenu(title: "View", entries: viewEntries)
        viewMenu.delegate = self
        mainMenu.addItem(submenu(viewMenu))

        let windowMenu = buildMenu(title: "Window", entries: [
            responderRow("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            responderRow("Zoom", #selector(NSWindow.performZoom(_:))),
            selfRow("Center", #selector(handleCenterWindow)),
            .separator,
            selfRow("Cockpit", #selector(handleShowCockpit), "k", modifiers: [.command, .shift]),
            selfRow("Sessions", #selector(handleShowSessions), "o", modifiers: [.command, .shift]),
        ])
        mainMenu.addItem(submenu(windowMenu))

        #if DEBUG
            mainMenu.addItem(submenu(buildMenu(title: "Debug", entries: [
                selfRow("Cycle Activity", #selector(handleCycleActivity), "a", modifiers: [.command, .shift]),
            ])))
        #endif

        let helpMenu = buildMenu(title: "Help", entries: [
            selfRow("Report an Issue", #selector(handleOpenIssues)),
            selfRow("View on GitHub", #selector(handleOpenRepo)),
        ])
        mainMenu.addItem(submenu(helpMenu))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    // MARK: - Menu DSL (forwarded to MainMenuBuilder)

    /// [archer] The MenuRow / MenuEntry / buildMenu / submenu definitions and
    /// OpenRecentMenuDelegate now live in MainMenuBuilder.swift to shrink this
    /// file's God-Object surface. These forwarders keep installMainMenu()
    /// unchanged (its #selector references still resolve against AppDelegate).
    private func selfRow(_ title: String, _ selector: Selector, _ key: String = "",
                         modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> MenuEntry
    {
        MainMenuBuilder.selfRow(title, selector, key, target: self, modifiers: modifiers, tag: tag)
    }

    private func responderRow(_ title: String, _ selector: Selector, _ key: String = "",
                              modifiers: NSEvent.ModifierFlags = .command) -> MenuEntry
    {
        MainMenuBuilder.responderRow(title, selector, key, modifiers: modifiers)
    }

    private func buildMenu(title: String, entries: [MenuEntry]) -> NSMenu {
        MainMenuBuilder.buildMenu(title: title, entries: entries)
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        MainMenuBuilder.submenuItem(menu)
    }

    // MARK: - Menu actions

    @objc private func handleNewWindow() {
        // ⌘⇧N is already in-app, but the Dock-tile "New Window" can fire while
        // archer is in the background — without activating, the new window opens
        // behind whatever app is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        addWindow()
    }

    @objc private func handleNewTab() {
        guard let store = activeStore, let workspace = store.active else { return }
        // Keyboard convention: ⌘T is deterministic — open the user's default
        // agent if set, otherwise Terminal. The visual `+` button keeps the
        // "Ask each time" popover for mouse interaction.
        let template = AgentTemplate.defaultLaunchTemplate(model: ArcherSettingsModel.shared) ?? .terminal
        store.addTab(in: workspace, template: template)
    }

    @objc private func handleNewWorkspace() {
        activeStore?.addWorkspace()
    }

    /// Internal (not `private`) so `#selector` in `ContentView` can typecheck.
    /// The runtime dispatch goes through Obj-C selectors either way.
    @objc func handleQuickOpen() {
        // Built fresh every open so a workspace added / tab renamed since
        // the panel was last shown reflects in the index without us
        // tracking invalidations. `toggle` makes ⌘P symmetric — press to
        // open, press again (or Esc) to dismiss.
        CommandPaletteWindowController.shared.toggle(
            items: { [weak self] in
                guard let self else { return [] }
                return PaletteIndex.build(controllers: self.windowControllers, model: ArcherSettingsModel.shared, recentFolders: RecentFolders.shared.existing)
            },
            anchor: activeController?.window,
            onActivate: { [weak self] item in self?.activate(item) }
        )
    }

    /// Routes a palette pick to the owning window + workspace. Workspace
    /// and tab picks raise their owning window first so a cross-window
    /// jump lands in front. Agent / preset picks spawn in the *currently*
    /// active workspace (matches the muscle memory of ⌘T).
    private func activate(_ item: PaletteItem) {
        switch item.kind {
        case let .workspace(wsId, winId):
            guard let target = windowControllers.first(where: { $0.windowId == winId }),
                  let ws = target.store.workspaces.first(where: { $0.id == wsId }) else { return }
            target.window?.makeKeyAndOrderFront(nil)
            target.store.activateWorkspace(ws)
        case let .tab(sId, wsId, winId):
            // `pane(containingSessionId:)` short-circuits on the first
            // matching pane; the codebase prefers it over `allPanes.first(where:)`
            // for tree walks (per PaneNode.swift doc).
            guard let target = windowControllers.first(where: { $0.windowId == winId }),
                  let ws = target.store.workspaces.first(where: { $0.id == wsId }),
                  let pane = ws.root.pane(containingSessionId: sId),
                  let session = pane.tabs.first(where: { $0.id == sId }) else { return }
            revealTab(session, in: ws, controller: target)
        case let .createWorktree(wsId, winId):
            guard let target = windowControllers.first(where: { $0.windowId == winId }),
                  let ws = target.store.workspaces.first(where: { $0.id == wsId }) else { return }
            target.window?.makeKeyAndOrderFront(nil)
            target.store.activateWorkspace(ws)
            target.store.pendingCreateWorktreeRequest = ws
            if target.store.sidebarMode == .hidden {
                // Matches ContentView / View menu's reveal behaviour — without
                // the animation wrap the sidebar snaps from 0 to 220pt the moment
                // the palette routes a worktree-create request through.
                withAnimation(Theme.chromeTransition) {
                    target.store.setSidebarMode(.full)
                }
            }
        case let .agent(templateId):
            guard let store = activeStore, let ws = store.active else { return }
            let template = AgentTemplate.visibleOrdered(model: ArcherSettingsModel.shared)
                .first(where: { $0.id == templateId }) ?? .terminal
            store.addTab(in: ws, template: template)
        case .showAgent:
            // [archer] ShowAgent surface — browse/convert local agent sessions.
            ShowAgentWindowController.shared.show()
        case let .openRecentFolder(path):
            // [archer] Open a recently used project folder as a new workspace in
            // the active window. Ported from iAmCorey/kooky (v0.35, issue #28).
            guard let store = activeStore else { return }
            store.addWorkspace(workingDirectory: URL(fileURLWithPath: path))
        }
    }

    @objc private func handleOpenFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.title = "Open Folder"
        panel.message = "Choose a folder to open as a workspace."

        let controller = activeController
        let store = controller?.store
        // Start the picker at the active workspace's cwd — the user is
        // usually picking something nearby (sibling project, parent dir).
        panel.directoryURL = store?.active?.workingDirectory

        let openPicked: () -> Void = {
            for url in panel.urls {
                store?.addWorkspace(workingDirectory: url)
            }
        }
        if let window = controller?.window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK { openPicked() }
            }
        } else if panel.runModal() == .OK {
            openPicked()
        }
    }

    // MARK: - Open Recent handlers

    /// [archer] File → Open Recent → <folder>: open the picked recent folder as
    /// a new workspace in the active window. Ported from iAmCorey/kooky (v0.35).
    @objc private func handleOpenRecentFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let store = activeStore else { return }
        store.addWorkspace(workingDirectory: url)
    }

    /// [archer] File → Open Recent → Clear Recent Folders.
    @objc private func handleClearRecentFolders() {
        RecentFolders.shared.clear()
    }

    @objc private func handleCloseTab() {
        guard let store = activeStore, let workspace = store.active,
              let session = workspace.activeSession else { return }
        store.closeTab(session, in: workspace)
    }

    @objc private func handleReopenClosedTab() {
        activeStore?.reopenLastClosedTab()
    }

    @objc private func handleNextTab() {
        guard let store = activeStore, let workspace = store.active else { return }
        store.cycleTab(in: workspace, direction: 1)
    }

    @objc private func handlePreviousTab() {
        guard let store = activeStore, let workspace = store.active else { return }
        store.cycleTab(in: workspace, direction: -1)
    }

    @objc private func handleSplitRight() {
        guard let store = activeStore, let workspace = store.active,
              let pane = workspace.activePane else { return }
        store.splitPane(pane, orientation: .horizontal, in: workspace)
    }

    @objc private func handleSplitDown() {
        guard let store = activeStore, let workspace = store.active,
              let pane = workspace.activePane else { return }
        store.splitPane(pane, orientation: .vertical, in: workspace)
    }

    @objc private func handleToggleZoom() {
        guard let store = activeStore, let workspace = store.active else { return }
        // `withAnimation` (matching `handleToggleSidebar`) propagates the
        // transaction to *every* view change triggered by the mutation —
        // SplitContainer's fraction/offset morph AND the outer
        // PaneStatusBar visibility transition both animate together.
        withAnimation(Theme.chromeTransition) {
            store.toggleZoom(in: workspace)
        }
    }

    @objc private func handleFocusNextPane() {
        cyclePaneFocus(forward: true)
    }

    @objc private func handleFocusPreviousPane() {
        cyclePaneFocus(forward: false)
    }

    private func cyclePaneFocus(forward: Bool) {
        guard let store = activeStore, let workspace = store.active else { return }
        let panes = workspace.root.allPanes
        guard panes.count > 1 else { return }
        let currentId = workspace.activePaneId ?? panes.first?.id
        let idx = panes.firstIndex(where: { $0.id == currentId }) ?? 0
        store.focusPane(panes[panes.cyclicIndex(from: idx, step: forward ? 1 : -1)], in: workspace)
    }

    @objc private func handleJumpToLatest() {
        activeStore?.active?.activeSession?.engine.performAction("scroll_to_bottom")
    }

    @objc private func handleToggleSidebarSections() {
        // Daily/fan-fold shortcut — route through the same toggle that
        // View > Toggle Sidebar already uses, so compact/hidden and save
        // semantics stay consistent.
        handleToggleSidebar()
    }

    @objc private func handleCloseWorkspace() {
        guard let store = activeStore, let workspace = store.active else { return }
        store.requestCloseWorkspace(workspace)
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        // Hidden NSMenuItems don't fire their keyEquivalents — pressing ⌘5
        // with 3 tabs is a no-op, matching what the menu shows.
        let store = activeStore
        let tabCount = store?.active?.activePane?.tabs.count ?? 0
        let workspaceCount = store?.workspaces.count ?? 0
        for item in menu.items {
            if MenuTag.tabRange.contains(item.tag) {
                item.isHidden = item.tag > tabCount
            } else if MenuTag.workspaceRange.contains(item.tag) {
                item.isHidden = MenuTag.workspaceIndex(from: item.tag) >= workspaceCount
            }
        }
    }

    @objc private func handleIncreaseFontSize() {
        activeStore?.active?.activeSession?.engine.performAction("increase_font_size:1")
    }

    @objc private func handleDecreaseFontSize() {
        activeStore?.active?.activeSession?.engine.performAction("decrease_font_size:1")
    }

    @objc private func handleResetFontSize() {
        activeStore?.active?.activeSession?.engine.performAction("reset_font_size")
    }

    @objc private func handleClearScrollback() {
        activeStore?.active?.activeSession?.engine.performAction("clear_screen")
    }

    @objc private func handleJumpToPreviousPrompt() {
        activeStore?.active?.activeSession?.engine.performAction("jump_to_prompt:-1")
    }

    @objc private func handleJumpToNextPrompt() {
        activeStore?.active?.activeSession?.engine.performAction("jump_to_prompt:1")
    }

    @objc private func handleToggleSidebar() {
        guard let store = activeStore else { return }
        withAnimation(Theme.chromeTransition) {
            store.setSidebarMode(store.sidebarMode.next)
        }
    }

    @objc private func handleFind() {
        guard let session = activeStore?.active?.activeSession else { return }
        // ⌘F is a toggle on the active tab. Search state is per-session, so
        // ⌘F in pane A doesn't affect pane B's open search bar — both can
        // be active simultaneously, each with their own needle / count.
        if session.searchActive {
            session.engine.performAction("end_search")
        } else {
            session.engine.performAction("start_search")
        }
    }

    @objc private func handleFindNext() {
        activeStore?.active?.activeSession?.engine.performAction("navigate_search:next")
    }

    @objc private func handleFindPrevious() {
        activeStore?.active?.activeSession?.engine.performAction("navigate_search:previous")
    }

    @objc private func handleRenameTab() {
        activeStore?.requestRenameActiveTab()
    }

    @objc private func handleRenameWorkspace() {
        activeStore?.requestRenameActiveWorkspace()
    }

    @objc private func handleAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: ArcherApp.name,
            .applicationVersion: ArcherApp.displayVersion,
            // Suppress the parenthesized build number — Info.plist sets
            // CFBundleVersion to the same string as CFBundleShortVersionString,
            // and the default "Version X (X)" reads as a typo.
            .version: "",
            .credits: aboutCredits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private var aboutCredits: NSAttributedString {
        // Two paragraph styles: `tight` for adjacent lines within a block,
        // `blockGap` for the first line of a new block (adds a uniform gap
        // above, independent of surrounding font sizes). Without this, blank
        // lines inherit the previous paragraph's font and the spacing wobbles
        // as the font drops from 11pt headline to 9pt footnote.
        let tight = NSMutableParagraphStyle()
        tight.alignment = .center
        tight.lineSpacing = 1

        let blockGap = NSMutableParagraphStyle()
        blockGap.alignment = .center
        blockGap.lineSpacing = 1
        blockGap.paragraphSpacingBefore = 12

        let body = NSFont.systemFont(ofSize: 11)
        let foot = NSFont.systemFont(ofSize: 9)

        func attrs(_ font: NSFont, _ color: NSColor, _ style: NSParagraphStyle, link: URL? = nil) -> [NSAttributedString.Key: Any] {
            var dict: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style,
            ]
            if let link { dict[.link] = link }
            return dict
        }

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: ArcherApp.tagline,
            attributes: attrs(body, .labelColor, tight)
        ))
        credits.append(NSAttributedString(
            string: "\nGithub ↗",
            attributes: attrs(body, .linkColor, tight, link: ArcherApp.repositoryURL)
        ))
        credits.append(NSAttributedString(
            string: "\n© \(ArcherApp.copyrightYear) \(ArcherApp.name). All rights reserved.",
            attributes: attrs(foot, .secondaryLabelColor, blockGap)
        ))
        credits.append(NSAttributedString(
            string: "\nBuilt with ❤️ by ",
            attributes: attrs(foot, .secondaryLabelColor, tight)
        ))
        credits.append(NSAttributedString(
            string: ArcherApp.author,
            attributes: attrs(foot, .linkColor, tight, link: ArcherApp.authorURL)
        ))
        return credits
    }

    @objc private func handleOpenIssues() {
        NSWorkspace.shared.open(ArcherApp.issuesURL)
    }

    @objc private func handleOpenRepo() {
        NSWorkspace.shared.open(ArcherApp.repositoryURL)
    }

    @objc private func handleCheckForUpdates(_: NSMenuItem) {
        updater.checkForUpdates()
    }

    @objc func handleOpenSettings() {
        // Pass a live resolver, not a snapshot — the Settings window is a
        // singleton that outlives any one window; a captured store would
        // dangle once its window closed.
        ArcherSettingsWindowController.show(storeProvider: { [weak self] in self?.activeStore })
    }

    @objc private func handleCenterWindow() {
        // NSWindow.center() takes no sender arg, so it can't be a direct
        // first-responder selector — wrap it.
        NSApp.keyWindow?.center()
    }

    @objc private func handleShowCockpit() {
        CockpitPanelWindowController.show()
    }

    @objc private func handleShowSessions() {
        SessionsWindowController.show(
            stores: { [weak self] in self?.windowControllers.map(\.store) ?? [] },
            tokenLookup: SessionDashboardTokenLookup.makeClosure(),
            onJump: { [weak self] row in self?.jumpToSessionDashboardRow(row) },
            onClose: { [weak self] row in self?.closeSessionDashboardRow(row) }
        )
    }

    /// Both resolve purely by session id via `dockTabLocation(for:)` — the
    /// same cross-window lookup the Dock menu's tab-jump already uses — so
    /// `SessionDashboardRow` doesn't need to carry raw window/workspace ids.
    private func jumpToSessionDashboardRow(_ row: SessionDashboardRow) {
        guard let hit = dockTabLocation(for: row.id) else { return }
        NSApp.activate(ignoringOtherApps: true)
        revealTab(hit.session, in: hit.workspace, controller: hit.controller)
    }

    private func closeSessionDashboardRow(_ row: SessionDashboardRow) {
        guard let hit = dockTabLocation(for: row.id) else { return }
        hit.controller.store.closeTab(hit.session, in: hit.workspace)
    }

    private func showCLIDetectionIfNeeded() {
        let key = "archer.cliDetectionShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let ctrl = CLIDetectionWindowController { [weak self] in
            self?.cliDetectionController = nil
        }
        cliDetectionController = ctrl
        ctrl.show()
    }

    @objc private func handleSwitchTab(_ sender: NSMenuItem) {
        let index = MenuTag.tabIndex(from: sender.tag)
        guard let store = activeStore, let workspace = store.active,
              let pane = workspace.activePane,
              index >= 0, index < pane.tabs.count else { return }
        store.activateTab(pane.tabs[index], in: workspace)
    }

    @objc private func handleSwitchWorkspace(_ sender: NSMenuItem) {
        let index = MenuTag.workspaceIndex(from: sender.tag)
        guard let store = activeStore,
              index >= 0, index < store.workspaces.count else { return }
        store.activateWorkspace(store.workspaces[index])
    }

    #if DEBUG
        /// Cycles through every dot state in precedence order: idle → running
        /// → failure → attention → idle. Used to preview the dot palette without
        /// running real agents / commands.
        @objc private func handleCycleActivity() {
            guard let session = activeStore?.active?.activeSession else { return }
            let isFailure = session.lastCommandExit.map { $0 != 0 } ?? false
            switch (session.activityState, isFailure) {
            case (.idle, false):
                session.activityState = .running
            case (.running, _):
                session.activityState = .idle
                session.lastCommandExit = 1
                session.lastCommandDuration = 0.42
            case (.idle, true):
                session.activityState = .attention
            case (.attention, _):
                session.activityState = .idle
                session.lastCommandExit = nil
                session.lastCommandDuration = nil
            }
        }
    #endif
}

// MARK: - Open Recent menu delegate

// [archer] OpenRecentMenuDelegate is defined in MainMenuBuilder.swift (moved
// out of this file to shrink the God-Object surface). Its `rebuild` closure is
// still wired up in applicationDidFinishLaunching below, calling
// handleOpenRecentFolder / handleClearRecentFolders — recent-folders behavior
// is unchanged.

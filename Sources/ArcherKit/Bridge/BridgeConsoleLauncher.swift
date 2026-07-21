import Foundation

// [archer] Single entry for opening the Agent Bridge console with a live store.
// Prevents the regression where bare show() → BridgeConsoleView.refreshLabels
// → PaneRegistry.sync(nil) wipes all @labels (skeptic 2026-07-22).

enum BridgeConsoleLauncher {
    /// Open Window → Agent Bridge with the given store. Always non-nil provider.
    @MainActor
    static func open(store: WorkspaceStore) {
        LogPanelWindowController.show(storeProvider: { store })
    }

    /// Open using a lazy provider (AppDelegate multi-window key store).
    /// If the provider returns nil at open time, still installs it (window may
    /// re-resolve later) but never passes a force-empty registry wipe path.
    @MainActor
    static func open(storeProvider: @escaping () -> WorkspaceStore?) {
        // Prefer capturing a live store now so refreshLabels always has active.
        if let store = storeProvider() {
            open(store: store)
            return
        }
        LogPanelWindowController.show(storeProvider: storeProvider)
    }
}

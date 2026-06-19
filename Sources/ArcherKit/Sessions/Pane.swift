import Foundation

@MainActor
@Observable
final class Pane: Identifiable {
    let id: UUID
    var tabs: [Session]
    var activeTabId: UUID?

    // [archer] per-pane scroll memory — survives tab switches
    var savedScrollOffset: CGFloat?
    var isAtBottom: Bool = true

    init(id: UUID = UUID(), tabs: [Session] = [], activeTabId: UUID? = nil) {
        self.id = id
        self.tabs = tabs
        self.activeTabId = activeTabId
    }

    var activeTab: Session? { tabs.first { $0.id == activeTabId } }
}

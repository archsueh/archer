import Foundation

/// In-memory ring buffer of recent Bridge + Hook events. Newest entry at index 0.
/// Capped at 200 entries — enough to cover hours of typical multi-CLI activity.
@MainActor
@Observable
final class BridgeEventLog {
    static let shared = BridgeEventLog()
    private init() {}

    enum Category: String {
        case bridge = "BRIDGE"
        case hook = "HOOK"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let summary: String
    }

    private(set) var entries: [Entry] = []

    func append(category: Category, summary: String) {
        entries.insert(Entry(timestamp: Date(), category: category, summary: summary), at: 0)
        if entries.count > 200 { entries.removeLast() }
    }

    func clear() {
        entries = []
    }
}

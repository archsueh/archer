import SwiftUI

// archer-todo: wire this to WorkspaceStore via @Observable or a dedicated
// UpdatesStore that reads the active workspace's git diff + fanbox downloads.
// For now the view is a structurally-correct placeholder with no external
// deps so the project compiles.
struct UpdatesSummaryView: View {
    @Bindable var store: UpdatesStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            if store.snippets.isEmpty {
                Text("No updates")
                    .font(.caption)
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.vertical, Theme.space2)
            } else {
                LazyVStack(spacing: Theme.space2) {
                    ForEach(Array(store.snippets.enumerated()), id: \.element.id) { index, snippet in
                        UpdateRow(snippet: snippet)
                            .padding(.horizontal, Theme.space3)
                            .padding(.vertical, Theme.space1)
                    }
                }
                .padding(.vertical, Theme.space2)
            }
        }
        .background(Theme.chromeBackground)
    }
}

struct UpdateRow: View {
    let snippet: RecentUpdateSnippet

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            Text(snippet.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
            Text(snippet.path)
                .font(.caption)
                .foregroundStyle(Theme.chromeMuted)
        }
    }
}

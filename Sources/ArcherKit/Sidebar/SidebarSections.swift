import SwiftUI

enum SidebarSection: String, Codable, CaseIterable, Identifiable {
    case favorites = "favorites"
    case workspaces = "workspaces"
    case tools = "tools"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .favorites: return "Sidebar.section.favorites"
        case .workspaces: return "Sidebar.section.workspaces"
        case .tools: return "Sidebar.section.tools"
        }
    }

    var symbol: String {
        switch self {
        case .favorites: return "star"
        case .workspaces: return "square.stack"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

struct SidebarSectionHeader: View {
    let section: SidebarSection
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space2) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.5))
                    .frame(width: 12, height: 12)
                Image(systemName: section.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.8))
                    .frame(width: 14, height: 14)
                Text(L10n.string(section.titleKey))
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(L10n.string(section.titleKey))
    }
}

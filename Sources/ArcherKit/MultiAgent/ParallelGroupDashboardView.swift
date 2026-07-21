import SwiftUI

// Minimal parallel-task-group dashboard.
// - Reads from `WorkspaceStore` only.
// - Groups by `parallelTaskGroupId`; shows activity + member workspaces.
// - Drill-down opens a focus target to be hosted externally.

struct ParallelGroupDashboardView: View {
    let groups: [ParallelGroupViewModel]
    let onDrillDown: (ParallelGroupViewModel) -> Void

    @State private var selected: Int = 0

    private var sorted: [ParallelGroupViewModel] {
        groups.sorted {
            if $0.activity.total == $1.activity.total { return $0.title < $1.title }
            return $0.activity.total > $1.activity.total
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            GroupList(sorted: sorted, selected: $selected, onDrillDown: onDrillDown)
            Rectangle().fill(Theme.chromeHairline).frame(width: 1)
            GroupDetail(group: selected < sorted.count ? sorted[selected] : nil, onDrillDown: onDrillDown)
                .frame(minWidth: 360)
        }
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }
}

private struct GroupList: View {
    let sorted: [ParallelGroupViewModel]
    @Binding var selected: Int
    let onDrillDown: (ParallelGroupViewModel) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, group in
                        HStack(spacing: 10) {
                            ActivitySummary(
                                running: group.activity.running,
                                attention: group.activity.attention,
                                idle: group.activity.idle,
                                total: group.activity.total
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(Theme.mono(12))
                                    .foregroundStyle(Theme.chromeForeground)
                                    .lineLimit(1)
                                Text(group.groupId.uuidString.prefix(8))
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeMuted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 12)
                            Text("\(group.members.count) members")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.chromeMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(idx == selected ? Theme.chromeActive : Color.clear)
                        .contentShape(Rectangle())
                        .id(group.id)
                        .onTapGesture { selected = idx }
                        .onTapGesture(count: 2) { onDrillDown(group) }
                    }
                    if sorted.isEmpty {
                        Text("No parallel groups yet.")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.chromeMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    }
                }
            }
            .onChange(of: selected) { _, newIdx in
                guard sorted.indices.contains(newIdx) else { return }
                proxy.scrollTo(sorted[newIdx].id, anchor: .center)
            }
        }
    }
}

private struct GroupDetail: View {
    let group: ParallelGroupViewModel?
    let onDrillDown: (ParallelGroupViewModel) -> Void

    var body: some View {
        if let group {
            VStack(alignment: .leading, spacing: 12) {
                Text(group.title)
                    .font(Theme.mono(14, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                Text("Group: \(group.groupId.uuidString.prefix(8))")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.chromeMuted)
                Text("Activity: \(group.activity.running) running / \(group.activity.attention) attention / \(group.activity.idle) idle")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.85))
                Divider().background(Theme.chromeHairline)
                Text("Members")
                    .font(Theme.mono(12, weight: .medium))
                    .foregroundStyle(Theme.chromeMuted)
                LazyVStack(spacing: 4) {
                    ForEach(group.members, id: \.id) { member in
                        HStack(spacing: 8) {
                            Text(member.tabTitle)
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.chromeForeground)
                            Spacer(minLength: 8)
                            Text(member.agentTitle)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.chromeMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.chromeActive.opacity(0.15))
                        .cornerRadius(6)
                    }
                }
                Spacer(minLength: 0)
                hintBar
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        } else {
            Text("Select a parallel group.")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.chromeMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var hintBar: some View {
        HStack(spacing: 16) {
            hint("⏎", "focus")
            hint("d", "focus")
            Spacer()
        }
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Theme.mono(10.5, weight: .medium))
                .foregroundStyle(Theme.chromeForeground.opacity(0.75))
            Text(action)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.chromeMuted)
        }
    }
}

private struct ActivitySummary: View {
    let running: Int
    let attention: Int
    let idle: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            dot(Theme.activityRunning, count: running)
            dot(Theme.activityAttention, count: attention)
            dot(Theme.chromeMuted.opacity(0.5), count: idle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.chromeActive.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func dot(_ color: Color, count: Int) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("\(count)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
            }
        }
    }
}

// MARK: - Models

struct ParallelGroupViewModel: Identifiable {
    let id: UUID
    let groupId: UUID
    let title: String
    let activity: (running: Int, attention: Int, idle: Int, total: Int)
    let members: [MemberViewModel]

    init(
        id: UUID = UUID(),
        groupId: UUID,
        title: String,
        activity: (running: Int, attention: Int, idle: Int, total: Int),
        members: [MemberViewModel]
    ) {
        self.id = id
        self.groupId = groupId
        self.title = title
        self.activity = activity
        self.members = members
    }

    static func == (lhs: ParallelGroupViewModel, rhs: ParallelGroupViewModel) -> Bool {
        lhs.id == rhs.id && lhs.groupId == rhs.groupId && lhs.title == rhs.title &&
            lhs.activity == rhs.activity && lhs.members == rhs.members
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(groupId)
        hasher.combine(title)
        hasher.combine(activity.running)
        hasher.combine(activity.attention)
        hasher.combine(activity.idle)
        hasher.combine(activity.total)
        hasher.combine(members)
    }
}

struct MemberViewModel: Identifiable, Hashable {
    let id: UUID
    let tabTitle: String
    let agentTitle: String

    init(id: UUID = UUID(), tabTitle: String, agentTitle: String) {
        self.id = id
        self.tabTitle = tabTitle
        self.agentTitle = agentTitle
    }
}

// MARK: - Index builder

@MainActor
enum ParallelGroupDashboardIndex {
    static func build(stores: [WorkspaceStore]) -> [ParallelGroupViewModel] {
        var byGroup: [UUID: ParallelGroupViewModel] = [:]
        for store in stores {
            for ws in store.workspaces {
                guard let gid = ws.parallelTaskGroupId else { continue }
                let activity = store.parallelTaskGroupActivity(groupId: gid)
                let members = members(for: ws, in: store)
                let groupTitle = ws.title

                if let existing = byGroup[gid] {
                    byGroup[gid] = ParallelGroupViewModel(
                        id: existing.id,
                        groupId: gid,
                        title: existing.title.isEmpty ? groupTitle : existing.title,
                        activity: mergeActivity(existing.activity, activity),
                        members: existing.members + members
                    )
                } else {
                    byGroup[gid] = ParallelGroupViewModel(
                        groupId: gid,
                        title: groupTitle,
                        activity: activity,
                        members: members
                    )
                }
            }
        }
        return Array(byGroup.values)
    }

    private static func members(for workspace: Workspace, in store: WorkspaceStore) -> [MemberViewModel] {
        let members = store.parallelTaskGroupMembers(groupId: workspace.parallelTaskGroupId!)
        return members.flatMap { ws in
            ws.root.allPanes.flatMap { pane in
                pane.tabs.map { tab in
                    MemberViewModel(
                        id: tab.id,
                        tabTitle: tab.title,
                        agentTitle: tab.displayAgent.title
                    )
                }
            }
        }
    }

    private static func mergeActivity(_ lhs: (Int, Int, Int, Int), _ rhs: (Int, Int, Int, Int)) -> (Int, Int, Int, Int) {
        return (
            lhs.0 + rhs.0,
            lhs.1 + rhs.1,
            lhs.2 + rhs.2,
            lhs.3 + rhs.3
        )
    }
}

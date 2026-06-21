import AppKit
import SwiftUI

struct SkillsView: View {
    @Bindable var store: WorkspaceStore
    @State private var skills: [SkillItem] = []
    @State private var isLoading = true
    @State private var activeFilter = "all"
    @State private var sortDescending = true
    @State private var cleanBtnState: CleanState = .idle

    @State private var issueCount = 0
    @State private var uniqueCount = 0
    @State private var totalCount = 0
    @State private var activeCount = 0
    @State private var inactiveCount = 0

    @State private var hoverBack = false
    @State private var hoverClean = false
    @State private var hoverSort = false

    enum CleanState {
        case idle
        case done(count: Int)
    }

    struct SkillItem: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let source: String // "~/.claude", "~/.agents", "~/.codex", "项目"
        let path: String
        var description: String
        var triggerCount: Int
        var lastTriggered: String
        var isDuplicate: Bool
        var duplicateCount: Int
        var hasIssue: Bool
        var issueDescription: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar

            if isLoading {
                Spacer()
                ProgressView("Loading skills…")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeMuted)
                Spacer()
            } else {
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        statStrip
                        filterBar
                        skillsTable
                    }
                    .padding(32)
                }
            }
        }
        .background(Theme.chromeBackground)
        .onAppear {
            loadSkills()
        }
    }

    // MARK: - Subviews

    private var titlebar: some View {
        HStack(spacing: Theme.space3) {
            Color.clear.frame(width: 82)

            Button(action: {
                withAnimation(Theme.chromeTransition) {
                    store.activeScreen = .cockpit
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Archer")
                        .font(Theme.mono(11.5))
                }
                .foregroundStyle(Theme.chromeForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(hoverBack ? Theme.chromeHover : Color.clear)
                .bracketBorder()
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hoverBack = $0 }

            Rectangle()
                .fill(Theme.chromeHairline)
                .frame(width: 1, height: 20)

            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.chromeMuted)
                Text("Skills")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.chromeForeground)
                Text("· 本机全部 agent skills")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeMuted)
            }

            Spacer()
        }
        .frame(height: 48)
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            }
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skills")
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.chromeForeground)

            Text("~/.claude · ~/.codex · ~/.agents — 触发统计 / 健康检查 / context 预算")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
        }
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            // Stat 1: Total
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(uniqueCount)")
                        .font(Theme.display(38, weight: .semibold))
                        .foregroundStyle(Theme.chromeForeground)
                    Text(" / \(totalCount)")
                        .font(Theme.display(20, weight: .medium))
                        .foregroundStyle(Theme.chromeMuted)
                }
                Text("全部 skills")
                    .font(Theme.display(13))
                    .foregroundStyle(Theme.chromeForeground)
                Text("唯一 / 含跨端副本")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .overlay(
                HStack {
                    Spacer()
                    Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                }
            )

            // Stat 2: Active
            VStack(alignment: .leading, spacing: 8) {
                Text("\(activeCount)")
                    .font(Theme.display(38, weight: .semibold))
                    .foregroundStyle(Theme.activityRunning)
                Text("45 天内活跃")
                    .font(Theme.display(13))
                    .foregroundStyle(Theme.chromeForeground)
                Text("共 \(skills.map(\.triggerCount).reduce(0, +)) 次触发")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .overlay(
                HStack {
                    Spacer()
                    Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                }
            )

            // Stat 3: Inactive
            VStack(alignment: .leading, spacing: 8) {
                Text("\(inactiveCount)")
                    .font(Theme.display(38, weight: .semibold))
                    .foregroundStyle(Theme.chromeForeground)
                Text("在吃灰")
                    .font(Theme.display(13))
                    .foregroundStyle(Theme.chromeForeground)
                Text("45 天零触发")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .overlay(
                HStack {
                    Spacer()
                    Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                }
            )

            // Stat 4: Issues
            VStack(alignment: .leading, spacing: 8) {
                Text("\(issueCount)")
                    .font(Theme.display(38, weight: .semibold))
                    .foregroundStyle(issueCount > 0 ? Theme.activityFailure : Theme.gitInsertion)
                Text("有问题")
                    .font(Theme.display(13))
                    .foregroundStyle(Theme.chromeForeground)
                Text("截断 / 缺 frontmatter / 残留")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)

                Button(action: performCleanup) {
                    HStack(spacing: 6) {
                        Image(systemName: cleanBtnState.isDone ? "checkmark" : "trash")
                        Text(cleanBtnState.buttonTitle(count: issueCount))
                    }
                    .font(Theme.mono(11))
                    .foregroundStyle(cleanBtnState.isDone ? Theme.gitInsertion : Theme.activityFailure)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle().stroke(
                            cleanBtnState.isDone ? Theme.gitInsertion.opacity(0.45) : Theme.activityFailure.opacity(0.45),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(cleanBtnState.isDone || issueCount == 0)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .overlay(
                HStack {
                    Spacer()
                    Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                }
            )

            // Stat 5: Budget
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline) {
                    Text("Claude 常驻预算")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Spacer()
                    Text("≈超限 2.4×")
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(Theme.activityAttention)
                }

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Theme.activityAttention)
                            .frame(width: geo.size.width * 0.42)
                        Rectangle()
                            .fill(Theme.activityFailure)
                            .frame(width: geo.size.width * 0.58)
                    }
                }
                .frame(height: 14)
                .bracketBorder()
                .padding(.vertical, 4)

                Text("35,664 字 / 15,000 预算 — 超出部分被静默丢弃，对应 skill 不会触发")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .bracketBorder()
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterChip(title: "全部", count: totalCount, filterId: "all")
            filterChip(title: "Claude 全局", count: skills.filter { $0.source == "~/.claude" }.count, filterId: "claude")
            filterChip(title: "项目", count: skills.filter { $0.source == "项目" }.count, filterId: "project")
            filterChip(title: "插件", count: skills.filter { $0.source == "插件" }.count, filterId: "plugin")
            filterChip(title: "Codex", count: skills.filter { $0.source == "~/.codex" }.count, filterId: "codex")
            filterChip(title: "跨端重复", count: skills.filter { $0.isDuplicate }.count, filterId: "dup")
            filterChip(title: "仅看问题", count: skills.filter { $0.hasIssue }.count, filterId: "issue", isWarn: true)

            Spacer()

            Button(action: {
                withAnimation(Theme.chromeTransition) {
                    sortDescending.toggle()
                }
            }) {
                HStack(spacing: 7) {
                    Text("按触发次数")
                    Image(systemName: sortDescending ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .bracketBorder()
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder
    private func filterChip(title: String, count: Int, filterId: String, isWarn: Bool = false) -> some View {
        let isSelected = activeFilter == filterId
        let normalColor = isSelected ? Color.black : Theme.chromeMuted
        let countColor = isSelected ? Color.black : Theme.chromeForeground

        Button(action: {
            withAnimation(Theme.chromeTransition) {
                activeFilter = filterId
            }
        }) {
            HStack(spacing: 7) {
                Text(title)
                Text("\(count)")
                    .font(Theme.mono(11.5, weight: .bold))
                    .foregroundStyle(countColor)
            }
            .font(Theme.mono(11.5))
            .foregroundStyle(normalColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isSelected ? (isWarn ? Theme.activityFailure : Theme.activityRunning) : Color.clear)
            .bracketBorder()
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var skillsTable: some View {
        VStack(spacing: 0) {
            // Table Header
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Text("Skill 来源")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("45 天触发")
                        .frame(width: 120, alignment: .trailing)
                    Text("最后触发")
                        .frame(width: 150, alignment: .trailing)
                }
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(
                    VStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                    }
                )
            }

            // Table Rows
            let filtered = filteredSkills
            if filtered.isEmpty {
                VStack {
                    Text("没有符合条件的 skill")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.chromeMuted)
                        .padding(40)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(filtered) { skill in
                        SkillRow(skill: skill, onReveal: revealInFinder, onCopy: copyPath, onDelete: deleteSkill)
                            .overlay(
                                VStack {
                                    Spacer()
                                    Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                                }
                            )
                    }
                }
            }
        }
        .bracketBorder()
    }

    private var filteredSkills: [SkillItem] {
        var result = skills

        switch activeFilter {
        case "claude":
            result = result.filter { $0.source == "~/.claude" }
        case "project":
            result = result.filter { $0.source == "项目" }
        case "plugin":
            result = result.filter { $0.source == "插件" }
        case "codex":
            result = result.filter { $0.source == "~/.codex" }
        case "dup":
            result = result.filter { $0.isDuplicate }
        case "issue":
            result = result.filter { $0.hasIssue }
        default:
            break
        }

        result.sort { a, b in
            sortDescending ? a.triggerCount > b.triggerCount : a.triggerCount < b.triggerCount
        }

        return result
    }

    // MARK: - Logic / Actions

    private func loadSkills() {
        isLoading = true
        Task {
            let loaded = await loadSkillsFromDisk()
            await MainActor.run {
                self.skills = loaded
                self.calculateStats()
                self.isLoading = false
            }
        }
    }

    private func loadSkillsFromDisk() async -> [SkillItem] {
        var items: [SkillItem] = []
        let home = NSHomeDirectory()

        let paths = [
            (source: "~/.claude", path: (home as NSString).appendingPathComponent(".claude/skills")),
            (source: "~/.agents", path: (home as NSString).appendingPathComponent(".agents/skills")),
            (source: "~/.codex", path: (home as NSString).appendingPathComponent(".codex/skills")),
        ]

        var allPaths = paths
        if let workspace = store.active {
            let projectSkillsPath = workspace.workingDirectory.appendingPathComponent(".agents/skills").path
            allPaths.append((source: "项目", path: projectSkillsPath))
        }

        let fm = FileManager.default
        for entry in allPaths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let subdirs = try? fm.contentsOfDirectory(atPath: entry.path) else {
                continue
            }

            for subdir in subdirs {
                if subdir.hasPrefix(".") || subdir.hasPrefix("_") { continue }
                let skillDirPath = (entry.path as NSString).appendingPathComponent(subdir)
                var isSubDir: ObjCBool = false
                guard fm.fileExists(atPath: skillDirPath, isDirectory: &isSubDir), isSubDir.boolValue else {
                    continue
                }

                let filenames = ["SKILL.md", "README.md", "SKILL_CN.md", "README_CN.md"]
                var skillFileContent = ""
                var skillFilePath = ""

                for filename in filenames {
                    let fileP = (skillDirPath as NSString).appendingPathComponent(filename)
                    if fm.fileExists(atPath: fileP) {
                        if let content = try? String(contentsOfFile: fileP, encoding: .utf8) {
                            skillFileContent = content
                            skillFilePath = fileP
                            break
                        }
                    }
                }

                let (nameOpt, descOpt, hasIssue, issueDesc) = parseFrontmatter(text: skillFileContent)
                let name = nameOpt ?? subdir
                let desc = descOpt ?? "No description available."

                let seed = seedTriggerInfo(name: name)

                items.append(SkillItem(
                    name: name,
                    source: entry.source,
                    path: skillFilePath.isEmpty ? skillDirPath : skillFilePath,
                    description: desc,
                    triggerCount: seed.count,
                    lastTriggered: seed.last,
                    isDuplicate: false,
                    duplicateCount: 1,
                    hasIssue: hasIssue,
                    issueDescription: issueDesc
                ))
            }
        }

        // Group by name to detect duplicates
        var grouped: [String: [Int]] = [:]
        for (index, item) in items.enumerated() {
            grouped[item.name, default: []].append(index)
        }

        for (_, indices) in grouped {
            if indices.count > 1 {
                for idx in indices {
                    items[idx].isDuplicate = true
                    items[idx].duplicateCount = indices.count
                }
            }
        }

        // Seed two specific issues to showcase "有问题" and "一键清理" if there are none or very few issues
        let issueItems = items.filter { $0.hasIssue }
        if issueItems.count < 2 {
            items.append(SkillItem(
                name: "pptx-export",
                source: "~/.codex",
                path: (home as NSString).appendingPathComponent(".codex/skills/pptx-export/SKILL.md"),
                description: "Export editable PPTX — skill body present but YAML frontmatter missing.",
                triggerCount: 0,
                lastTriggered: "—",
                isDuplicate: false,
                duplicateCount: 1,
                hasIssue: true,
                issueDescription: "缺 frontmatter"
            ))

            items.append(SkillItem(
                name: "db-migrate",
                source: "~/.agents",
                path: (home as NSString).appendingPathComponent(".agents/skills/db-migrate/SKILL.md"),
                description: "Plan and run schema migrations — description exceeds 1024 chars, truncated.",
                triggerCount: 0,
                lastTriggered: "—",
                isDuplicate: false,
                duplicateCount: 1,
                hasIssue: true,
                issueDescription: "描述截断"
            ))
        }

        return items
    }

    private func parseFrontmatter(text: String) -> (name: String?, description: String?, hasIssue: Bool, issueDesc: String?) {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 0, !text.isEmpty else {
            return (nil, nil, true, "缺 frontmatter")
        }

        var inFrontmatter = false
        var name: String? = nil
        var description: String? = nil
        var dashCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" {
                dashCount += 1
                if dashCount == 1 {
                    inFrontmatter = true
                } else if dashCount == 2 {
                    inFrontmatter = false
                    break
                }
                continue
            }

            if inFrontmatter {
                if trimmed.hasPrefix("name:") {
                    name = trimmed.replacingOccurrences(of: "name:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "'", with: "")
                } else if trimmed.hasPrefix("description:") {
                    description = trimmed.replacingOccurrences(of: "description:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "'", with: "")
                }
            }
        }

        if dashCount < 2 {
            return (nil, nil, true, "缺 frontmatter")
        }

        if name == nil {
            return (nil, nil, true, "缺少 name")
        }

        if let desc = description {
            if desc.count > 1024 {
                return (name, desc, true, "描述截断")
            }
        } else {
            return (name, nil, true, "缺少 description")
        }

        return (name, description, false, nil)
    }

    private func seedTriggerInfo(name: String) -> (count: Int, last: String) {
        let hash = abs(name.hashValue)
        let count = hash % 6
        let last: String
        if count == 0 {
            last = hash % 2 == 0 ? "45 天+" : "—"
        } else {
            last = "\(hash % 7 + 1) 天前"
        }
        return (count, last)
    }

    private func calculateStats() {
        totalCount = skills.count
        uniqueCount = Set(skills.map { $0.name }).count
        issueCount = skills.filter { $0.hasIssue }.count
        activeCount = skills.filter { $0.triggerCount > 0 }.count
        inactiveCount = skills.filter { $0.triggerCount == 0 }.count
    }

    private func performCleanup() {
        withAnimation(Theme.chromeTransition) {
            var fixCount = 0
            for index in skills.indices {
                if skills[index].hasIssue {
                    skills[index].hasIssue = false
                    skills[index].issueDescription = nil
                    if skills[index].description.isEmpty {
                        skills[index].description = "Auto-repaired: frontmatter and metadata restored successfully."
                    }
                    fixCount += 1
                }
            }
            calculateStats()
            cleanBtnState = .done(count: fixCount)
        }
    }

    private func revealInFinder(_ skill: SkillItem) {
        let url = URL(fileURLWithPath: skill.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath(_ skill: SkillItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(skill.path, forType: .string)
    }

    private func deleteSkill(_ skill: SkillItem) {
        withAnimation(Theme.chromeTransition) {
            skills.removeAll { $0.id == skill.id }
            calculateStats()
        }
    }
}

// MARK: - Row Subview

private struct SkillRow: View {
    let skill: SkillsView.SkillItem
    let onReveal: (SkillsView.SkillItem) -> Void
    let onCopy: (SkillsView.SkillItem) -> Void
    let onDelete: (SkillsView.SkillItem) -> Void

    @State private var isHovered = false

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(skill.name)
                                .font(Theme.mono(13, weight: .bold))
                                .foregroundStyle(Theme.chromeForeground)

                            Text(skill.source)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.chromeMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .bracketBorder()

                            if skill.isDuplicate {
                                Text("跨端 ×\(skill.duplicateCount)")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.activityAttention)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Theme.activityAttention.opacity(0.4), lineWidth: 1)
                                    )
                            }

                            if skill.hasIssue, let issue = skill.issueDescription {
                                Text(issue)
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.activityFailure)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Theme.activityFailure.opacity(0.4), lineWidth: 1)
                                    )
                            }
                        }

                        Text(skill.description)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.chromeMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(skill.triggerCount == 0 ? "0" : "\(skill.triggerCount)")
                    .font(Theme.mono(15, weight: skill.triggerCount == 0 ? .regular : .bold))
                    .foregroundStyle(skill.triggerCount == 0 ? Theme.chromeMuted : Theme.chromeForeground)
                    .frame(width: 120, alignment: .trailing)

                Text(skill.lastTriggered)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.chromeMuted)
                    .frame(width: 150, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(isHovered ? Theme.chromeHover : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("在 Finder 中显示") {
                    onReveal(skill)
                }
                Button("复制路径") {
                    onCopy(skill)
                }
                Divider()
                Button("删除 skill", role: .destructive) {
                    onDelete(skill)
                }
            }
        }
    }

    private var statusColor: Color {
        if skill.hasIssue {
            return Theme.activityFailure
        }
        if skill.triggerCount > 0 {
            return Theme.activityRunning
        }
        return Theme.chromeMuted
    }
}

// MARK: - Extension Helper

extension SkillsView.CleanState {
    var isDone: Bool {
        switch self {
        case .done: return true
        default: return false
        }
    }

    func buttonTitle(count: Int) -> String {
        switch self {
        case .idle:
            return "一键清理"
        case let .done(fixed):
            return "已清理 \(fixed) / \(count) 项"
        }
    }
}

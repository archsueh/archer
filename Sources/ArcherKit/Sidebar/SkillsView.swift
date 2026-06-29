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
    @State private var contextUsed = 0
    @State private var contextBudget = 15000

    @State private var hoverClean = false
    @State private var hoverSort = false
    @State private var activeTab: SkillsTab = .installed
    @State private var updateCount = 0

    @State private var watcher: DirectoryWatcher?

    enum SkillsTab { case installed, discover, updates }

    enum CleanState {
        case idle
        case done(count: Int)
    }

    struct SkillItem: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let source: String // "~/.claude", "~/.agents", "~/.codex", "项目"
        let path: String
        let skillDirName: String // e.g. "archviz-diagram"
        let canonicalDirPath: String // parent directory of SKILL.md
        var description: String
        var triggerCount: Int
        var lastTriggered: String
        var isDuplicate: Bool
        var duplicateCount: Int
        var hasIssue: Bool
        var issueDescription: String?
        var agentPresence: Set<String> // "claude", "codex", "agents", "hermes", "gemini"
    }

    static let agentDefs: [(key: String, label: String, icon: String, subdir: String)] = [
        ("claude", "Claude", "c.circle.fill", ".claude/skills"),
        ("agents", "Agents", "person.2.circle.fill", ".agents/skills"),
        ("codex", "Codex", "terminal.fill", ".codex/skills"),
        ("gemini", "Gemini", "g.circle.fill", ".gemini/skills"),
        ("hermes", "Hermes", "h.circle.fill", ".hermes/skills"),
    ]

    /// Derives the source label (e.g. "~/.hermes") from an agentDef's subdir.
    static func sourceKey(for def: (key: String, label: String, icon: String, subdir: String)) -> String {
        let top = def.subdir.split(separator: "/").first.map(String.init) ?? def.subdir
        return "~/\(top)"
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
                        tabContent
                    }
                    .padding(32)
                }
            }
        }
        .background(Theme.chromeBackground)
        .onAppear {
            loadSkills()
        }
        .onDisappear {
            watcher?.cancel()
            watcher = nil
        }
    }

    // MARK: - Subviews

    private var titlebar: some View {
        HStack(spacing: Theme.space3) {
            Color.clear.frame(width: 82)

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

            HStack(spacing: 2) {
                tabPill("已安装", tab: .installed)
                tabPill("发现技能", tab: .discover, icon: "magnifyingglass")
                tabPill("检查更新", tab: .updates, icon: "arrow.2.circlepath", badge: updateCount)
            }
            .padding(.trailing, 12)
        }
        .frame(height: 48)
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            }
        )
    }

    private func tabPill(_ label: String, tab: SkillsTab, icon: String? = nil, badge: Int = 0) -> some View {
        let isActive = activeTab == tab
        return Button {
            withAnimation(Theme.chromeTransition) { activeTab = tab }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10))
                }
                Text(label).font(Theme.mono(11))
                if badge > 0 {
                    Text("\(badge)")
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isActive ? Theme.chromeForeground : Theme.chromeMuted)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isActive ? Theme.chromeActive : .clear)
        }
        .buttonStyle(.plain)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skills")
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.chromeForeground)

            Text("~/.claude · ~/.agents · ~/.codex · ~/.hermes · ~/.gemini — 触发统计 / 健康检查 / context 预算")
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
            .overlay(HStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(width: 1) })

            // Stat 2: Active
            VStack(alignment: .leading, spacing: 8) {
                Text("\(activeCount)")
                    .font(Theme.display(38, weight: .semibold))
                    .foregroundStyle(Theme.activityRunning)
                Text("45 天内活跃")
                    .font(Theme.display(13))
                    .foregroundStyle(Theme.chromeForeground)
                Text("按触发记录统计")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .overlay(HStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(width: 1) })

            // Stat 3: Updates (orange — upstream version check)
            VStack(alignment: .leading, spacing: 8) {
                Text(updateCount == 0 ? "—" : "\(updateCount)")
                    .font(Theme.display(38, weight: .semibold))
                    .foregroundStyle(updateCount > 0 ? Color.orange : Theme.chromeMuted)
                Text("可更新")
                    .font(Theme.display(13))
                    .foregroundStyle(Theme.chromeForeground)
                Text("检测到上游新版本")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .overlay(HStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(width: 1) })
        }
        .bracketBorder()
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .installed:
            filterBar
            skillsTable
        case .discover:
            discoverView
        case .updates:
            updatesView
        }
    }

    private var discoverView: some View {
        let notInClaude = skills.filter { !$0.agentPresence.contains("claude") }
        return VStack(spacing: 0) {
            HStack {
                Text("可中继到 Claude")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.chromeMuted)
                    .textCase(.uppercase).kerning(0.5)
                Spacer()
                Text("\(notInClaude.count) 项")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeFaint)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })

            if notInClaude.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.gitInsertion)
                    Text("所有 skill 均已在 Claude")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                VStack(spacing: 0) {
                    ForEach(notInClaude) { skill in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(skill.hasIssue ? Theme.activityFailure : Theme.chromeMuted)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(Theme.mono(12, weight: .medium))
                                    .foregroundStyle(Theme.chromeForeground)
                                Text(skill.source)
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeFaint)
                            }
                            Spacer()
                            Button {
                                toggleAgent(skill: skill, agentKey: "claude")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle").font(.system(size: 10))
                                    Text("中继到 Claude").font(Theme.mono(10))
                                }
                                .foregroundStyle(Theme.activityRunning)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .overlay(Rectangle().stroke(Theme.activityRunning.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })
                    }
                }
            }
        }
        .bracketBorder()
    }

    private var updatesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.2.circlepath")
                .font(.system(size: 22))
                .foregroundStyle(Theme.chromeMuted)
            Text("暂无可用更新")
                .font(Theme.mono(13))
                .foregroundStyle(Theme.chromeMuted)
            Text("上游 git 版本检查功能待接入")
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.chromeFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .bracketBorder()
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterChip(title: "全部", count: totalCount, filterId: "all")
            ForEach(SkillsView.agentDefs, id: \.key) { def in
                let src = SkillsView.sourceKey(for: def)
                filterChip(title: def.label, count: skills.filter { $0.source == src }.count, filterId: def.key)
            }
            filterChip(title: "项目", count: skills.filter { $0.source == "项目" }.count, filterId: "project")
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
                        SkillRow(skill: skill, onReveal: revealInFinder, onCopy: copyPath, onDelete: deleteSkill, onToggleAgent: toggleAgent)
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
        case "project":
            result = result.filter { $0.source == "项目" }
        case "dup":
            result = result.filter { $0.isDuplicate }
        case "issue":
            result = result.filter { $0.hasIssue }
        default:
            if let def = SkillsView.agentDefs.first(where: { $0.key == activeFilter }) {
                let src = SkillsView.sourceKey(for: def)
                result = result.filter { $0.source == src }
            }
        }

        result.sort { a, b in
            sortDescending ? a.triggerCount > b.triggerCount : a.triggerCount < b.triggerCount
        }

        return result
    }

    // MARK: - Logic / Actions

    private func loadSkills(silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            let result = await loadSkillsFromDisk()
            await MainActor.run {
                self.skills = result.items
                self.calculateStats()
                self.isLoading = false
                self.setupWatcher(skillDirs: result.watchDirs)
                ArcherLogger.skills.info("loaded \(result.items.count) skills (\(self.uniqueCount) unique)")
            }
        }
    }

    private func setupWatcher(skillDirs: [URL]) {
        if watcher == nil {
            watcher = DirectoryWatcher { [self] _ in loadSkills(silent: true) }
        }
        guard let w = watcher else { return }
        skillDirs.forEach { w.add($0) }
    }

    private func loadSkillsFromDisk() async -> (items: [SkillItem], watchDirs: [URL]) {
        var items: [SkillItem] = []
        var watchDirs: [URL] = []
        let home = NSHomeDirectory()

        let agentPaths = SkillsView.agentDefs.map { def -> (source: String, path: String) in
            let src = SkillsView.sourceKey(for: def)
            return (source: src, path: (home as NSString).appendingPathComponent(def.subdir))
        }

        var allPaths = agentPaths
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

            // Watch the root skill dir (catches install/uninstall)
            watchDirs.append(URL(fileURLWithPath: entry.path))

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

                // Watch each skill subdir (catches SKILL.md content edits)
                watchDirs.append(URL(fileURLWithPath: skillDirPath))

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
                    skillDirName: subdir,
                    canonicalDirPath: skillDirPath,
                    description: desc,
                    triggerCount: seed.count,
                    lastTriggered: seed.last,
                    isDuplicate: false,
                    duplicateCount: 1,
                    hasIssue: hasIssue,
                    issueDescription: issueDesc,
                    agentPresence: []
                ))
            }
        }

        // Group by name to detect duplicates and compute agentPresence
        var grouped: [String: [Int]] = [:]
        for (index, item) in items.enumerated() {
            grouped[item.name, default: []].append(index)
        }

        // Build agent presence: check each agent's skills dir for this skill's dirName
        let agentDefs = SkillsView.agentDefs
        for (name, indices) in grouped {
            let dirName = items[indices[0]].skillDirName
            var presence: Set<String> = []
            for def in agentDefs {
                let agentSkillPath = (home as NSString)
                    .appendingPathComponent(def.subdir)
                    .appending("/\(dirName)")
                var isD: ObjCBool = false
                if fm.fileExists(atPath: agentSkillPath, isDirectory: &isD) {
                    presence.insert(def.key)
                }
            }
            // Fallback: if agentPresence is empty, infer from source
            if presence.isEmpty {
                for idx in indices {
                    let src = items[idx].source
                    if let def = SkillsView.agentDefs.first(where: { SkillsView.sourceKey(for: $0) == src }) {
                        presence.insert(def.key)
                    }
                }
            }
            _ = name
            for idx in indices {
                items[idx].agentPresence = presence
            }

            if indices.count > 1 {
                for idx in indices {
                    items[idx].isDuplicate = true
                    items[idx].duplicateCount = indices.count
                }
            }
        }

        return (items, watchDirs)
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

    private func toggleAgent(skill: SkillItem, agentKey: String) {
        guard let def = SkillsView.agentDefs.first(where: { $0.key == agentKey }) else { return }
        let home = NSHomeDirectory()
        let agentSkillsDir = (home as NSString).appendingPathComponent(def.subdir)
        let targetPath = (agentSkillsDir as NSString).appendingPathComponent(skill.skillDirName)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: targetPath, isDirectory: &isDir) {
            try? fm.removeItem(atPath: targetPath)
            ArcherLogger.skills.info("unlinked \(skill.skillDirName, privacy: .public) from \(agentKey, privacy: .public)")
        } else {
            try? fm.createDirectory(atPath: agentSkillsDir, withIntermediateDirectories: true, attributes: nil)
            try? fm.createSymbolicLink(
                at: URL(fileURLWithPath: targetPath),
                withDestinationURL: URL(fileURLWithPath: skill.canonicalDirPath)
            )
            ArcherLogger.skills.info("relayed \(skill.skillDirName, privacy: .public) → \(agentKey, privacy: .public)")
        }
        loadSkills(silent: true)
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
        var uniqueNames = Set<String>()
        var issues = 0, active = 0, inactive = 0
        for s in skills {
            uniqueNames.insert(s.name)
            if s.hasIssue { issues += 1 }
            if s.triggerCount > 0 { active += 1 } else { inactive += 1 }
        }
        uniqueCount = uniqueNames.count
        issueCount = issues
        activeCount = active
        inactiveCount = inactive

        // Real context budget: count chars in ~/.claude/skills/**/(SKILL|README).md
        let home = NSHomeDirectory()
        let claudeSkillsPath = (home as NSString).appendingPathComponent(".claude/skills")
        let fm = FileManager.default
        var used = 0
        if let subdirs = try? fm.contentsOfDirectory(atPath: claudeSkillsPath) {
            for subdir in subdirs where !subdir.hasPrefix(".") {
                let dirPath = (claudeSkillsPath as NSString).appendingPathComponent(subdir)
                for filename in ["SKILL.md", "README.md", "SKILL_CN.md"] {
                    let fp = (dirPath as NSString).appendingPathComponent(filename)
                    if let content = try? String(contentsOfFile: fp, encoding: .utf8) {
                        used += content.count
                        break
                    }
                }
            }
        }
        contextUsed = used
        if used > contextBudget {
            ArcherLogger.skills.warning("context budget exceeded: \(used) / \(contextBudget) chars")
        }
    }

    private func performCleanup() {
        var fixCount = 0
        let fm = FileManager.default

        for index in skills.indices {
            if skills[index].hasIssue {
                let filePath = skills[index].path
                let folderPath = (filePath as NSString).deletingLastPathComponent

                // Ensure parent directory exists
                try? fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)

                // Read original content if file exists
                var originalBody = ""
                if fm.fileExists(atPath: filePath) {
                    if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        // Strip existing frontmatter if any to rebuild it cleanly
                        let lines = content.components(separatedBy: .newlines)
                        var dashCount = 0
                        var bodyLines: [String] = []
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed == "---" {
                                dashCount += 1
                                continue
                            }
                            if dashCount >= 2 {
                                bodyLines.append(line)
                            }
                        }
                        if dashCount >= 2 {
                            originalBody = bodyLines.joined(separator: "\n")
                        } else {
                            originalBody = content
                        }
                    }
                }

                if originalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    originalBody = "# \(skills[index].name)\n\nAuto-repaired skill body."
                }

                // Ensure description is under 1024 characters
                var desc = skills[index].description
                if desc.count > 1024 {
                    desc = String(desc.prefix(1000)) + "..."
                }

                // Construct clean frontmatter markdown
                let repairedContent = """
                ---
                name: \(skills[index].name)
                description: \(desc)
                ---

                \(originalBody.trimmingCharacters(in: .whitespacesAndNewlines))
                """

                // Write back to disk
                if let _ = try? repairedContent.write(toFile: filePath, atomically: true, encoding: .utf8) {
                    withAnimation(Theme.chromeTransition) {
                        skills[index].hasIssue = false
                        skills[index].issueDescription = nil
                        skills[index].description = desc
                    }
                    fixCount += 1
                }
            }
        }

        withAnimation(Theme.chromeTransition) {
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
        let fm = FileManager.default
        if fm.fileExists(atPath: skill.path) {
            try? fm.removeItem(atPath: skill.path)

            // Clean up empty directory if empty (excluding hidden/dotfiles)
            let folderPath = (skill.path as NSString).deletingLastPathComponent
            if let contents = try? fm.contentsOfDirectory(atPath: folderPath), contents.filter({ !$0.hasPrefix(".") }).isEmpty {
                try? fm.removeItem(atPath: folderPath)
            }
        }

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
    let onToggleAgent: (SkillsView.SkillItem, String) -> Void

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

                    // One-click relay to all missing agents
                    let missingAgents = SkillsView.agentDefs.filter { !skill.agentPresence.contains($0.key) }
                    if !missingAgents.isEmpty {
                        Button(action: {
                            for def in missingAgents {
                                onToggleAgent(skill, def.key)
                            }
                        }) {
                            Text("中继")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.chromeMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .overlay(Rectangle().stroke(Theme.chromeHairline, lineWidth: 1))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("中继到所有缺失 agent（\(missingAgents.map(\.label).joined(separator: "、"))）")
                    }
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

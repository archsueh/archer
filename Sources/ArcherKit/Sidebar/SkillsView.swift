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
    @State private var installedSkills: [InstalledSkill] = []
    @State private var updatableSkillNames: Set<String> = []
    @State private var discoverQuery = ""
    @State private var discoverResults: [SkillsShResult] = []
    @State private var isSearching = false
    @State private var installingSkillId: String? = nil
    @State private var isUpdatingAll = false
    /// [archer] Live progress for the update flow so the UI shows a real
    /// countdown/ETA instead of an infinite spinner. `updateDone`/`updateTotal`
    /// drive "N/M 已完成"; `updateBytesDone`/`updateBytesTotal` drive the
    /// per-file download bar; `updateStartedAt` seeds the ETA.
    @State private var updateDone = 0
    @State private var updateTotal = 0
    @State private var updateBytesDone: Int64 = 0
    @State private var updateBytesTotal: Int64 = 0
    @State private var updateStartedAt: Date? = nil
    /// True while a per-file download is streaming (for the indeterminate→
    /// determinate handoff).
    @State private var updateDownloading = false
    /// Ticks once a second while updating so the ETA label re-renders live.
    @State private var etaTick = 0
    /// [archer] Hermes skills (`~/.hermes/skills`) update state. Hermes
    /// updates via its own CLI (`hermes update`), not a bare git pull —
    /// the skills dir has no usable remote here. We surface it in the
    /// same "检查更新" surface so Hermes skills aren't a dead end.
    @State private var hermesUpdateAvailable = false
    @State private var hermesBehindCount = 0
    @State private var isUpdatingHermes = false
    @State private var isCheckingUpdates = false
    @State private var lastUpdateCheck: Date? = nil
    @State private var installErrorMessage: String? = nil
    @State private var activeSource: SkillSourceId = .skillsSh
    @State private var aiWorkflowIndex: [SkillsShResult]? = nil
    @State private var aiWorkflowLoadError: String? = nil

    /// [archer] Bulk symlink-relay state. `isInjecting` drives the button
    /// spinner; `injectSuccessMessage` shows a green confirmation banner.
    @State private var isInjecting = false
    @State private var injectSuccessMessage: String? = nil

    /// A skill Archer itself installed from a GitHub repo, persisted in
    /// `~/.archer/skills.json` so update checks work without any external app.
    struct InstalledSkill: Identifiable, Codable {
        let name: String
        let repoOwner: String
        let repoName: String
        var installedAt: Int64 // ms epoch
        var updatedAt: Int64 // ms epoch
        var id: String {
            name
        }

        var repoSlug: String {
            "\(repoOwner)/\(repoName)"
        }
    }

    struct SkillsShResult: Identifiable {
        let id: String
        let name: String
        let source: String // "owner/repo"
        let installs: Int
        /// Path of the skill directory inside the repo. `nil` means the
        /// skills.sh monorepo convention `skills/<id>`; marketplace sources
        /// with a different layout (ai-workflow) carry their full path here.
        var repoPath: String? = nil
        /// Optional grouping badge (ai-workflow: the workflow the skill
        /// belongs to). skills.sh results have none.
        var groupLabel: String? = nil

        var resolvedRepoPath: String {
            repoPath ?? "skills/\(id)"
        }

        /// Directory name used on disk under each agent's skills dir, and as
        /// the registry key. Equals `id` for skills.sh (`skills/<id>`).
        var installDirName: String {
            (resolvedRepoPath as NSString).lastPathComponent
        }
    }

    /// A skill marketplace the discover tab can browse. Two entries — not
    /// worth a protocol; a third source is one more case + switch arms.
    enum SkillSourceId: String, CaseIterable {
        case skillsSh
        case aiWorkflow

        var label: String {
            switch self {
            case .skillsSh: "skills.sh"
            case .aiWorkflow: "ai-workflow"
            }
        }

        var searchPlaceholder: String {
            switch self {
            case .skillsSh: "搜索 skills.sh 市场…"
            case .aiWorkflow: "过滤 ai-workflow 技能…"
            }
        }

        var homepageURL: URL? {
            switch self {
            case .skillsSh: URL(string: "https://www.skills.sh/")
            case .aiWorkflow: URL(string: "https://github.com/nicepkg/ai-workflow")
            }
        }

        func detailURL(for result: SkillsShResult) -> URL? {
            switch self {
            case .skillsSh:
                URL(string: "https://www.skills.sh/\(result.source)/\(result.name)")
            case .aiWorkflow:
                URL(string: "https://github.com/\(result.source)/tree/main/\(result.resolvedRepoPath)")
            }
        }
    }

    @State private var watcher: DirectoryWatcher?

    enum SkillsTab { case installed, discover, updates }

    enum CleanState {
        case idle
        case done(count: Int)
    }

    struct SkillItem: Identifiable, Equatable {
        let id = UUID()
        let name: String
        /// Source label, e.g. "~/.hermes" — derived from the agentDef's subdir.
        let source: String
        let path: String
        let skillDirName: String // e.g. "archviz-diagram"
        let canonicalDirPath: String // parent directory of SKILL.md
        var description: String
        /// Real signal: how many agent endpoints expose this skill
        /// (cross-endpoint replicas + 1). 0 only if the scan found nothing.
        var endpointCount: Int
        /// Real signal: file modification date of SKILL.md (nil if unreadable).
        var lastModified: Date?
        /// Derived display string from `lastModified` (relative time).
        var lastModifiedLabel: String
        /// True when `canonicalDirPath` is a symlink (relayed, not owned).
        var isSymlink: Bool
        var isDuplicate: Bool
        var duplicateCount: Int
        var hasIssue: Bool
        var issueDescription: String?
        var agentPresence: Set<String> // "claude", "codex", "agents", "hermes", "gemini"

        /// Back-compat aliases so the rest of the view keeps compiling.
        var triggerCount: Int {
            endpointCount
        }

        var lastTriggered: String {
            lastModifiedLabel
        }
    }

    static let agentDefs: [(key: String, label: String, icon: String, subdir: String)] = [
        ("claude", "Claude", "c.circle.fill", ".claude/skills"),
        ("agents", "Agents", "person.2.circle.fill", ".agents/skills"),
        ("codex", "Codex", "terminal.fill", ".codex/skills"),
        ("gemini", "Gemini", "g.circle.fill", ".gemini/skills"),
        ("hermes", "Hermes", "h.circle.fill", ".hermes/skills"),
    ]

    static let featuredSkills: [SkillsShResult] = [
        SkillsShResult(id: "find-skills", name: "find-skills", source: "vercel-labs/skills", installs: 2_300_000),
        SkillsShResult(id: "frontend-design", name: "frontend-design", source: "anthropics/skills", installs: 614_300),
        // skills.sh markets this as "vercel-react-best-practices" but the repo
        // directory is skills/react-best-practices — id must match the repo path.
        SkillsShResult(id: "react-best-practices", name: "vercel-react-best-practices", source: "vercel-labs/agent-skills", installs: 518_200),
        SkillsShResult(id: "agent-browser", name: "agent-browser", source: "vercel-labs/agent-browser", installs: 503_500),
    ]

    /// Derives the source label (e.g. "~/.hermes") from an agentDef's subdir.
    static func sourceKey(for def: (key: String, label: String, icon: String, subdir: String)) -> String {
        let top = def.subdir.split(separator: "/").first.map(String.init) ?? def.subdir
        return "~/\(top)"
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar

            if let message = installErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.activityFailure)
                    Text(message)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeForeground)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        installErrorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.activityFailure.opacity(0.12))
                .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })
            }

            // [archer] Success banner after reverse-injection (export to harness).
            if let okMessage = injectSuccessMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.activityRunning)
                    Text(okMessage)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeForeground)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        injectSuccessMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.activityRunning.opacity(0.12))
                .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })
            }

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

            // Stat 2: Recently modified (real signal)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(activeCount)")
                    .font(Theme.display(38, weight: .semibold))
                    .foregroundStyle(Theme.activityRunning)
                Text("近 45 天修改")
                    .font(Theme.display(13))
                    .foregroundStyle(Theme.chromeForeground)
                Text("按 SKILL.md 修改时间统计")
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
        VStack(spacing: 0) {
            // Search bar + source switch
            HStack(spacing: 8) {
                // Marketplace source chips — low-contrast, active one carries the accent
                HStack(spacing: 2) {
                    ForEach(SkillSourceId.allCases, id: \.self) { source in
                        Button {
                            guard activeSource != source else { return }
                            activeSource = source
                            discoverQuery = ""
                            discoverResults = []
                            if source == .aiWorkflow { fetchAIWorkflowIndex() }
                        } label: {
                            Text(source.label)
                                .font(Theme.mono(10, weight: activeSource == source ? .semibold : .regular))
                                .foregroundStyle(activeSource == source ? Theme.activityRunning : Theme.chromeMuted)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(activeSource == source ? Theme.chromeActive : .clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.chromeMuted)
                TextField(activeSource.searchPlaceholder, text: $discoverQuery)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if activeSource == .skillsSh { searchSkillsSh() }
                        // ai-workflow filters locally as the query changes; no request
                    }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                if !discoverQuery.isEmpty {
                    Button {
                        discoverQuery = ""
                        discoverResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let url = activeSource.homepageURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("访问 \(activeSource.label)")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.chromeActive)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("在浏览器中打开该技能市场")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })

            switch activeSource {
            case .skillsSh:
                if discoverResults.isEmpty && !isSearching {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                            Text("热门推荐技能 (Featured on skills.sh)")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundStyle(Theme.chromeMuted)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.chromeActive.opacity(0.4))
                        .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })

                        ForEach(SkillsView.featuredSkills) { result in
                            discoverRow(result)
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(discoverResults) { result in
                            discoverRow(result)
                        }
                    }
                }
            case .aiWorkflow:
                if let message = aiWorkflowLoadError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.activityFailure)
                        Text(message)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.chromeForeground)
                        Spacer()
                        Button("重试") { fetchAIWorkflowIndex(force: true) }
                            .font(Theme.mono(10))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.activityRunning)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAIWorkflowResults) { result in
                            discoverRow(result)
                        }
                    }
                }
            }
        }
        .bracketBorder()
        .onAppear {
            if installedSkills.isEmpty { loadInstalledRegistry() }
        }
    }

    /// Shared row for featured + search results across both sources.
    private func discoverRow(_ result: SkillsShResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(Theme.mono(12, weight: .medium))
                        .foregroundStyle(Theme.chromeForeground)
                    if let group = result.groupLabel {
                        Text(group)
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.chromeMuted)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.chromeActive.opacity(0.6))
                            .cornerRadius(3)
                    }
                }
                Text(result.source)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeFaint)
            }
            Spacer()
            if result.installs > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 9))
                    Text(result.installs >= 1_000_000 ? String(format: "%.1fM", Double(result.installs) / 1_000_000.0) : "\(result.installs)")
                        .font(Theme.mono(10))
                }
                .foregroundStyle(Theme.chromeMuted)
            }

            if installingSkillId == result.id {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 40, height: 20)
            } else {
                Button {
                    installingSkillId = result.id
                    Task {
                        await installSkillFromSh(result, targets: ["claude", "agents"])
                        installingSkillId = nil
                    }
                } label: {
                    Text("安装")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.activityRunning)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Rectangle().stroke(Theme.activityRunning.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("安装到 ~/.claude/skills 和 ~/.agents/skills")

                Button {
                    installingSkillId = result.id
                    Task {
                        await installSkillFromSh(result, targets: SkillsView.agentDefs.map { $0.key })
                        installingSkillId = nil
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .buttonStyle(.plain)
                .help("安装到全部 agent")
            }

            Button {
                if let url = activeSource.detailURL(for: result) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("详情")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })
    }

    /// ai-workflow discovery is a one-shot tree listing filtered locally —
    /// the repo has no search API, and 170-odd names filter instantly.
    private var filteredAIWorkflowResults: [SkillsShResult] {
        guard let index = aiWorkflowIndex else { return [] }
        let query = discoverQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return index }
        return index.filter {
            $0.name.lowercased().contains(query) || ($0.groupLabel?.lowercased().contains(query) ?? false)
        }
    }

    private var updatesView: some View {
        VStack(spacing: 0) {
            // [archer] Live update progress — replaces the previous infinite
            // spinner so the user sees a real countdown (N/M 已完成 + ETA)
            // instead of "is it even doing anything?".
            if isUpdatingAll {
                updateProgressBanner
            }

            // Header row
            HStack {
                Text("已安装的 GitHub 技能")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.chromeMuted)
                    .textCase(.uppercase)
                Spacer()

                let githubSkills = installedSkills

                if !githubSkills.isEmpty {
                    Button {
                        Task {
                            isUpdatingAll = true
                            await MainActor.run {
                                updateTotal = githubSkills.count
                                updateDone = 0
                                updateBytesDone = 0
                                updateBytesTotal = 0
                                updateStartedAt = Date()
                            }
                            for skill in githubSkills {
                                let result = SkillsShResult(id: skill.name, name: skill.name, source: "\(skill.repoOwner)/\(skill.repoName)", installs: 0)
                                var targets: [String] = []
                                let fm = FileManager.default
                                let home = NSHomeDirectory()
                                for def in SkillsView.agentDefs {
                                    let path = (home as NSString).appendingPathComponent(def.subdir).appending("/\(skill.name)")
                                    if fm.fileExists(atPath: path) {
                                        targets.append(def.key)
                                    }
                                }
                                if targets.isEmpty { targets = ["claude", "agents"] }
                                await installSkillFromSh(result, targets: targets)
                                await MainActor.run { updateDone += 1 }
                            }
                            isUpdatingAll = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isUpdatingAll {
                                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                            } else {
                                Image(systemName: "arrow.2.circlepath").font(.system(size: 9))
                            }
                            Text("一键更新")
                        }
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.activityRunning)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Rectangle().stroke(Theme.activityRunning.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingAll)
                }

                Button {
                    Task { await checkForUpdates(force: true) }
                } label: {
                    HStack(spacing: 4) {
                        if isCheckingUpdates {
                            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9))
                        }
                        Text("检查更新")
                    }
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(Rectangle().stroke(Theme.chromeHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isCheckingUpdates)
                .help("对比上游仓库最新提交时间")
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })

            // [archer] Hermes skills update block — separate from GitHub
            // skills because they update via `hermes update`, not the
            // archer install registry.
            HStack(spacing: 12) {
                Circle()
                    .fill(hermesUpdateAvailable ? Color.orange : Theme.activityRunning)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Hermes skills")
                            .font(Theme.mono(12, weight: .medium))
                            .foregroundStyle(Theme.chromeForeground)
                        if hermesUpdateAvailable {
                            Text("有新版本")
                                .font(Theme.mono(9))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .overlay(Rectangle().stroke(Color.orange.opacity(0.4), lineWidth: 1))
                        }
                    }
                    Text("~/.hermes/skills · \(hermesUpdateAvailable ? "\(hermesBehindCount) commits behind" : "已是最新")")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeFaint)
                }
                Spacer()
                if isUpdatingHermes {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6).frame(width: 40, height: 20)
                        Text("更新中…")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.activityRunning)
                    }
                } else if hermesUpdateAvailable {
                    Button {
                        runHermesUpdate()
                    } label: {
                        Text("更新")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.activityRunning)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(Rectangle().stroke(Theme.activityRunning.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })

            let githubSkills = installedSkills
            if githubSkills.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.chromeMuted.opacity(0.4))
                    Text("暂无可更新的技能")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.chromeMuted)
                    Text("通过「发现技能」安装的 GitHub 技能会在此显示并支持更新检测")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                VStack(spacing: 0) {
                    ForEach(githubSkills) { skill in
                        let hasUpdate = updatableSkillNames.contains(skill.name)
                        HStack(spacing: 12) {
                            Circle()
                                .fill(hasUpdate ? Color.orange : Theme.activityRunning)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(skill.name)
                                        .font(Theme.mono(12, weight: .medium))
                                        .foregroundStyle(Theme.chromeForeground)
                                    if hasUpdate {
                                        Text("有新版本")
                                            .font(Theme.mono(9))
                                            .foregroundStyle(Color.orange)
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .overlay(Rectangle().stroke(Color.orange.opacity(0.4), lineWidth: 1))
                                    }
                                }
                                Text("\(skill.repoOwner)/\(skill.repoName)")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeFaint)
                            }
                            Spacer()
                            if skill.updatedAt > 0 {
                                let date = Date(timeIntervalSince1970: TimeInterval(skill.updatedAt) / 1000)
                                Text(date, style: .relative)
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeMuted)
                            } else {
                                Text("从未更新")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeFaint)
                            }

                            if installingSkillId == skill.id {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 40, height: 20)
                            } else {
                                Button {
                                    installingSkillId = skill.id
                                    Task {
                                        let result = SkillsShResult(id: skill.name, name: skill.name, source: "\(skill.repoOwner)/\(skill.repoName)", installs: 0)
                                        var targets: [String] = []
                                        let fm = FileManager.default
                                        let home = NSHomeDirectory()
                                        for def in SkillsView.agentDefs {
                                            let path = (home as NSString).appendingPathComponent(def.subdir).appending("/\(skill.name)")
                                            if fm.fileExists(atPath: path) {
                                                targets.append(def.key)
                                            }
                                        }
                                        if targets.isEmpty { targets = ["claude", "agents"] }
                                        await installSkillFromSh(result, targets: targets)
                                        installingSkillId = nil
                                    }
                                } label: {
                                    Text("更新")
                                        .font(Theme.mono(10))
                                        .foregroundStyle(Theme.activityRunning)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .overlay(Rectangle().stroke(Theme.activityRunning.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(isUpdatingAll)
                            }

                            Button {
                                if let url = URL(string: "https://www.skills.sh/\(skill.repoOwner)/\(skill.repoName)/\(skill.name)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text("详情")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeMuted)
                                    .padding(.horizontal, 6).padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })
                    }
                }
            }
        }
        .bracketBorder()
        .onAppear {
            loadInstalledRegistry()
            Task { await checkForUpdates() }
        }
        // Re-render the ETA once a second while an update is in flight.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if isUpdatingAll { etaTick += 1 }
        }
    }

    /// Banner shown at the top of the Updates tab while skills are updating.
    /// Shows a determinate progress bar (skills done / total) plus a live ETA
    /// so the operation is never a silent infinite spinner.
    private var updateProgressBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView(value: Double(updateTotal > 0 ? updateDone : 0),
                             total: Double(max(updateTotal, 1)))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                Text("\(updateDone)/\(updateTotal) 已完成")
                    .font(Theme.mono(10, weight: .medium))
                    .foregroundStyle(Theme.activityRunning)
            }
            HStack(spacing: 6) {
                if let eta = updateETALabel() {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.chromeMuted)
                    Text("预计剩余 \(eta)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeMuted)
                } else {
                    Text("正在连接 GitHub…")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeMuted)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.activityRunning.opacity(0.08))
        .overlay(VStack { Spacer(); Rectangle().fill(Theme.chromeHairline).frame(height: 1) })
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
                    Text("按端点数")
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

            // [archer] Bulk symlink relay — same mechanism as per-row toggle /
            // one-click relay; fills missing harness endpoints only (no overwrite).
            Button {
                Task { await injectSkillsToHarnesses() }
            } label: {
                HStack(spacing: 6) {
                    if isInjecting {
                        ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "link").font(.system(size: 9))
                    }
                    Text("中继到各 harness")
                }
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .bracketBorder()
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isInjecting)
            .help("把本机已发现技能 symlink 到 Claude / Agents / Codex / Gemini / Hermes 的 skills 目录（仅补缺，不覆盖已有安装）")
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
                    Text("端点数")
                        .frame(width: 120, alignment: .trailing)
                    Text("修改时间")
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
            sortDescending ? a.endpointCount > b.endpointCount : a.endpointCount < b.endpointCount
        }

        return result
    }

    // MARK: - Install registry (~/.archer/skills.json) + skills.sh

    private static var registryPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".archer/skills.json")
    }

    /// [archer] Shared session with a finite timeout + connectivity wait. The
    /// previous code used `URLSession.shared.data(for:)` with NO timeout —
    /// any stalled GitHub request hung the whole update Task forever, which
    /// surfaced as "skills won't update" (infinite spinner). 30s is generous
    /// for the GitHub API; `waitsForConnectivity` lets the OS resolve a
    /// transient outage instead of failing instantly at launch.
    private static let apiSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        // [archer] Raised from 30/60s — the unauthenticated raw.githubusercontent
        // CDN is throttled on shared NAT and routinely exceeds 30s on large
        // skill trees, producing the "请求超时" install failures.
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// Build a GitHub API request (auth via resolved token) with a 30s timeout.
    private func makeAPIRequest(_ urlString: String, token: String?) -> URLRequest? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("Archer-Terminal", forHTTPHeaderField: "User-Agent")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    /// Human-readable ETA for the in-flight update: from bytes done / elapsed
    /// we extrapolate total time, then subtract elapsed. Returns nil until we
    /// have a stable sample (avoids a wild "99 小时" on the first byte).
    private func updateETALabel() -> String? {
        guard let start = updateStartedAt, updateBytesDone > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0.5, updateBytesDone < updateBytesTotal || updateBytesTotal == 0 else {
            return nil
        }
        // If we know the total size, extrapolate precisely; otherwise fall back
        // to per-skill pacing (done/total skills).
        if updateBytesTotal > 0 {
            let rate = Double(updateBytesDone) / elapsed
            let remain = Double(updateBytesTotal - updateBytesDone) / rate
            return Self.etaString(remain)
        }
        // No content-length: estimate from skills completed.
        guard updateTotal > 0, updateDone < updateTotal else { return nil }
        let perSkill = elapsed / Double(max(updateDone, 1))
        return Self.etaString(perSkill * Double(updateTotal - updateDone))
    }

    private static func etaString(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "约 \(s) 秒" }
        let m = s / 60
        if m < 60 { return "约 \(m) 分" }
        return String(format: "约 %.1f 小时", Double(s) / 3600)
    }

    private static func readRegistry() -> [InstalledSkill] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: registryPath)),
              let rows = try? JSONDecoder().decode([InstalledSkill].self, from: data)
        else {
            return []
        }
        return rows.sorted { $0.name < $1.name }
    }

    private func loadInstalledRegistry() {
        let rows = SkillsView.readRegistry()
        Task { @MainActor in installedSkills = rows }
    }

    private func registerInstalledSkill(name: String, repoOwner: String, repoName: String) {
        var rows = SkillsView.readRegistry()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let idx = rows.firstIndex(where: { $0.name == name }) {
            rows[idx].updatedAt = now
        } else {
            rows.append(InstalledSkill(name: name, repoOwner: repoOwner, repoName: repoName, installedAt: now, updatedAt: now))
        }
        let dir = (SkillsView.registryPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        if let data = try? JSONEncoder().encode(rows.sorted(by: { $0.name < $1.name })) {
            try? data.write(to: URL(fileURLWithPath: SkillsView.registryPath), options: .atomic)
        }
    }

    /// One request per distinct upstream repo (not per skill): compares the
    /// repo's latest commit time against when we installed/updated each skill.
    /// Repo-level granularity can over-report for monorepos, but costs
    /// `distinct repos` requests instead of `skills × tree walks`.
    private func checkForUpdates(force: Bool = false) async {
        if !force, let last = lastUpdateCheck, Date().timeIntervalSince(last) < 600 { return }
        let skills = await MainActor.run { installedSkills }
        guard !skills.isEmpty else { return }
        await MainActor.run {
            isCheckingUpdates = true
            installErrorMessage = nil
        }

        let token = resolveGitHubToken()
        let repos = Set(skills.map { $0.repoSlug })
        var repoLatest: [String: Int64] = [:]
        var firstErrorCode: Int? = nil
        let iso = ISO8601DateFormatter()

        for slug in repos {
            guard let url = URL(string: "https://api.github.com/repos/\(slug)/commits?per_page=1") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            req.setValue("Archer-Terminal", forHTTPHeaderField: "User-Agent")
            if let token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            guard let (data, resp) = try? await SkillsView.apiSession.data(for: req) else { continue }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                if firstErrorCode == nil { firstErrorCode = (resp as? HTTPURLResponse)?.statusCode ?? -1 }
                continue
            }
            guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let commit = list.first?["commit"] as? [String: Any],
                  let committer = commit["committer"] as? [String: Any],
                  let dateStr = committer["date"] as? String,
                  let date = iso.date(from: dateStr)
            else { continue }
            repoLatest[slug] = Int64(date.timeIntervalSince1970 * 1000)
        }

        var names: Set<String> = []
        for skill in skills {
            if let latest = repoLatest[skill.repoSlug], latest > max(skill.installedAt, skill.updatedAt) {
                names.insert(skill.name)
            }
        }

        await MainActor.run {
            updatableSkillNames = names
            updateCount = names.count + (hermesUpdateAvailable ? 1 : 0)
            lastUpdateCheck = Date()
            isCheckingUpdates = false
            if repoLatest.isEmpty, let code = firstErrorCode {
                installErrorMessage = code == 403
                    ? "检查更新失败:GitHub API 限流(403)。登录 gh(gh auth login)或设置 GITHUB_TOKEN 可提升到 5000 次/小时。"
                    : "检查更新失败(HTTP \(code))。"
            }
        }
        // [archer] Hermes skills live in a git repo with no usable remote
        // here; they update via `hermes update`, which we invoke read-only.
        await checkHermesUpdates()
    }

    /// [archer] Read-only check: runs `hermes update --check` and parses the
    /// "N commits behind origin/main" line. Never mutates the repo.
    private func checkHermesUpdates() async {
        let hermesPath = "/Users/mac/.local/bin/hermes"
        guard FileManager.default.isExecutableFile(atPath: hermesPath) else {
            await MainActor.run { hermesUpdateAvailable = false; hermesBehindCount = 0 }
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hermesPath)
        process.arguments = ["update", "--check"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            await MainActor.run { hermesUpdateAvailable = false; hermesBehindCount = 0 }
            return
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        // Match "Update available: 6 commits behind origin/main."
        var behind = 0
        if let range = text.range(of: "(\\d+) commits behind", options: .regularExpression),
           let n = Int(text[range].replacingOccurrences(of: " commits behind", with: ""))
        {
            behind = n
        }
        let available = behind > 0
        await MainActor.run {
            hermesUpdateAvailable = available
            hermesBehindCount = behind
            // Fold Hermes into the global "可更新" count.
            updateCount = self.updatableSkillNames.count + (available ? 1 : 0)
        }
    }

    /// [archer] Fire-and-forget `hermes update --yes` to pull + reinstall.
    private func runHermesUpdate() {
        isUpdatingHermes = true
        Task {
            let hermesPath = "/Users/mac/.local/bin/hermes"
            guard FileManager.default.isExecutableFile(atPath: hermesPath) else {
                await MainActor.run { isUpdatingHermes = false }
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: hermesPath)
            process.arguments = ["update", "--yes"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do { try process.run(); process.waitUntilExit() } catch {}
            await MainActor.run { isUpdatingHermes = false }
            await checkHermesUpdates()
        }
    }

    private func searchSkillsSh() {
        guard !discoverQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        discoverResults = []
        let q = discoverQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? discoverQuery
        guard let url = URL(string: "https://skills.sh/api/search?q=\(q)&limit=20") else {
            isSearching = false; return
        }
        Task {
            defer { Task { @MainActor in isSearching = false } }
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.setValue("Archer-Terminal", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await SkillsView.apiSession.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["skills"] as? [[String: Any]] else { return }
            let results: [SkillsShResult] = list.compactMap { item in
                guard let skillId = item["skillId"] as? String,
                      let name = item["name"] as? String,
                      let source = item["source"] as? String else { return nil }
                let installs = item["installs"] as? Int ?? 0
                return SkillsShResult(id: skillId, name: name, source: source, installs: installs)
            }
            await MainActor.run { discoverResults = results }
        }
    }

    /// One-shot index of nicepkg/ai-workflow via the Git Trees API. Cached in
    /// memory for the panel's lifetime; `force` re-fetches (retry button).
    private func fetchAIWorkflowIndex(force: Bool = false) {
        if aiWorkflowIndex != nil, !force { return }
        isSearching = true
        aiWorkflowLoadError = nil
        let token = resolveGitHubToken()
        Task {
            defer { Task { @MainActor in isSearching = false } }
            guard let url = URL(string: "https://api.github.com/repos/nicepkg/ai-workflow/git/trees/HEAD?recursive=1") else { return }
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            req.setValue("Archer-Terminal", forHTTPHeaderField: "User-Agent")
            if let token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200
            else {
                await MainActor.run {
                    aiWorkflowLoadError = "加载 ai-workflow 索引失败(GitHub API 不可达或限流,可运行 gh auth login)"
                }
                return
            }
            let parsed = SkillsView.parseAIWorkflowTree(data)
            await MainActor.run { aiWorkflowIndex = parsed }
        }
    }

    /// Parses a Git Trees API response into skill entries. ai-workflow keeps
    /// skills at exactly `workflows/<wf>/.claude/skills/<name>/SKILL.md`;
    /// deeper matches are sub-skills bundled inside a skill's assets and the
    /// top-level `.claude/skills/` holds the repo's own meta skills — both
    /// deliberately excluded. Static + pure so tests can feed it fixtures.
    static func parseAIWorkflowTree(_ data: Data) -> [SkillsShResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else { return [] }
        var results: [SkillsShResult] = []
        for node in tree {
            guard let path = node["path"] as? String else { continue }
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count == 6,
                  parts[0] == "workflows",
                  parts[2] == ".claude",
                  parts[3] == "skills",
                  parts[5] == "SKILL.md" else { continue }
            let workflow = parts[1]
            let name = parts[4]
            let group = workflow.hasSuffix("-workflow") ? String(workflow.dropLast("-workflow".count)) : workflow
            results.append(SkillsShResult(
                id: "\(workflow)/\(name)",
                name: name,
                source: "nicepkg/ai-workflow",
                installs: 0,
                repoPath: "workflows/\(workflow)/.claude/skills/\(name)",
                groupLabel: group
            ))
        }
        return results.sorted {
            ($0.groupLabel ?? "", $0.name) < ($1.groupLabel ?? "", $1.name)
        }
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

                // Real signals — no fabricated trigger counts.
                // `endpointCount` is filled after the duplicate/group pass
                // (it equals the number of agent endpoints exposing this
                // skill). `lastModified` reads SKILL.md's mtime; symlink
                // detection tells owned vs relayed skills apart.
                var isSym = false
                if let attrs = try? fm.attributesOfItem(atPath: skillDirPath),
                   let ft = attrs[.type] as? FileAttributeType,
                   ft == .typeSymbolicLink
                {
                    isSym = true
                }
                let mtime = try? fm.attributesOfItem(atPath: skillFilePath.isEmpty ? skillDirPath : skillFilePath)[.modificationDate] as? Date

                items.append(SkillItem(
                    name: name,
                    source: entry.source,
                    path: skillFilePath.isEmpty ? skillDirPath : skillFilePath,
                    skillDirName: subdir,
                    canonicalDirPath: skillDirPath,
                    description: desc,
                    endpointCount: 0,
                    lastModified: mtime,
                    lastModifiedLabel: mtime.map { Self.relativeTime($0) } ?? "未知",
                    isSymlink: isSym,
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
                items[idx].endpointCount = max(1, presence.count)
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

    /// Relative-time formatter for skill file mtimes. Pure + static so the
    /// scan can call it without a `DateFormatter` per row.
    static func relativeTime(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 0 {
            let hrs = Calendar.current.dateComponents([.hour], from: date, to: Date()).hour ?? 0
            return hrs <= 0 ? "今天" : "\(hrs) 小时前"
        }
        if days < 30 { return "\(days) 天前" }
        let months = days / 30
        if months < 12 { return "\(months) 个月前" }
        return "\(days / 365) 年前"
    }

    private func calculateStats() {
        totalCount = skills.count
        var uniqueNames = Set<String>()
        var issues = 0, active = 0, inactive = 0
        let fortyFiveDaysAgo = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date.distantPast
        for s in skills {
            uniqueNames.insert(s.name)
            if s.hasIssue { issues += 1 }
            // Real activity signal: SKILL.md modified within the last 45 days.
            if let m = s.lastModified, m >= fortyFiveDaysAgo { active += 1 } else { inactive += 1 }
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

    /// GitHub's unauthenticated API cap is 60 req/hr — trivially exhausted by
    /// installing a skill or two. Prefer `GITHUB_TOKEN`/`GITHUB_PERSONAL_ACCESS_TOKEN`
    /// if set, but Archer is normally launched from Finder/Dock, which does not
    /// inherit the user's shell profile — so those env vars are almost never
    /// actually present here even if set in `.zshrc`. Fall back to `gh auth
    /// token`: if the user has GitHub CLI signed in (common for developers),
    /// this gets us the same 5,000 req/hr authenticated limit with no setup.
    private func resolveGitHubToken() -> String? {
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GITHUB_PERSONAL_ACCESS_TOKEN"],
           !token.isEmpty
        {
            return token
        }
        // GUI apps get a minimal PATH, so a bare `env gh` lookup would miss
        // Homebrew installs — check the common absolute locations directly.
        let ghCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let ghPath = ghCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["auth", "token"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (token?.isEmpty == false) ? token : nil
        } catch {
            return nil
        }
    }

    /// [archer] Bulk symlink relay into every harness skills dir (补缺 only).
    /// Same semantics as `toggleAgent` / one-click relay — never clobbers.
    private func injectSkillsToHarnesses() async {
        await MainActor.run {
            isInjecting = true
            installErrorMessage = nil
            injectSuccessMessage = nil
        }

        let sourceDirs = skills.map { URL(fileURLWithPath: $0.canonicalDirPath) }

        do {
            let injector = SkillsInjector(sourceSkillDirs: sourceDirs)
            let result = try injector.installToAllHarnesses()
            await MainActor.run {
                injectSuccessMessage =
                    "中继完成：新建 \(result.linked) 条 symlink；跳过已有 \(result.skippedExisting)；自路径 \(result.skippedSelf)。"
                isInjecting = false
                loadSkills(silent: true)
            }
        } catch {
            await MainActor.run {
                installErrorMessage = "中继到 harness 失败：\(error.localizedDescription)"
                isInjecting = false
            }
        }
    }

    private func installSkillFromSh(_ result: SkillsShResult, targets: [String]) async {
        await MainActor.run { installErrorMessage = nil }

        let home = NSHomeDirectory()
        let fm = FileManager.default
        let githubToken = resolveGitHubToken()

        struct GitHubFile: Decodable {
            let name: String
            let path: String
            let download_url: String?
            let type: String
        }

        func downloadDirectory(repo: String, pathInRepo: String, destBasePaths: [String]) async throws {
            let urlString = "https://api.github.com/repos/\(repo)/contents/\(pathInRepo)"
            guard let url = URL(string: urlString) else { return }

            var req = URLRequest(url: url, timeoutInterval: 60)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            req.setValue("Archer-Terminal", forHTTPHeaderField: "User-Agent")

            if let githubToken {
                req.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            }

            let (data, resp) = try await SkillsView.apiSession.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
                if !urlString.contains("?ref=") {
                    let masterUrlString = urlString + "?ref=master"
                    if let masterUrl = URL(string: masterUrlString) {
                        var masterReq = req
                        masterReq.url = masterUrl
                        let (mData, mResp) = try await SkillsView.apiSession.data(for: masterReq)
                        if let mHttpResp = mResp as? HTTPURLResponse, mHttpResp.statusCode == 200 {
                            try await parseAndDownload(data: mData, repo: repo, destBasePaths: destBasePaths)
                            return
                        }
                    }
                }
                let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let description: String
                switch statusCode {
                case 403:
                    description = "GitHub API 请求超限(403),未认证请求每小时限 60 次,请稍后再试。"
                case 404:
                    description = "在 \(repo) 找不到路径 \(pathInRepo)(404)。"
                default:
                    description = "GitHub 请求失败(HTTP \(statusCode))。"
                }
                throw NSError(domain: "GitHubAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: description])
            }

            try await parseAndDownload(data: data, repo: repo, destBasePaths: destBasePaths)
        }

        func parseAndDownload(data: Data, repo: String, destBasePaths: [String]) async throws {
            let decoder = JSONDecoder()
            let files = try decoder.decode([GitHubFile].self, from: data)

            for file in files {
                if file.type == "file", let dlUrlStr = file.download_url, let dlUrl = URL(string: dlUrlStr) {
                    // Stream the file so we can surface a real download progress
                    // (bytes received) instead of blocking on an all-or-nothing
                    // `data(from:)`. Retries transient timeouts (common on the
                    // unauthenticated raw.githubusercontent CDN) and sends the
                    // resolved GitHub token so we stay under the 60 req/hr limit.
                    var fileData = Data()
                    let maxAttempts = 3
                    var lastErr: Error?
                    for attempt in 1 ... maxAttempts {
                        do {
                            var dlReq = URLRequest(url: dlUrl, timeoutInterval: 120)
                            dlReq.setValue("Archer-Terminal", forHTTPHeaderField: "User-Agent")
                            if let githubToken {
                                dlReq.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
                            }
                            let (bytes, _) = try await SkillsView.apiSession.bytes(for: dlReq)
                            fileData = Data()
                            for try await byte in bytes {
                                fileData.append(byte)
                                await MainActor.run { updateBytesDone += 1 }
                            }
                            lastErr = nil
                            break
                        } catch {
                            lastErr = error
                            // Roll back the progress we counted for the partial
                            // stream so a retry starts from a clean counter.
                            let rolledBack = fileData.count
                            fileData = Data()
                            await MainActor.run { updateBytesDone -= Int64(rolledBack) }
                            if attempt < maxAttempts {
                                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                            }
                        }
                    }
                    if let lastErr { throw lastErr }

                    for destBase in destBasePaths {
                        let prefix = "\(result.resolvedRepoPath)/"
                        var relPath = file.path
                        if relPath.hasPrefix(prefix) {
                            relPath = String(relPath.dropFirst(prefix.count))
                        }

                        let destFilePath = (destBase as NSString).appendingPathComponent(relPath)
                        let destFileDir = (destFilePath as NSString).deletingLastPathComponent

                        try fm.createDirectory(atPath: destFileDir, withIntermediateDirectories: true, attributes: nil)
                        try fileData.write(to: URL(fileURLWithPath: destFilePath))
                    }
                } else if file.type == "dir" {
                    try await downloadDirectory(repo: repo, pathInRepo: file.path, destBasePaths: destBasePaths)
                }
            }
        }

        do {
            var destPaths: [String] = []
            for target in targets {
                if let def = SkillsView.agentDefs.first(where: { $0.key == target }) {
                    let path = (home as NSString).appendingPathComponent(def.subdir).appending("/\(result.installDirName)")
                    destPaths.append(path)
                }
            }

            if destPaths.isEmpty { return }

            try await downloadDirectory(repo: result.source, pathInRepo: result.resolvedRepoPath, destBasePaths: destPaths)

            let parts = result.source.split(separator: "/")
            let owner = parts.count > 0 ? String(parts[0]) : ""
            let repo = parts.count > 1 ? String(parts[1]) : ""
            registerInstalledSkill(name: result.installDirName, repoOwner: owner, repoName: repo)

            await MainActor.run {
                self.loadSkills(silent: true)
                self.loadInstalledRegistry()
                if self.updatableSkillNames.remove(result.installDirName) != nil {
                    self.updateCount = self.updatableSkillNames.count
                }
            }
        } catch {
            await MainActor.run {
                installErrorMessage = "安装 \(result.name) 失败: \(error.localizedDescription)"
            }
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

                Text(skill.endpointCount == 0 ? "0" : "\(skill.endpointCount)")
                    .font(Theme.mono(15, weight: skill.endpointCount == 0 ? .regular : .bold))
                    .foregroundStyle(skill.endpointCount == 0 ? Theme.chromeMuted : Theme.chromeForeground)
                    .frame(width: 120, alignment: .trailing)

                Text(skill.lastModifiedLabel)
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
        if skill.endpointCount > 0 {
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

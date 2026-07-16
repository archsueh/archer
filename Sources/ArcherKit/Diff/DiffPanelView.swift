import SwiftUI

/// Right-side Git Diff panel: visualizes uncommitted changes in the active
/// workspace. When `family` has multiple source/worktree members, shows a
/// cross-worktree overview above the file list (BACKLOG A.1②).
/// Fits a 280px-wide sidebar using a stacked List -> Detail navigation pattern.
public struct DiffPanelView: View {
    @StateObject private var model: DiffModel
    @State private var showingDetail = false
    /// AI commit preview sheet state.
    @State private var showCommitSheet = false
    @State private var commitPlan: GitAgentCommitResult?
    @State private var commitError: String?
    @State private var commitBusy = false
    /// Co-change analysis expansion (git-agent `related`).
    @State private var showRelated = false
    @State private var related: GitAgentRelatedResult?
    @State private var relatedError: String?
    @State private var relatedBusy = false
    let rootURL: URL
    var width: Double

    public init(rootURL: URL, family: [WorktreeDiffMember] = [], width: Double = 280) {
        self.rootURL = rootURL
        self.width = width
        _model = StateObject(wrappedValue: DiffModel(rootURL: rootURL, family: family))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)

            Group {
                if model.isLoading && model.modifiedFiles.isEmpty && model.summaries.isEmpty {
                    loadingView
                } else if showingDetail, let selected = model.selectedFile {
                    diffDetailView(for: selected)
                } else {
                    if model.showsFamilyOverview {
                        familyOverview
                        Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                    }
                    if model.modifiedFiles.isEmpty {
                        emptyView
                    } else {
                        fileListView
                        relatedSection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: CGFloat(width))
        .background(Theme.chromeBackground)
        .onDisappear {
            model.teardown()
        }
        .sheet(isPresented: $showCommitSheet) {
            commitSheet
        }
    }

    // MARK: - AI Commit (git-agent)

    /// Previews an atomic commit plan via `git-agent commit --dry-run -o json`.
    /// Opens a confirmation sheet; the user approves before anything is committed.
    private func runCommitPreview() async {
        guard GitAgentClient.shared.binaryPath() != nil else {
            commitError = GitAgentClient.GitAgentError.notFound.errorDescription
            showCommitSheet = true
            return
        }
        commitBusy = true
        commitError = nil
        commitPlan = nil
        defer { commitBusy = false }
        do {
            let plan = try await GitAgentClient.shared.commit(cwd: model.focusedRootURL, dryRun: true)
            commitPlan = plan
            showCommitSheet = true
        } catch {
            commitError = error.localizedDescription
            showCommitSheet = true
        }
    }

    /// Executes the approved commit plan for real.
    private func runCommitApply() async {
        commitBusy = true
        commitError = nil
        defer { commitBusy = false }
        do {
            let result = try await GitAgentClient.shared.commit(cwd: model.focusedRootURL, dryRun: false)
            commitPlan = result
            // Refresh the diff panel so committed files drop out of CHANGES.
            model.refresh()
        } catch {
            commitError = error.localizedDescription
        }
    }

    // MARK: - Co-change analysis (git-agent related)

    private func runRelated() async {
        relatedBusy = true
        relatedError = nil
        related = nil
        defer { relatedBusy = false }
        do {
            related = try await GitAgentClient.shared.related(cwd: model.focusedRootURL)
        } catch {
            relatedError = error.localizedDescription
        }
    }

    // MARK: - Views

    private var header: some View {
        HStack(spacing: 6) {
            if showingDetail {
                HoverableIconButton(systemName: "chevron.left", fontSize: 11, size: 24, help: "Back to list") {
                    withAnimation(Theme.chromeTransition) {
                        showingDetail = false
                    }
                }
            }

            Text(showingDetail ? "DIFF" : "CHANGES")
                .font(Theme.display(12, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)

            Spacer()

            if !showingDetail {
                Text(headerFileCountLabel)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
            }

            HoverableIconButton(systemName: "wand.and.stars", fontSize: 11, size: 24, help: "AI Commit (git-agent)") {
                Task { await runCommitPreview() }
            }
            .disabled(model.modifiedFiles.isEmpty || commitBusy)

            HoverableIconButton(systemName: "arrow.clockwise", fontSize: 11, size: 24, help: "Refresh") {
                model.refresh()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var headerFileCountLabel: String {
        if model.showsFamilyOverview {
            return "\(model.totalDirtyFileCount) · \(model.summaries.count) trees"
        }
        return "\(model.modifiedFiles.count) files"
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.chromeMuted)
            Text("No uncommitted changes")
                .font(Theme.display(11))
                .foregroundStyle(Theme.chromeMuted)
            if model.showsFamilyOverview {
                Text("in focused tree")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeMuted.opacity(0.8))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Per-worktree dirty counts. Tap a row to focus the file list on that tree.
    private var familyOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WORKTREES")
                .font(Theme.mono(9, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Theme.chromeMuted.opacity(0.85))
                .padding(.horizontal, Theme.space3)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(model.summaries) { summary in
                FamilySummaryRow(
                    summary: summary,
                    isFocused: summary.rootURL == model.focusedRootURL
                ) {
                    withAnimation(Theme.chromeTransition) {
                        showingDetail = false
                        model.focus(rootURL: summary.rootURL)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(model.modifiedFiles) { file in
                    FileListRow(file: file, isSelected: model.selectedFile?.url == file.url) {
                        model.select(file)
                        withAnimation(Theme.chromeTransition) {
                            showingDetail = true
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func diffDetailView(for file: ModifiedFile) -> some View {
        VStack(spacing: 0) {
            // File header strip
            HStack {
                Text(file.url.lastPathComponent)
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                Spacer()
                statusBadge(file.status)
            }
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, 6)
            .background(Theme.chromeHairline.opacity(0.3))

            Rectangle().fill(Theme.chromeHairline).frame(height: 1)

            if model.activeDiffLines.isEmpty {
                VStack {
                    Spacer()
                    Text("No diff content")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeMuted)
                    Spacer()
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.activeDiffLines) { line in
                            DiffLineRow(line: line)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func statusBadge(_ status: GitFileStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .added:
            text = "ADDED"
            color = Theme.gitInsertion
        case .deleted:
            text = "DELETED"
            color = Theme.gitDeletion
        case .modified:
            text = "MODIFIED"
            color = Theme.activityAttention
        }
        return Text(text)
            .font(Theme.mono(8.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .bracketBorder()
    }

    // MARK: - Co-change section (git-agent related)

    /// Collapsible "related changes" block under the file list. Triggers a
    /// `git-agent related` query (offline, mines git history) to surface files
    /// that habitually change together with the current edits.
    private var relatedSection: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            HStack(spacing: 6) {
                Button {
                    withAnimation(Theme.chromeTransition) {
                        if showRelated {
                            showRelated = false
                        } else {
                            showRelated = true
                            if related == nil && relatedError == nil { Task { await runRelated() } }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showRelated ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("关联改动")
                            .font(Theme.display(11, weight: .medium))
                    }
                    .foregroundStyle(Theme.chromeForeground)
                }
                .buttonStyle(.plain)

                if relatedBusy {
                    ProgressView().scaleEffect(0.7)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, 6)

            if showRelated {
                relatedContent
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private var relatedContent: some View {
        if let error = relatedError {
            Text(error)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.gitDeletion)
                .padding(.horizontal, Theme.space3)
        } else if let result = related {
            if result.coChanged.isEmpty {
                Text("无关联文件")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.horizontal, Theme.space3)
            } else {
                ForEach(result.coChanged.prefix(8)) { entry in
                    relatedRow(entry)
                }
            }
        }
    }

    private func relatedRow(_ entry: GitAgentRelatedEntry) -> some View {
        let pct = Int(entry.couplingStrength * 100)
        return HStack(spacing: 6) {
            Text("\(pct)%")
                .font(Theme.mono(9, weight: .medium))
                .foregroundStyle(Theme.activityAttention)
                .frame(width: 30, alignment: .trailing)
            Text(entry.path)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 2)
    }

    // MARK: - AI Commit sheet

    /// Confirmation sheet for the atomic commit plan. Shows each planned commit
    /// group (title + files); the user approves before `git-agent` commits.
    private var commitSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI Commit")
                    .font(Theme.display(14, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                Spacer()
                if commitBusy {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(16)

            Rectangle().fill(Theme.chromeHairline).frame(height: 1)

            if let error = commitError {
                ScrollView {
                    Text(error)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.gitDeletion)
                        .padding(16)
                }
            } else if let plan = commitPlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(plan.commits) { commit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.title)
                                    .font(Theme.mono(11, weight: .medium))
                                    .foregroundStyle(Theme.chromeForeground)
                                Text(commit.files.joined(separator: "  ·  "))
                                    .font(Theme.mono(9))
                                    .foregroundStyle(Theme.chromeMuted)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                if let sha = commit.sha {
                                    Text("→ \(sha.prefix(7))")
                                        .font(Theme.mono(9))
                                        .foregroundStyle(Theme.gitInsertion)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }

            Rectangle().fill(Theme.chromeHairline).frame(height: 1)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") { showCommitSheet = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.chromeMuted)
                if let plan = commitPlan, plan.commits.isEmpty == false, commitError == nil {
                    Button {
                        Task {
                            await runCommitApply()
                            if commitError == nil { showCommitSheet = false }
                        }
                    } label: {
                        Text("提交 \(plan.commits.count) 组")
                            .font(Theme.display(11, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.activityAttention)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(commitBusy)
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 420)
        .background(Theme.chromeBackground)
    }
}

// MARK: - Row Components

private struct FamilySummaryRow: View {
    let summary: WorktreeDiffSummary
    let isFocused: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isFocused ? "circle.inset.filled" : "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isFocused ? Theme.chromeForeground : Theme.chromeMuted)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title)
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                if let branch = summary.branch, !branch.isEmpty {
                    Text("⎇ \(branch)")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.chromeMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if summary.fileCount == 0 {
                Text("clean")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeMuted)
            } else {
                HStack(spacing: 4) {
                    if summary.modifiedCount > 0 {
                        countChip(summary.modifiedCount, color: Theme.activityAttention)
                    }
                    if summary.addedCount > 0 {
                        countChip(summary.addedCount, color: Theme.gitInsertion)
                    }
                    if summary.deletedCount > 0 {
                        countChip(summary.deletedCount, color: Theme.gitDeletion)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 5)
        .background(isFocused ? Theme.chromeActive : (hovered ? Theme.chromeHover : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { action() }
    }

    private func countChip(_ n: Int, color: Color) -> some View {
        Text("\(n)")
            .font(Theme.mono(9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .bracketBorder()
    }
}

private struct FileListRow: View {
    let file: ModifiedFile
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator(file.status)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                Text(file.url.deletingLastPathComponent().lastPathComponent)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeMuted)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 6)
        .background(isSelected ? Theme.chromeActive : (hovered ? Theme.chromeHover : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { action() }
    }

    private func statusIndicator(_ status: GitFileStatus) -> some View {
        let symbol: String
        let color: Color
        switch status {
        case .added:
            symbol = "plus.circle.fill"
            color = Theme.gitInsertion
        case .deleted:
            symbol = "minus.circle.fill"
            color = Theme.gitDeletion
        case .modified:
            symbol = "pencil.circle.fill"
            color = Theme.activityAttention
        }
        return Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(color)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 8) {
            // Line counters
            HStack(spacing: 4) {
                Text(line.oldLineNum.map(String.init) ?? "")
                    .frame(width: 20, alignment: .trailing)
                Text(line.newLineNum.map(String.init) ?? "")
                    .frame(width: 20, alignment: .trailing)
            }
            .font(Theme.mono(8.5))
            .foregroundStyle(Theme.chromeMuted.opacity(0.5))

            // Code Content
            Text(line.content)
                .font(Theme.mono(10))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(backgroundColor)
    }

    private var textColor: Color {
        switch line.type {
        case .added: return Theme.gitInsertion
        case .deleted: return Theme.gitDeletion
        case .header: return Theme.chromeMuted
        case .context: return Theme.chromeForeground.opacity(0.85)
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return Theme.gitInsertion.opacity(0.08)
        case .deleted: return Theme.gitDeletion.opacity(0.08)
        case .header: return Theme.chromeHairline.opacity(0.15)
        case .context: return Color.clear
        }
    }
}

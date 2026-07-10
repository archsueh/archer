// ProjectRulesSection.swift
// Inspired by orbiteditor's `.cursor/rules` (project-root rule files that an
// AI agent auto-loads). Archer does NOT auto-inject these into any agent's
// system prompt — that would cross the "one worktree, one agent session"
// isolation boundary (STATE §4) and violate the human-curation philosophy.
// Instead this section *discovers* `.archer/rules/*.md` in the active
// workspace's disk root and lists them; tapping a rule copies `@<path>` so
// the user can reference it manually in a prompt. Read-only, side-effect free.

import SwiftUI

struct ProjectRulesSection: View {
    @Bindable var store: WorkspaceStore

    private let fm = FileManager.default
    @State private var rules: [URL] = []

    private var root: URL? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }?.diskPath
    }

    private var rulesDir: URL? {
        root?.appendingPathComponent(".archer/rules")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: Theme.space2) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 16, height: 16)
                Text(L10n.string("Project rules"))
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.9))
                Spacer(minLength: 0)
                Text("\(rules.count)")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.45))
            }
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }

            if isExpanded {
                if rules.isEmpty {
                    Text(L10n.string("No project rules"))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.chromeForeground.opacity(0.4))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ScrollView(showsIndicators: true) {
                        LazyVStack(alignment: .trailing, spacing: 0) {
                            ForEach(rules, id: \.path) { rule in
                                HStack(alignment: .firstTextBaseline, spacing: Theme.space1) {
                                    Text("→")
                                        .font(Theme.mono(9))
                                        .foregroundStyle(Theme.chromeForeground.opacity(0.45))
                                    Text(rule.lastPathComponent)
                                        .font(Theme.mono(10))
                                        .foregroundStyle(Theme.chromeForeground.opacity(0.8))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, Theme.space3)
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                                .onTapGesture { copyToPasteboard("@\(rule.path)") }
                                .help("\(rule.lastPathComponent) · 点击复制 @\(rule.path)")
                            }
                        }
                        .padding(.horizontal, Theme.space2)
                        .padding(.vertical, Theme.space1)
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 2)
        .onAppear { scan() }
        .onChange(of: store.activeWorkspaceId) { _, _ in scan() }
    }

    @State private var isExpanded = true

    private func scan() {
        guard let dir = rulesDir,
              let urls = try? fm.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else { rules = []; return }
        rules = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func copyToPasteboard(_ text: String) {
        let escaped = text.replacingOccurrences(of: " ", with: "\\ ")
        guard let data = "\(escaped)\n".data(using: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .string)
    }
}

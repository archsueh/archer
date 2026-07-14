import SwiftUI

/// Brutalist sheet for spawning N parallel Claude agents in N git worktrees
/// from a source workspace. Each slot gets its own branch and initial prompt;
/// they all share a launch template.
///
/// Visual language mirrors `CreateWorktreeSheet`: `Theme.chrome*` tokens,
/// mono kebab-case labels, hairlines, bracket buttons, 480pt wide.
struct ParallelTaskSheet: View {
    /// Adam Sandler's "Delegation Brief" discipline: a task handed to a
    /// worker agent is a verifiable unit, not a vague ask. Goal is required;
    /// the rest sharpen the result. `briefText()` flattens this into the
    /// prompt we actually send, so workers get a structured contract.
    struct AgentSlot: Identifiable {
        let id = UUID()
        var branchName: String
        var prompt: String
        var goal: String = ""
        var why: String = ""
        var criteria: String = ""
        var boundaries: String = ""
    }

    /// Flattens a slot's Delegation Brief into the prompt text sent to the
    /// agent. When the structured fields are empty we fall back to the raw
    /// `prompt` (legacy / free-form path) so existing callers are unaffected.
    static func briefText(_ slot: AgentSlot) -> String {
        let goal = slot.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = slot.why.trimmingCharacters(in: .whitespacesAndNewlines)
        let criteria = slot.criteria.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundaries = slot.boundaries.trimmingCharacters(in: .whitespacesAndNewlines)
        if goal.isEmpty, why.isEmpty, criteria.isEmpty, boundaries.isEmpty {
            return slot.prompt
        }
        var out = ""
        out += "## Goal\n\(goal.isEmpty ? slot.prompt : goal)\n"
        if !why.isEmpty { out += "\n## Why it matters\n\(why)\n" }
        if !criteria.isEmpty { out += "\n## Completion Criteria (machine-checkable)\n\(criteria)\n" }
        if !boundaries.isEmpty { out += "\n## Boundaries\n\(boundaries)\n" }
        out += "\n## Honesty rule\nWorker never grades its own work. `Done` means green build + passing tests (exit code 0). Report without attached checks is incomplete.\n"
        return out
    }

    struct Request {
        let agents: [AgentSlot]
        let template: AgentTemplate
    }

    let source: Workspace
    let launchTemplates: [AgentTemplate]
    let defaultLaunchTemplate: AgentTemplate
    /// Returns nil on success, an error string on failure.
    let launch: @MainActor (Request) async -> String?
    let dismiss: () -> Void

    @State private var agentCount: Int = 2
    @State private var slots: [AgentSlot] = []
    @State private var selectedTemplate: AgentTemplate?
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

    private static let maxAgents = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLabel
                .padding(.bottom, 18)

            headline
            subtitle
                .padding(.top, 6)

            Rectangle()
                .fill(Theme.chromeHairline)
                .frame(width: 32, height: 1)
                .padding(.vertical, 22)

            form

            honestyRule

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.activityFailure.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            HStack(spacing: 10) {
                Spacer()
                BracketButton("cancel") { dismiss() }
                    .disabled(isWorking)
                    .opacity(isWorking ? 0.4 : 1)
                BracketButton(isWorking ? "launching…" : "launch parallel") {
                    submit()
                }
                .disabled(isWorking || !canSubmit)
                .opacity(canSubmit && !isWorking ? 1 : 0.4)
            }
            .padding(.top, 22)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .frame(width: 480, alignment: .topLeading)
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onAppear(perform: prefill)
    }

    // MARK: Sections

    private var statusLabel: some View {
        Text("PARALLEL-TASK")
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(Theme.chromeMuted.opacity(0.85))
    }

    private var headline: some View {
        Text(source.title)
            .font(Theme.display(20, weight: .medium))
            .foregroundStyle(Theme.chromeForeground)
    }

    private var subtitle: some View {
        Text((source.workingDirectory.path as NSString).abbreviatingWithTildeInPath)
            .font(Theme.mono(11.5))
            .foregroundStyle(Theme.chromeMuted)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            agentCountPicker
            launchPicker
            Divider()
                .background(Theme.chromeHairline)
                .padding(.vertical, 2)
            ForEach(slots.indices, id: \.self) { i in
                agentSlotSection(index: i)
            }
        }
    }

    private var agentCountPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("agents")
            Picker("", selection: $agentCount) {
                Text("2").tag(2)
                Text("3").tag(3)
                Text("4").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: agentCount) { _, count in
                syncSlots(to: count)
            }
        }
    }

    private var launchPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("launch")
            Picker("", selection: Binding(
                get: { selectedTemplate ?? defaultLaunchTemplate },
                set: { selectedTemplate = $0 }
            )) {
                ForEach(launchTemplates) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func agentSlotSection(index: Int) -> some View {
        if index < slots.count {
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("agent-\(index + 1)")
                TextField("branch-name", text: $slots[index].branchName)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .bracketBorder()
                briefField(index: index, label: "goal *", binding: $slots[index].goal, placeholder: "one sentence: what to deliver", lines: 2 ... 4)
                briefField(index: index, label: "why it matters", binding: $slots[index].why, placeholder: "why this matters now", lines: 2 ... 3)
                briefField(index: index, label: "completion criteria", binding: $slots[index].criteria, placeholder: "machine-checkable: build green, tests pass, exit 0", lines: 2 ... 4)
                briefField(index: index, label: "boundaries", binding: $slots[index].boundaries, placeholder: "what NOT to do (e.g. no force-push, no schema change)", lines: 2 ... 3)
            }
        }
    }

    /// One Delegation Brief text field, bound to a slot string field.
    private func briefField(index _: Int, label: String, binding: Binding<String>, placeholder: String, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            TextField(placeholder, text: binding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(lines)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .bracketBorder()
        }
    }

    private var honestyRule: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 11))
            Text("Worker 不自评 · Done = 绿构建 + 通过测试（退出码 0）")
                .font(Theme.mono(10.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.chromeMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bracketBorder()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.chromeMuted.opacity(0.85))
    }

    // MARK: Logic

    private var canSubmit: Bool {
        slots.allSatisfy { !$0.branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && slots.allSatisfy { !Self.briefText($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func prefill() {
        if selectedTemplate == nil {
            selectedTemplate = defaultLaunchTemplate
        }
        syncSlots(to: agentCount)
    }

    private func syncSlots(to count: Int) {
        while slots.count < count {
            let n = slots.count + 1
            let branch = "parallel-\(n)"
            slots.append(AgentSlot(branchName: branch, prompt: ""))
        }
        if slots.count > count {
            slots = Array(slots.prefix(count))
        }
    }

    private func submit() {
        let template = selectedTemplate ?? defaultLaunchTemplate
        // Promote each slot's Delegation Brief into the prompt the worker
        // receives. `briefText` falls back to the raw `prompt` when no
        // structured fields are filled, so free-form use still works.
        let briefed = slots.map { slot in
            var s = slot
            s.prompt = Self.briefText(slot)
            return s
        }
        let request = Request(agents: briefed, template: template)
        isWorking = true
        errorMessage = nil
        Task {
            let err = await launch(request)
            if let err {
                isWorking = false
                errorMessage = err
            } else {
                dismiss()
            }
        }
    }
}

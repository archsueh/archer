import SwiftUI

/// Brutalist sheet for spawning N parallel Claude agents in N git worktrees
/// from a source workspace. Each slot gets its own branch and initial prompt;
/// they all share a launch template.
///
/// Visual language mirrors `CreateWorktreeSheet`: `Theme.chrome*` tokens,
/// mono kebab-case labels, hairlines, bracket buttons, 480pt wide.
struct ParallelTaskSheet: View {
    struct AgentSlot: Identifiable {
        let id = UUID()
        var branchName: String
        var prompt: String
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
                TextField("describe this agent's task…", text: $slots[index].prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(3 ... 6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .bracketBorder()
            }
        }
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
    }

    private func prefill() {
        if selectedTemplate == nil {
            selectedTemplate = defaultLaunchTemplate
        }
        syncSlots(to: agentCount)
    }

    private func syncSlots(to count: Int) {
        // Reuse existing slots where possible; append or trim as needed.
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
        let request = Request(agents: slots, template: template)
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

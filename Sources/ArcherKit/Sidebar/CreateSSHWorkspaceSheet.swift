import SwiftUI

/// Brutalist sheet for creating an SSH workspace — one field, the ssh
/// destination. Same visual language as `CreateWorktreeSheet` (`Theme.chrome*`
/// tokens, mono kebab-case labels, bracket buttons). Purely presentational:
/// the parent owns workspace creation via the `create` closure.
struct CreateSSHWorkspaceSheet: View {
    let create: (String) -> Void
    let dismiss: () -> Void

    @State private var destination = ""
    @FocusState private var fieldFocused: Bool

    /// Same blank-collapses-to-nil rule the store's `normalizedSSHHost`
    /// applies at ingress, so the submit gate and the model gate can't drift.
    private var normalizedDestination: String? {
        normalizedTitle(destination)
    }

    private var canSubmit: Bool {
        normalizedDestination != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SSH-WORKSPACE")
                .font(Theme.mono(10.5, weight: .semibold))
                .foregroundStyle(Theme.chromeMuted)
                .tracking(1.2)
                .padding(.bottom, 18)

            Text("Connect to a remote host")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.chromeForeground)

            Text("Every new tab in this workspace opens an SSH session to the same destination; agent tabs launch their agent on the remote.")
                .font(Theme.display(12.5))
                .foregroundStyle(Theme.chromeMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Rectangle()
                .fill(Theme.chromeHairline)
                .frame(width: 32, height: 1)
                .padding(.vertical, 22)

            VStack(alignment: .leading, spacing: 8) {
                Text("destination")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Theme.chromeMuted)
                TextField("user@host", text: $destination)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .bracketBorder()
                    .focused($fieldFocused)
                    .onSubmit(submit)
                Text("anything your `ssh` accepts — host aliases from ~/.ssh/config work")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted.opacity(0.8))
            }

            HStack(spacing: 10) {
                Spacer()
                BracketButton("cancel") { dismiss() }
                BracketButton("create") { submit() }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
            }
            .padding(.top, 22)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .frame(width: 420, alignment: .topLeading)
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onAppear { fieldFocused = true }
    }

    private func submit() {
        guard let host = normalizedDestination else { return }
        create(host)
    }
}

import AppKit
import SwiftUI

/// Brutalist confirm sheet for closing a worktree workspace. Same visual
/// language as `CreateWorktreeSheet` / `UpdatePromptView`. Parent owns
/// the actual close (+ optional git ops) via the `confirm` closure; this
/// view stays a pure form.
///
/// Three dispositions (BACKLOG A.1①):
/// - **keep**: drop the sidebar entry only — disk untouched
/// - **merge**: merge worktree branch into the main tree HEAD, then
///   `git worktree remove` + `branch -d`
/// - **delete**: `git worktree remove --force` + `branch -d` (merged only)
///
/// Default is non-destructive (`keep`) so close stays safe by habit.
struct ConfirmRemoveWorktreeSheet: View {
    enum Outcome: Equatable {
        case success
        case failure(String)
    }

    /// Close disposition chosen in the sheet.
    enum Mode: String, CaseIterable, Identifiable, Equatable {
        case keep
        case merge
        case delete

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .keep: return "keep on disk (sidebar only)"
            case .merge: return "merge into main tree, then delete"
            case .delete: return "delete worktree directory and branch"
            }
        }

        var workingLabel: String {
            switch self {
            case .keep: return "closing…"
            case .merge: return "merging…"
            case .delete: return "deleting…"
            }
        }

        var buttonLabel: String {
            switch self {
            case .keep: return "close"
            case .merge: return "merge & close"
            case .delete: return "close & delete"
            }
        }
    }

    let workspace: Workspace
    /// Caller still owns the close + pending-request cleanup before
    /// resolving `.success`.
    let confirm: @MainActor (_ mode: Mode) async -> Outcome
    let dismiss: () -> Void

    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    @State private var mode: Mode = .keep

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

            modePicker

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
                BracketButton(primaryButtonLabel) { submit() }
                    .disabled(isWorking)
                    .opacity(isWorking ? 0.4 : 1)
            }
            .padding(.top, 22)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .frame(width: 480, alignment: .topLeading)
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }

    private var statusLabel: some View {
        Text("CLOSE-WORKTREE")
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(Theme.chromeMuted.opacity(0.85))
    }

    private var headline: some View {
        Text(workspace.title)
            .font(Theme.display(20, weight: .medium))
            .foregroundStyle(Theme.chromeForeground)
    }

    private var subtitle: some View {
        Text((worktreePath.path as NSString).abbreviatingWithTildeInPath)
            .font(Theme.mono(11.5))
            .foregroundStyle(Theme.chromeMuted)
    }

    /// Three exclusive dispositions — radio rows, not a destructive
    /// checkbox hidden under default close.
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Mode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: mode == option ? "circle.inset.filled" : "circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(mode == option ? Theme.chromeForeground : Theme.chromeMuted)
                        Text(option.label)
                            .font(Theme.mono(11.5))
                            .foregroundStyle(mode == option ? Theme.chromeForeground : Theme.chromeMuted)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
    }

    private var primaryButtonLabel: String {
        isWorking ? mode.workingLabel : mode.buttonLabel
    }

    private var worktreePath: URL {
        workspace.diskPath
    }

    private func submit() {
        isWorking = true
        errorMessage = nil
        Task {
            let outcome = await confirm(mode)
            switch outcome {
            case .success:
                dismiss()
            case let .failure(msg):
                isWorking = false
                errorMessage = msg
            }
        }
    }
}

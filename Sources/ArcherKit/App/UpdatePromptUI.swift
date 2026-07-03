import AppKit
import SwiftUI

/// Brutalist update prompt — matches the Settings window's visual language:
/// Theme.chrome* tokens, mono kebab-case labels, sharp corners, 1pt
/// hairlines, BracketButton actions. Replaces Sparkle's default AppKit alert
/// windows so the update flow doesn't fall out of archer's design system;
/// `ArcherUpdateUserDriver` is what feeds it Sparkle's real lifecycle state.
struct UpdatePromptView: View {
    @Bindable var flow: UpdateFlowController

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

            content

            HStack(spacing: 10) {
                Spacer()
                actions
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .frame(width: 460, alignment: .topLeading)
        .glassWindowBackground(fallback: Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }

    // MARK: Sections

    private var statusLabel: some View {
        Text(statusText)
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(Theme.chromeMuted.opacity(0.85))
    }

    private var headline: some View {
        Text(headlineText)
            .font(Theme.display(28, weight: .medium))
            .foregroundStyle(Theme.chromeForeground)
    }

    private var subtitle: some View {
        Text(subtitleText)
            .font(Theme.mono(11.5))
            .foregroundStyle(Theme.chromeMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        switch flow.stage {
        case let .found(_, notes, _, _) where !notes.isEmpty:
            VStack(alignment: .leading, spacing: 10) {
                Text("release-notes")
                    .font(Theme.mono(10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Theme.chromeMuted.opacity(0.85))
                ScrollView {
                    Text(notes)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.chromeForeground)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 160)
                .bracketBorder()
            }
        case .checking, .installing:
            ProgressView()
                .progressViewStyle(.linear)
        case let .downloading(progress):
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        case let .extracting(progress):
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch flow.stage {
        case .found:
            BracketButton("skip", action: flow.chooseSkip)
            BracketButton("later", action: flow.chooseDismiss)
            BracketButton("update", action: flow.chooseInstall)
        case .readyToInstall:
            BracketButton("later", action: flow.chooseDismiss)
            BracketButton("restart-and-install", action: flow.chooseInstall)
        case .checking, .downloading, .extracting:
            BracketButton("cancel", action: flow.chooseDismiss)
        case .installing:
            EmptyView()
        case .upToDate, .notFound, .error:
            BracketButton("done", action: flow.chooseDismiss)
        case .idle:
            EmptyView()
        }
    }

    // MARK: Copy

    private var statusText: String {
        switch flow.stage {
        case .idle: return ""
        case .checking: return "CHECKING…"
        case .found: return "UPDATE-AVAILABLE"
        case .downloading: return "DOWNLOADING…"
        case .extracting: return "EXTRACTING…"
        case .readyToInstall: return "READY-TO-INSTALL"
        case .installing: return "INSTALLING…"
        case .upToDate: return "UP-TO-DATE"
        case .notFound: return "NO-UPDATE"
        case .error: return "CHECK-FAILED"
        }
    }

    private var headlineText: String {
        switch flow.stage {
        case .idle: return ""
        case .checking: return "checking github…"
        case let .found(version, _, _, _): return version
        case .downloading: return "downloading update…"
        case .extracting: return "unpacking update…"
        case .readyToInstall: return "update ready"
        case .installing: return "installing…"
        case let .upToDate(version): return version
        case .notFound: return "no update found"
        case .error: return "couldn't reach github"
        }
    }

    private var subtitleText: String {
        switch flow.stage {
        case .idle: return ""
        case .checking: return "looking for a newer release."
        case .found: return "current \(ArcherApp.displayVersion)"
        case .downloading: return "verifying signature once complete."
        case .extracting: return "almost there."
        case .readyToInstall: return "archer will quit and relaunch on the new version."
        case .installing: return "quitting and relaunching…"
        case .upToDate: return "you're on the latest release."
        case let .notFound(message): return message
        case let .error(message): return message
        }
    }
}

@MainActor
final class UpdatePromptWindowController: NSWindowController {
    static let shared = UpdatePromptWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    static func presentFlow(_ flow: UpdateFlowController) {
        let controller = shared
        controller.build(flow: flow)
        if controller.window?.isVisible != true {
            controller.window?.center()
        }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build(flow: UpdateFlowController) {
        let view = UpdatePromptView(flow: flow)
        let host = NSHostingController(rootView: view)
        // NSHostingController computes its preferred size from the SwiftUI
        // root; the .frame(width:) on UpdatePromptView fixes the width and
        // lets height self-size around the content (with or without release
        // notes). Without this, the window opens at NSWindow default size.
        host.sizingOptions = .preferredContentSize

        if let window {
            window.contentViewController = host
        } else {
            let new = NSWindow(contentViewController: host)
            new.title = "Update"
            new.styleMask = [.titled, .closable]
            new.isReleasedWhenClosed = false
            new.appearance = Theme.windowAppearance
            new.configureGlassChrome()
            window = new
        }
    }
}

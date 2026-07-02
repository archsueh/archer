import AppKit
import SwiftUI

/// Custom About window. The system `orderFrontStandardAboutPanel` renders on a
/// solid white panel that can't pick up Liquid Glass, so archer hosts its own
/// — a normal archer window that gets the glass backing like every other.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 78, height: 78)
                .padding(.bottom, 12)
            Text(ArcherApp.name)
                .font(Theme.display(28, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
            Text("Version \(ArcherApp.displayVersion)")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.top, 4)
            Text(ArcherApp.tagline)
                .font(Theme.display(12))
                .foregroundStyle(Theme.chromeMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            aboutLink("Github ↗", url: ArcherApp.repositoryURL)
                .padding(.top, 14)
            Rectangle()
                .fill(Theme.chromeHairline)
                .frame(width: 32, height: 1)
                .padding(.vertical, 16)
            Text("© \(ArcherApp.copyrightYear) \(ArcherApp.name). All rights reserved.")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.chromeFaint)
            HStack(spacing: 0) {
                Text("Built with ❤️ by ")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeFaint)
                aboutLink(ArcherApp.author, url: ArcherApp.authorURL, font: Theme.mono(9))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 36)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(width: 360)
        .glassWindowBackground(fallback: Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }

    private func aboutLink(_ title: String, url: URL, font: Font = Theme.mono(11)) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Text(title)
                .font(font)
                .foregroundStyle(Theme.chromeForeground)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not a storyboard window")
    }

    func show() {
        buildWindowIfNeeded()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindowIfNeeded() {
        guard window == nil else { return }
        let host = NSHostingController(rootView: AboutView())
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "About \(ArcherApp.name)"
        window.styleMask = [.titled, .closable]
        // Name/version live in the content, so hide the titlebar text.
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        window.configureGlassChrome()
        self.window = window
    }
}

private extension View {
    /// Pointing-hand cursor on hover — links should feel clickable.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

import AppKit
import SwiftUI

// MARK: - Log Panel Window Controller

final class LogPanelWindowController: NSWindowController {
    static let shared = LogPanelWindowController()
    private var host: NSHostingController<LogPanelView>?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    static func show() {
        let controller = shared
        controller.buildWindowIfNeeded()
        if controller.window?.isVisible != true { controller.window?.center() }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindowIfNeeded() {
        guard window == nil else { return }
        let view = LogPanelView()
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Log"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.minSize = NSSize(width: 480, height: 260)
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        self.window = window
    }
}

// MARK: - Log Panel View

struct LogPanelView: View {
    @State private var log = BridgeEventLog.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            if log.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("LOG")
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.chromeForeground.opacity(0.5))
                .tracking(1.5)
            Spacer()
            Text("\(log.entries.count) entries")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.trailing, 8)
            Button("Clear") { log.clear() }
                .buttonStyle(PlainButtonStyle())
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.chromeActive)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No activity yet")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.chromeMuted)
            Text("Bridge commands and hook events will appear here.")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(log.entries) { entry in
                    LogEntryRow(entry: entry, formatter: Self.timeFormatter)
                    Rectangle().fill(Theme.chromeHairline.opacity(0.5)).frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: BridgeEventLog.Entry
    let formatter: DateFormatter

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formatter.string(from: entry.timestamp))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
                .frame(width: 60, alignment: .leading)

            Text(entry.category.rawValue)
                .font(Theme.mono(9, weight: .semibold))
                .foregroundStyle(categoryColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(categoryColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(entry.summary)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeForeground.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var categoryColor: Color {
        switch entry.category {
        case .bridge: return Theme.activityRunning
        case .hook: return Theme.activityAttention
        }
    }
}

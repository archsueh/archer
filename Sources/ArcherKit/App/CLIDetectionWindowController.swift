import AppKit
import SwiftUI

/// Shown once at first launch (after ghostty onboarding) to surface which
/// AI CLI tools Archer detected on this machine. Read-only: no install buttons,
/// no close button — user continues via the "Continue" button.
final class CLIDetectionWindowController: NSWindowController {
    private var host: NSHostingController<CLIDetectionView>?
    private var onContinue: (() -> Void)?

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        super.init(window: nil)
        buildWindow()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func buildWindow() {
        let view = CLIDetectionView {
            self.window?.orderOut(nil)
            self.onContinue?()
        }
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Archer — CLI Tools"
        window.styleMask = [.titled]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        self.window = window
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Detection helpers (nonisolated)

private let cliToolDefs: [(name: String, command: String)] = [
    ("Claude Code", "claude"),
    ("Antigravity CLI", "agy"),
    ("Hermes", "hermes"),
    ("Codex", "codex"),
    ("Gemini CLI", "gemini"),
]

private func cliResolvedPath(for command: String) -> String? {
    if let p = cliShell("which", command)?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
        return p
    }
    let home = NSHomeDirectory()
    let candidates = [
        "\(home)/Library/Application Support/archer/bin/\(command)",
        "/opt/homebrew/bin/\(command)",
        "/usr/local/bin/\(command)",
        "/usr/bin/\(command)",
        "\(home)/.local/bin/\(command)",
        "\(home)/.npm-global/bin/\(command)",
        "\(home)/.cargo/bin/\(command)",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func cliShell(_ cmd: String, _ arg: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = [cmd, arg]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}

// MARK: - View

struct CLIDetectionView: View {
    let onContinue: () -> Void

    @State private var results: [ToolResult] = []
    @State private var isScanning = true

    struct ToolResult: Identifiable {
        let id = UUID()
        let name: String
        let command: String
        let path: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar

            if isScanning {
                Spacer()
                ProgressView("Scanning…")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeMuted)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        toolList
                    }
                    .padding(32)
                }

                Divider()
                    .background(Theme.chromeHairline)

                HStack {
                    Spacer()
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(Theme.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.chromeForeground)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .overlay(Rectangle().stroke(Theme.chromeHairline, lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
        }
        .background(Theme.chromeBackground)
        .onAppear { scan() }
    }

    private var titlebar: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.chromeMuted)
            Text("CLI Tools")
                .font(Theme.mono(12, weight: .bold))
                .foregroundStyle(Theme.chromeForeground)
            Spacer()
        }
        .frame(height: 48)
        .padding(.horizontal, 32)
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本机 CLI 工具")
                .font(Theme.display(22, weight: .semibold))
                .foregroundStyle(Theme.chromeForeground)
            Text("Archer 已扫描常用安装路径。未检测到不影响启动。")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
        }
    }

    private var toolList: some View {
        VStack(spacing: 0) {
            ForEach(results) { result in
                HStack(spacing: 14) {
                    Circle()
                        .fill(result.path != nil ? Theme.activityRunning : Theme.chromeMuted.opacity(0.3))
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name)
                            .font(Theme.mono(13, weight: .bold))
                            .foregroundStyle(Theme.chromeForeground)
                        Text(result.path ?? "未检测到")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(result.path != nil ? Theme.chromeMuted : Theme.chromeMuted.opacity(0.5))
                    }

                    Spacer()

                    Text(result.path != nil ? "✓" : "—")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(result.path != nil ? Theme.activityRunning : Theme.chromeMuted.opacity(0.4))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .overlay(
                    VStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                    }
                )
            }
        }
        .bracketBorder()
    }

    private func scan() {
        Task.detached(priority: .userInitiated) {
            let found = cliToolDefs.map { tool in
                ToolResult(
                    name: tool.name,
                    command: tool.command,
                    path: cliResolvedPath(for: tool.command)
                )
            }
            await MainActor.run {
                results = found
                isScanning = false
            }
        }
    }
}

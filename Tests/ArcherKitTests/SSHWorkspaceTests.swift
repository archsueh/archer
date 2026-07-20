@testable import ArcherKit
import XCTest

/// Pure-logic coverage for the SSH-workspace surface: host normalization,
/// logout marker, remote-paste filename sanitization. No PTY / network.
@MainActor
final class SSHWorkspaceTests: XCTestCase {
    // MARK: - normalizedSSHHost

    func testNormalizedSSHHostTrimsAndRejectsBlank() {
        XCTAssertEqual(WorkspaceStore.normalizedSSHHost("  user@host  "), "user@host")
        XCTAssertEqual(WorkspaceStore.normalizedSSHHost("host"), "host")
        XCTAssertNil(WorkspaceStore.normalizedSSHHost(nil))
        XCTAssertNil(WorkspaceStore.normalizedSSHHost(""))
        XCTAssertNil(WorkspaceStore.normalizedSSHHost("   \n\t  "))
    }

    // MARK: - RemoteLoginMarker logout

    func testLogoutTitleIsDistinctFromLoginPrefix() {
        XCTAssertEqual(RemoteLoginMarker.logoutTitle, "archer-remote-logout")
        XCTAssertTrue(RemoteLoginMarker.isLogoutTitle("archer-remote-logout"))
        XCTAssertTrue(RemoteLoginMarker.isLogoutTitle("  archer-remote-logout  "))
        XCTAssertFalse(RemoteLoginMarker.isLogoutTitle("archer-remote-login:host"))
        XCTAssertFalse(RemoteLoginMarker.isLogoutTitle("other"))
        XCTAssertFalse(RemoteLoginMarker.isLogoutTitle(""))
    }

    func testParseLoginTitleStillWorks() {
        XCTAssertEqual(RemoteLoginMarker.parseTitle("archer-remote-login:user@host"), "user@host")
        XCTAssertEqual(RemoteLoginMarker.parseTitle("  archer-remote-login:box  "), "box")
        XCTAssertNil(RemoteLoginMarker.parseTitle("archer-remote-login:"))
        XCTAssertNil(RemoteLoginMarker.parseTitle("archer-remote-logout"))
        XCTAssertNil(RemoteLoginMarker.parseTitle("not-a-marker"))
    }

    // MARK: - remote paste filename sanitize / dest

    func testSanitizedRemotePasteFilename() {
        XCTAssertEqual(
            ArcherShellIntegration.sanitizedRemotePasteFilename("photo.png"),
            "photo.png"
        )
        XCTAssertEqual(
            ArcherShellIntegration.sanitizedRemotePasteFilename("my file (1).png"),
            "my_file__1_.png"
        )
        XCTAssertEqual(
            ArcherShellIntegration.sanitizedRemotePasteFilename("..."),
            "paste"
        )
        XCTAssertEqual(
            ArcherShellIntegration.sanitizedRemotePasteFilename(""),
            "paste"
        )
    }

    func testRemotePasteDestinationsDedup() {
        let dir = "/tmp/archer-pastes-test"
        let urls = [
            URL(fileURLWithPath: "/a/report.pdf"),
            URL(fileURLWithPath: "/b/report.pdf"),
            URL(fileURLWithPath: "/c/notes.txt"),
        ]
        let dests = ArcherShellIntegration.remotePasteDestinations(for: urls, remoteDir: dir)
        XCTAssertEqual(dests.map(\.remotePath), [
            "\(dir)/report.pdf",
            "\(dir)/report-2.pdf",
            "\(dir)/notes.txt",
        ])
    }

    // MARK: - AgentTemplate ssh composition

    func testMakeSessionConfigSSHWrapsPlainTerminal() {
        let config = AgentTemplate.terminal.makeSessionConfig(sshHost: "user@box")
        let launch = config.environment["ARCHER_AGENT"]
        XCTAssertNotNil(launch)
        XCTAssertTrue(launch?.hasPrefix("archer-ssh ") == true, launch ?? "nil")
        XCTAssertTrue(launch?.contains("user@box") == true, launch ?? "nil")
        // Plain terminal has no agent suffix after `--`
        XCTAssertFalse(launch?.contains(" -- ") == true, launch ?? "nil")
    }

    func testMakeSessionConfigSSHWrapsAgentBehindDashDash() throws {
        let config = AgentTemplate.claudeCode.makeSessionConfig(
            resumeId: "local-sess-id",
            initialPrompt: nil,
            sshHost: "devbox"
        )
        let launch = try XCTUnwrap(config.environment["ARCHER_AGENT"])
        XCTAssertTrue(launch.hasPrefix("archer-ssh "))
        XCTAssertTrue(launch.contains(" -- claude"), launch)
        // Resume must be dropped on remote
        XCTAssertFalse(launch.contains("--resume"), launch)
        XCTAssertFalse(launch.contains("local-sess-id"), launch)
    }

    // MARK: - Persistence round-trip

    func testPersistedWorkspaceEncodesSSHHost() throws {
        let pane = Pane()
        let root = PaneNode(pane: pane)
        let ws = Workspace(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()), root: root)
        ws.sshRemoteHost = "user@remote"
        let persisted = PersistedWorkspace(ws)
        XCTAssertEqual(persisted.sshRemoteHost, "user@remote")

        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedWorkspace.self, from: data)
        XCTAssertEqual(decoded.sshRemoteHost, "user@remote")
    }

    func testPersistedWorkspaceDecodesMissingSSHHostAsNil() throws {
        let pane = PersistedPane(id: UUID(), tabs: [], activeTabId: nil)
        let root = PersistedPaneNode(id: UUID(), kind: .pane(pane))
        let bare = PersistedWorkspace(
            id: UUID(),
            workingDirectoryPath: "/tmp",
            root: root
        )
        let data = try JSONEncoder().encode(bare)
        let decoded = try JSONDecoder().decode(PersistedWorkspace.self, from: data)
        XCTAssertNil(decoded.sshRemoteHost)
    }

    // MARK: - ssh wrapper script branding

    func testSSHWrapperContainsArcherBrandingAndLogout() {
        let script = ArcherShellIntegration.sshWrapperScript
        XCTAssertTrue(script.contains("archer-ssh"))
        XCTAssertTrue(script.contains(RemoteLoginMarker.titlePrefix))
        XCTAssertTrue(script.contains(RemoteLoginMarker.logoutTitle))
        XCTAssertTrue(script.contains("ControlPath=/tmp/archer-ssh-%C"))
        XCTAssertTrue(script.contains("ARCHER_REMOTE_AGENT"))
        // Must not carry upstream kooky branding
        XCTAssertFalse(script.contains("kooky-ssh"))
        XCTAssertFalse(script.contains("KOOKY_REMOTE_AGENT"))
    }

    func testRemoteBootstrapEvalsRemoteAgent() {
        let bootstrap = ArcherShellIntegration.remoteAgentBootstrapScript
        XCTAssertTrue(bootstrap.contains("ARCHER_REMOTE_AGENT"))
        XCTAssertTrue(bootstrap.contains("archer-agent-markers"))
        XCTAssertFalse(bootstrap.contains("KOOKY_REMOTE_AGENT"))
    }
}

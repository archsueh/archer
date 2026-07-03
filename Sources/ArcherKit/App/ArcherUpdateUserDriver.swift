import Foundation
import Sparkle

/// Bridges Sparkle's `SPUUserDriver` callbacks onto `UpdateFlowController`,
/// which `UpdatePromptView` renders in Archer's own glass chrome. This exists
/// so adopting Sparkle (real background download + verified install) doesn't
/// mean falling back to Sparkle's default AppKit alert windows — see the
/// "Replaces the system NSAlert" note on `UpdatePromptView`.
@MainActor
final class ArcherUpdateUserDriver: NSObject, SPUUserDriver {
    private let flow: UpdateFlowController
    private var expectedContentLength: UInt64 = 0
    private var receivedContentLength: UInt64 = 0

    init(flow: UpdateFlowController) {
        self.flow = flow
    }

    private func present() {
        UpdatePromptWindowController.presentFlow(flow)
    }

    // MARK: Permission (should not fire — SUEnableAutomaticChecks is set explicitly in Info.plist)

    func show(_: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    // MARK: Checking

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        flow.cancellation = cancellation
        flow.stage = .checking
        present()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state _: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        flow.foundReply = reply
        flow.stage = .found(
            version: appcastItem.displayVersionString,
            notes: appcastItem.itemDescription ?? "",
            informationOnly: appcastItem.isInformationOnlyUpdate,
            infoURL: appcastItem.infoURL
        )
        present()
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard case let .found(version, _, informationOnly, infoURL) = flow.stage,
              let text = String(data: downloadData.data, encoding: .utf8) else { return }
        flow.stage = .found(version: version, notes: text, informationOnly: informationOnly, infoURL: infoURL)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_: Error) {
        // Keep whatever notes (if any) were already inline in the appcast item.
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        flow.acknowledgement = acknowledgement
        let nsError = error as NSError
        let reason = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        if let reason, reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue {
            flow.stage = .upToDate(version: ArcherApp.displayVersion)
        } else {
            flow.stage = .notFound(message: error.localizedDescription)
        }
        present()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        flow.acknowledgement = acknowledgement
        flow.stage = .error(message: error.localizedDescription)
        present()
    }

    // MARK: Downloading

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedContentLength = 0
        receivedContentLength = 0
        flow.cancellation = cancellation
        flow.stage = .downloading(progress: nil)
        present()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedContentLength += length
        guard expectedContentLength > 0 else {
            flow.stage = .downloading(progress: nil)
            return
        }
        flow.stage = .downloading(progress: Double(receivedContentLength) / Double(expectedContentLength))
    }

    func showDownloadDidStartExtractingUpdate() {
        flow.stage = .extracting(progress: 0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        flow.stage = .extracting(progress: progress)
    }

    // MARK: Install

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        flow.readyReply = reply
        flow.stage = .readyToInstall
        present()
    }

    func showInstallingUpdate(withApplicationTerminated _: Bool, retryTerminatingApplication _: @escaping () -> Void) {
        flow.stage = .installing
        present()
    }

    func showUpdateInstalledAndRelaunched(_: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        flow.stage = .idle
    }

    func dismissUpdateInstallation() {
        flow.stage = .idle
        UpdatePromptWindowController.shared.window?.close()
    }

    func showUpdateInFocus() {
        present()
    }
}

import Foundation
import Sparkle

/// Shared state between `ArcherUpdateUserDriver` (Sparkle's callback surface)
/// and `UpdatePromptView` (Archer's glass-styled UI). The driver writes
/// `stage` and stashes the reply closure Sparkle gave it; the view reads
/// `stage` and calls back through `chooseInstall()` / `chooseDismiss()` /
/// `chooseSkip()`, which forward into whichever reply Sparkle is waiting on.
@MainActor
@Observable
final class UpdateFlowController {
    enum Stage: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case found(version: String, notes: String, informationOnly: Bool, infoURL: URL?)
        case downloading(progress: Double?) // nil = indeterminate (no content-length yet)
        case extracting(progress: Double)
        case readyToInstall
        case installing
        case notFound(message: String)
        case error(message: String)
    }

    var stage: Stage = .idle

    /// Reply for `showUpdateFoundWithAppcastItem:state:reply:`.
    var foundReply: ((SPUUserUpdateChoice) -> Void)?
    /// Reply for `showReadyToInstallAndRelaunch:`.
    var readyReply: ((SPUUserUpdateChoice) -> Void)?
    /// Cancellation for an in-flight check or download.
    var cancellation: (() -> Void)?
    /// Acknowledgement Sparkle wants once an error/no-update screen is dismissed.
    var acknowledgement: (() -> Void)?

    func chooseInstall() {
        foundReply?(.install)
        readyReply?(.install)
        clearReplies()
    }

    func chooseDismiss() {
        foundReply?(.dismiss)
        readyReply?(.dismiss)
        cancellation?()
        acknowledgement?()
        clearReplies()
        stage = .idle
    }

    func chooseSkip() {
        foundReply?(.skip)
        clearReplies()
        stage = .idle
    }

    private func clearReplies() {
        foundReply = nil
        readyReply = nil
        cancellation = nil
        acknowledgement = nil
    }
}

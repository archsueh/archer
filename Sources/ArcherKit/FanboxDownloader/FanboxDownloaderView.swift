import SwiftUI

/// Right-side Fanbox Downloader panel.
/// Fits a 280px-wide sidebar, matching the design of FilePanelView and DiffPanelView.
public struct FanboxDownloaderView: View {
    @ObservedObject private var queueManager = DownloadQueueManager.shared
    // [archer] begin: review manager
    @ObservedObject private var reviewManager = ClassificationReviewManager.shared
    // [archer] end: review manager
    @State private var inputIds: String = ""
    let rootURL: URL
    let onFinished: () -> Void
    var width: Double

    public init(rootURL: URL, onFinished: @escaping () -> Void = {}, width: Double = 280) {
        self.rootURL = rootURL
        self.onFinished = onFinished
        self.width = width
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            
            inputSection
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            
            // [archer] begin: pending review section
            if !reviewManager.pendingMoves.isEmpty {
                pendingClassificationSection
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            }
            // [archer] end: pending review section
            
            queueHeader
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            
            jobListView
        }
        .frame(width: CGFloat(width))
        .background(Theme.chromeBackground)
    }

    // MARK: - Views

    private var header: some View {
        HStack(spacing: 6) {
            Text(L10n.string("Fanbox Downloader"))
                .font(Theme.display(12, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
            
            Spacer()
            
            Text("\(queueManager.activeJobs.count) jobs")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeMuted)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text("POST IDS")
                .font(Theme.display(10, weight: .bold))
                .foregroundStyle(Theme.chromeMuted)
            
            TextField("Paste IDs (comma/space separated)", text: $inputIds)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.chromeForeground)
                .textFieldStyle(.plain)
                .padding(Theme.space2)
                .background(Theme.chromeHairline.opacity(0.12))
                .bracketBorder()
            
            HStack {
                Spacer()
                BracketButton("DOWNLOAD") {
                    triggerDownload()
                }
                .disabled(inputIds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.space3)
    }

    private var queueHeader: some View {
        HStack {
            Text("DOWNLOAD QUEUE")
                .font(Theme.display(10, weight: .bold))
                .foregroundStyle(Theme.chromeMuted)
            Spacer()
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 6)
        .background(Theme.chromeHairline.opacity(0.3))
    }

    private var jobListView: some View {
        Group {
            if queueManager.activeJobs.isEmpty {
                emptyQueueView
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(queueManager.activeJobs) { job in
                            JobRow(job: job)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyQueueView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.chromeMuted)
            Text("Queue is empty")
                .font(Theme.display(11))
                .foregroundStyle(Theme.chromeMuted)
            Spacer()
        }
    }

    // MARK: - Actions

    private func triggerDownload() {
        let rawIds = inputIds
            .replacingOccurrences(of: ",", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !rawIds.isEmpty else { return }
        
        inputIds = ""
        queueManager.downloadPosts(postIds: rawIds, targetDir: rootURL, onFinished: onFinished)
    }

    // [archer] begin: pending classification section view
    private var pendingClassificationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PENDING CLASSIFICATION")
                    .font(Theme.display(10, weight: .bold))
                    .foregroundStyle(Theme.chromeMuted)
                Spacer()
                HStack(spacing: 8) {
                    Button("Approve All") {
                        reviewManager.approveAll(onFinished: onFinished)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.gitInsertion)
                    
                    Text("·")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.chromeMuted)
                    
                    Button("Decline All") {
                        reviewManager.declineAll()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.gitDeletion)
                }
            }
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, 6)
            .background(Theme.chromeHairline.opacity(0.3))
            
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(reviewManager.pendingMoves) { move in
                        PendingMoveRow(move: move, reviewManager: reviewManager, onFinished: onFinished)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 180)
        }
    }
    // [archer] end: pending classification section view
}

// [archer] begin: PendingMoveRow
private struct PendingMoveRow: View {
    let move: PendingMove
    @ObservedObject var reviewManager: ClassificationReviewManager
    let onFinished: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.chromeMuted)
                
                Text(move.source.lastPathComponent)
                    .font(Theme.mono(10.5, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                
                Spacer()
            }
            
            HStack(spacing: 6) {
                Text("Move to:")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeMuted)
                
                Text(move.rule.folder)
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Approve") {
                        reviewManager.approve(move, onFinished: onFinished)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.gitInsertion)
                    
                    Button("Decline") {
                        reviewManager.decline(move)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.gitDeletion)
                }
            }
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 6)
        .background(hovered ? Theme.chromeHover : Color.clear)
        .onHover { hovered = $0 }
    }
}
// [archer] end: PendingMoveRow

// MARK: - Job Row

private struct JobRow: View {
    let job: DownloadJob
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            statusIcon(job.status)
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(job.title)
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                
                Text(statusDetail)
                    .font(Theme.mono(9))
                    .foregroundStyle(statusColor)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, 6)
        .background(hovered ? Theme.chromeHover : Color.clear)
        .onHover { hovered = $0 }
    }

    private var statusDetail: String {
        switch job.status {
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading..."
        case .completed:
            return "Completed · \(job.filesCount) files"
        case .failed:
            return "Failed"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:
            return Theme.chromeMuted
        case .downloading:
            return Theme.activityRunning
        case .completed:
            return Theme.gitInsertion
        case .failed:
            return Theme.gitDeletion
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: DownloadJobStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.chromeMuted)
        case .downloading:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 11, height: 11)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.gitInsertion)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.gitDeletion)
        }
    }
}

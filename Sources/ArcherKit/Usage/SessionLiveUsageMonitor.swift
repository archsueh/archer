import Darwin
import Foundation

// [archer] File-watch driven session cost updates. Mirrors CodexUsageMonitor:
// resolve path → DispatchSource on write/extend → debounced force-refresh of
// SessionLiveUsageLookup. Poll only while the log file is not yet present.

/// Watches agent log files and republishes live session cost. // [archer]
@MainActor
final class SessionLiveUsageMonitor {
    static let shared = SessionLiveUsageMonitor()

    private struct Watch {
        let path: String
        let tool: String
        let sessionKey: String
        let cwd: URL
        let source: DispatchSourceFileSystemObject
        var pendingRead: DispatchWorkItem?
    }

    private var watches: [UUID: Watch] = [:]
    /// Generation token per surface — drops stale resolve/read/retry work. // [archer]
    private var generation: [UUID: Int] = [:]

    /// (Re)start watching for this Archer tab (`surfaceId` = `Session.id`).
    /// Publishes immediately when data exists, then on every debounced file
    /// change. Retries path resolve for ~30s when the log is not written yet. // [archer]
    func start(
        surfaceId: UUID,
        tool: String,
        conversationId: String?,
        cwd: URL,
        attempt: Int = 0,
        update: @MainActor @escaping (SessionLiveUsage?) -> Void
    ) {
        let token = (generation[surfaceId] ?? 0) + 1
        generation[surfaceId] = token

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let sessionKey = SessionLiveUsageSource.resolveSessionKey(
                tool: tool,
                conversationId: conversationId,
                cwd: cwd
            )
            let pathURL: URL?
            if let sessionKey {
                pathURL = SessionLiveUsagePaths.resolve(
                    tool: tool,
                    sessionID: sessionKey,
                    cwd: cwd
                )
            } else {
                pathURL = nil
            }

            // Seed usage even before watch attaches (force bypasses TTL).
            let seed: SessionLiveUsage?
            if let sessionKey {
                seed = SessionLiveUsageLookup.usage(
                    sessionID: sessionKey,
                    tool: tool,
                    preferredSourcePath: pathURL?.path,
                    force: true
                )
            } else {
                seed = nil
            }

            DispatchQueue.main.async {
                guard let self, self.generation[surfaceId] == token else { return }
                update(seed)

                guard let sessionKey, let pathURL else {
                    // No key or file yet — retry like CodexUsageMonitor.
                    guard attempt < 30 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard let self, self.generation[surfaceId] == token else { return }
                        self.start(
                            surfaceId: surfaceId,
                            tool: tool,
                            conversationId: conversationId,
                            cwd: cwd,
                            attempt: attempt + 1,
                            update: update
                        )
                    }
                    return
                }

                if self.watches[surfaceId]?.path != pathURL.path {
                    self.install(
                        surfaceId: surfaceId,
                        path: pathURL.path,
                        tool: tool,
                        sessionKey: sessionKey,
                        cwd: cwd,
                        conversationId: conversationId,
                        update: update
                    )
                }
                self.scheduleRead(surfaceId: surfaceId, update: update)
            }
        }
    }

    func stop(surfaceId: UUID) {
        guard watches[surfaceId] != nil || generation[surfaceId] != nil else { return }
        generation[surfaceId] = (generation[surfaceId] ?? 0) + 1
        if let watch = watches.removeValue(forKey: surfaceId) {
            watch.pendingRead?.cancel()
            watch.source.cancel()
        }
    }

    func stopAll() {
        for id in Array(watches.keys) {
            stop(surfaceId: id)
        }
        for id in Array(generation.keys) where watches[id] == nil {
            generation[id] = (generation[id] ?? 0) + 1
        }
    }

    // MARK: - Watch install

    private func install(
        surfaceId: UUID,
        path: String,
        tool: String,
        sessionKey: String,
        cwd: URL,
        conversationId: String?,
        update: @MainActor @escaping (SessionLiveUsage?) -> Void
    ) {
        if let existing = watches.removeValue(forKey: surfaceId) {
            existing.pendingRead?.cancel()
            existing.source.cancel()
        }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                // Log rotated or deleted — re-resolve and reattach.
                self.stop(surfaceId: surfaceId)
                self.start(
                    surfaceId: surfaceId,
                    tool: tool,
                    conversationId: conversationId,
                    cwd: cwd,
                    update: update
                )
                return
            }
            self.scheduleRead(surfaceId: surfaceId, update: update)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watches[surfaceId] = Watch(
            path: path,
            tool: tool,
            sessionKey: sessionKey,
            cwd: cwd,
            source: source,
            pendingRead: nil
        )
    }

    /// Debounce ~200ms — agents often append several lines per turn. // [archer]
    private func scheduleRead(
        surfaceId: UUID,
        update: @MainActor @escaping (SessionLiveUsage?) -> Void
    ) {
        guard var watch = watches[surfaceId] else { return }
        watch.pendingRead?.cancel()
        let tool = watch.tool
        let sessionKey = watch.sessionKey
        let path = watch.path
        let token = (generation[surfaceId] ?? 0) + 1
        generation[surfaceId] = token
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.global(qos: .utility).async {
                // Invalidate TTL cache so we re-fold from the watched file.
                SessionLiveUsageLookup.invalidate(sessionID: sessionKey, tool: tool)
                let usage = SessionLiveUsageLookup.usage(
                    sessionID: sessionKey,
                    tool: tool,
                    preferredSourcePath: path,
                    force: true
                )
                DispatchQueue.main.async {
                    guard let self, self.generation[surfaceId] == token else { return }
                    update(usage)
                }
            }
        }
        watch.pendingRead = work
        watches[surfaceId] = watch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}

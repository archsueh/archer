import AppKit
import IOKit.pwr_mgt
import SwiftUI

// MARK: - Model

/// One dial, three notches of sleep protection.
enum AwakeMode: String, CaseIterable {
    /// Never interferes with sleep.
    case off
    /// Stays awake while agents or SSH work (lid included once the helper
    /// is authorized), sleeps normally again when the work ends.
    case auto
    /// The strongest tier (Capsomnia model): never sleeps at all until
    /// switched down. Requires the privileged helper.
    case always
}

/// Holds a `PreventUserIdleSystemSleep` power assertion while the terminal
/// is busy — any coding agent actively running, or any live SSH session —
/// so an unattended Mac doesn't idle-sleep out from under the work.
/// Display sleep stays allowed — only the system nap is blocked — and a
/// closed lid still forces sleep (a macOS rule no app can override).
///
/// Mirrors `NotificationInbox` / `AgentMonitor`: a `@MainActor @Observable`
/// singleton. State is *derived* — `refresh()` recomputes "should we hold
/// an assertion" from the settings toggle + the cross-window agent set,
/// and the `withObservationTracking` loop re-runs it whenever either
/// input changes. The assertion dies with the process, so quit needs no
/// cleanup path.
@MainActor
@Observable
final class SleepGuard {
    static let shared = SleepGuard()
    /// `internal` (not `private`) so tests can build an isolated instance.
    init() {}

    /// True while the assertion is held — drives the top-strip button's
    /// "actively keeping the Mac awake" copy. Computed off `assertionID`
    /// (stored, thus observation-tracked).
    var isKeepingAwake: Bool {
        assertionID != nil
    }

    /// True while lid sleep is disabled system-wide on our behalf (closed-lid
    /// mode engaged around the current busy window).
    private(set) var lidSleepDisabled = false

    /// Input seams — tests swap these; the defaults read the live app state.
    var awakeMode: @MainActor () -> AwakeMode = {
        ArcherSettingsModel.shared.awakeMode
    }

    /// Dial writeback for external-change reconciliation — the no-install
    /// variant of the model's single dial entry (reconcile must never pop
    /// the auth dialog).
    var setMode: @MainActor (AwakeMode) -> Void = {
        ArcherSettingsModel.shared.applyAwakeMode($0, runInstall: false)
    }

    /// Whether the one-time privileged helper is authorized. Gates the
    /// lid-sleep layer for BOTH modes; auto mode silently degrades to
    /// idle-only protection without it.
    var helperReady: @MainActor () -> Bool = {
        ClosedLidSleep.isInstalled
    }

    /// Seam over the privileged pmset call.
    var setLidSleep: @MainActor (_ disabled: Bool, _ done: @escaping @MainActor (Bool) -> Void) -> Void = { disabled, done in
        ClosedLidSleep.setDisabled(disabled, completion: done)
    }

    /// Ownership-marker seams (real file writes — tests inject no-ops, the
    /// same opt-in rule as every other write seam in this codebase).
    var markOwnership: @MainActor () -> Void = { ClosedLidSleep.markLidOwnership() }
    var clearOwnership: @MainActor () -> Void = { ClosedLidSleep.clearLidOwnership() }
    /// Engage-failure feedback (helper broken / sudo denied). The `always`
    /// tier is helper-dependent by definition — step it down so Settings
    /// shows the truth. `auto` just degrades to idle-only protection
    /// (the engage-block stops retries).
    var onLidHelperFailure: @MainActor () -> Void = {
        if ArcherSettingsModel.shared.awakeMode == .always {
            ArcherSettingsModel.shared.applyAwakeMode(.auto, runInstall: false)
        }
    }

    /// "Busy" = an agent is working, or an SSH conversation is live —
    /// `AgentMonitor.hasActiveWork`, the cross-window aggregation's own
    /// predicate. Reading it registers observation on each session's
    /// `activityState` / `remoteHost`, so state changes re-fire refresh.
    var hasActiveWork: @MainActor () -> Bool = {
        AgentMonitor.shared.hasActiveWork
    }

    /// IOKit seams — tests count calls instead of touching real power
    /// management. A create failure returns nil (treated as "not held",
    /// retried on the next refresh).
    var createAssertion: @MainActor () -> IOPMAssertionID? = {
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "archer: agent or SSH session active" as CFString,
            &id
        )
        return status == kIOReturnSuccess ? id : nil
    }

    var releaseAssertion: @MainActor (IOPMAssertionID) -> Void = {
        IOPMAssertionRelease($0)
    }

    private var assertionID: IOPMAssertionID?
    private var observing = false
    private var lidCallInFlight = false
    /// Set when engaging lid sleep fails; blocks further engage attempts for
    /// the rest of this busy window (cleared when the work ends). Without it
    /// a failure whose handler doesn't flip the setting would retry-loop —
    /// the completion re-runs refresh, which would immediately re-engage.
    private var lidEngageBlocked = false
    /// Set when RELEASING lid sleep fails (helper broken?): the system very
    /// likely still has SleepDisabled 1, so `lidSleepDisabled` stays true —
    /// keeping shutdown cleanup armed — and this flag stops the
    /// completion→refresh loop from retrying instantly. The next poll that
    /// confirms reality clears it, giving a calm ~30s retry cadence.
    private var lidReleaseBlocked = false
    /// Bumped on every local lid mutation and absorbed reconcile. A poll
    /// captures the generation when it starts; a result from a stale
    /// generation is dropped — otherwise a pre-engage snapshot landing
    /// after the engage would read as an external release and veto the
    /// user's dial.
    private var lidGeneration = 0

    /// Called once at launch, after `AgentMonitor.storesProvider` is wired.
    /// Launch reconciliation runs to completion BEFORE the observation loop
    /// starts — otherwise a crash-straggler `off` races the Always-restore
    /// `on`, and whichever sudo lands last wins. Idempotent.
    func start() {
        guard !observing else { return }
        observing = true
        Task { @MainActor in
            await reconcileAtLaunch()
            observe()
            startSystemStateWatch()
        }
    }

    /// The system-wide SleepDisabled flag is shared territory — the user
    /// can flip it in any terminal (`sudo pmset -a disablesleep …`) or via
    /// another tool, and Archer's light/Settings must not show stale state.
    /// No change notification exists for it, so: poll every 30s, plus an
    /// immediate check whenever Archer becomes the active app (the moment
    /// right after someone flipped it in a terminal). Only meaningful once
    /// the helper exists (without it Archer never engages the lid layer and
    /// has no authority to reconcile).
    private func startSystemStateWatch() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pollSystemLidState() }
        }
        Task { @MainActor [weak self] in
            while let self, self.observing {
                try? await Task.sleep(for: .seconds(30))
                // Skip the recurring subprocess while the dial is off and
                // nothing is engaged — the app-activation check still
                // reconciles external changes the moment Archer is fronted.
                if self.awakeMode() != .off || self.lidSleepDisabled {
                    self.pollSystemLidState()
                }
            }
        }
    }

    private func pollSystemLidState() {
        guard helperReady() else { return }
        let generation = lidGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let system = ClosedLidSleep.systemSleepCurrentlyDisabled()
            Task { @MainActor in
                guard let self, let system, generation == self.lidGeneration else { return }
                self.reconcileExternalLidState(systemDisabled: system)
            }
        }
    }

    /// Absorb an out-of-band SleepDisabled change so reflects reality.
    /// External OFF is an explicit user veto: the Always notch drops all
    /// the way to Off (Auto would re-arm on the next busy window, fighting
    /// the user), and no lid re-engage for the rest of this busy window.
    /// External ON surfaces as the Always notch (switching away in Archer
    /// then releases it).
    func reconcileExternalLidState(systemDisabled: Bool) {
        guard systemDisabled != lidSleepDisabled else {
            // Reality confirmed. If a failed release left its block set,
            // lift it so refresh can try again on this calm cadence.
            if lidReleaseBlocked {
                lidReleaseBlocked = false
                refresh()
            }
            return
        }
        lidGeneration += 1
        lidSleepDisabled = systemDisabled
        lidReleaseBlocked = false
        if systemDisabled {
            markOwnership() // archer manages it from here
            if awakeMode() != .always { setMode(.always) }
        } else {
            clearOwnership()
            lidEngageBlocked = true
            if awakeMode() == .always { setMode(.off) }
        }
        refresh()
    }

    /// Sort out a system SleepDisabled flag that predates this process.
    /// The ownership marker distinguishes two very different situations:
    /// - marker present → archer set it. Crash straggler: clear it — unless
    ///   the persisted dial is Always, then adopt it and keep holding.
    /// - marker absent → the user or another tool set it on purpose:
    ///   absorb it as the Always notch, never silently clear it.
    private func reconcileAtLaunch() async {
        guard ClosedLidSleep.isInstalled else { return }
        let system = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: ClosedLidSleep.systemSleepCurrentlyDisabled())
            }
        }
        guard let system else { return } // unknown → touch nothing
        if system {
            if ClosedLidSleep.ownsLidState, awakeMode() != .always {
                // Our crash straggler. Clear it and WAIT for the sudo to
                // land, so the observe loop can't race an `on` against it.
                await withCheckedContinuation { cont in
                    ClosedLidSleep.setDisabled(false) { _ in cont.resume() }
                }
                clearOwnership()
            } else {
                // Ours + Always persisted → adopt and keep holding.
                // Not ours → surface as Always; Archer takes ownership and
                // dialing away in Archer will release it.
                lidSleepDisabled = true
                markOwnership()
                if awakeMode() != .always { setMode(.always) }
            }
        } else {
            clearOwnership()
        }
        lidGeneration += 1
    }

    /// Termination path: a completion handler can't outlive the process, so
    /// this one call is synchronous (short watchdog timeout inside). Also
    /// covers an ENGAGE still in flight — the sudo child is a separate
    /// process that survives us and may flip the flag on after we're gone,
    /// so "in flight" must be treated as "possibly engaged".
    func shutdownCleanup() {
        guard lidSleepDisabled || lidCallInFlight else { return }
        ClosedLidSleep.forceOffSynchronously()
        clearOwnership()
        lidSleepDisabled = false
    }

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: {
            // Fires at willSet — hop to the next runloop tick so the
            // recompute reads settled values, then re-register.
            Task { @MainActor in self.observe() }
        }
    }

    /// Idempotent reconcile along the three-notch dial:
    /// - off: never hold
    /// - auto: hold while agents/SSH are active
    /// - always: hold unconditionally
    /// The assertion covers idle sleep; the privileged lid layer engages on
    /// top whenever the helper is authorized. Short-circuits are deliberate —
    /// off/always don't track agent/SSH churn, only the dial itself.
    func refresh() {
        let mode = awakeMode()
        let active = mode == .always || (mode == .auto && hasActiveWork())
        let lidWanted = active && helperReady()
        if active != (assertionID != nil) {
            if active {
                assertionID = createAssertion()
            } else if let id = assertionID {
                releaseAssertion(id)
                assertionID = nil
            }
        }
        syncLidSleep(lidWanted)
    }

    /// One privileged call in flight at a time; re-reconcile when it lands
    /// (the busy state may have moved meanwhile).
    private func syncLidSleep(_ want: Bool) {
        if !want { lidEngageBlocked = false }
        guard !lidCallInFlight,
              want != lidSleepDisabled,
              !(want && lidEngageBlocked),
              !(!want && lidReleaseBlocked)
        else { return }
        lidCallInFlight = true
        lidGeneration += 1
        // Pessimistic ownership: marked before the engage is confirmed, so
        // a crash mid-flight still reads as ours at next launch.
        if want { markOwnership() }
        setLidSleep(want) { [weak self] ok in
            guard let self else { return }
            self.lidCallInFlight = false
            if ok {
                self.lidSleepDisabled = want
                if !want { clearOwnership() }
            } else if want {
                // Couldn't engage: block retries for this busy window and
                // surface it (the default handler steps `always` down).
                self.clearOwnership()
                self.lidEngageBlocked = true
                self.onLidHelperFailure()
            } else {
                // Couldn't release: the system very likely still has
                // SleepDisabled 1 — keep claiming it (shutdown cleanup
                // stays armed) and block instant retries; the next poll
                // that confirms reality lifts the block.
                NSLog("SleepGuard: failed to re-enable lid sleep")
                self.lidReleaseBlocked = true
            }
            self.refresh()
        }
    }
}

// MARK: - Top-strip button

/// Chrome-strip toggle + indicator for keep-awake. Stays in the top strip's
/// quiet visual language: the moon glyph never changes color or variant —
/// dimmed means the feature is off, and "actively holding the assertion"
/// is a small green corner dot (the same badge pattern as `InboxBell`'s
/// unread dot, green matching the sidebar's agent-running dot). Click
/// toggles the setting — saved imperatively because the Settings window's
/// autosave chain is only mounted while that window is open.
struct KeepAwakeButton: View {
    var sleepGuard = SleepGuard.shared
    var model = ArcherSettingsModel.shared

    var body: some View {
        // Archer's HoverableIconButton is SF-symbol based; the keep-awake
        // light is a custom painted dot, so use a plain hover button shell.
        Button(action: cycleDial) {
            indicatorDot
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel("Keep Mac awake while agents or SSH sessions are active")
    }

    /// Click cycles the dial: off → auto → always → off. Funnels through
    /// applyAwakeMode so first entry into `always` runs the one-time admin
    /// auth (cancelled → falls back to auto).
    private func cycleDial() {
        let next: AwakeMode = switch model.awakeMode {
        case .off: .auto
        case .auto: .always
        case .always: .off
        }
        model.applyAwakeMode(next)
    }

    /// The light mirrors the dial one-to-one: gray = off, breathing dot =
    /// auto, breathing dot + ring = always. Whether protection is engaged
    /// right now is the tooltip's job, not the light's. The on/off states
    /// are separate view identities on purpose — the breathing
    /// `phaseAnimator` is torn down with its branch, so no repeatForever
    /// animation can leak into the off state.
    @ViewBuilder
    private var indicatorDot: some View {
        if model.awakeMode != .off {
            // Green throughout (deliberately NOT `activityRunning`, that
            // token is blue — the sidebar's agent dot). The ring stays
            // mounted and animates via opacity so the phaseAnimator's view
            // identity never changes; both circles breathe in one phase.
            let green = Theme.keepAwakeGreen
            ZStack {
                Circle()
                    .stroke(green.opacity(0.55), lineWidth: 1)
                    .frame(width: 13, height: 13)
                    .opacity(model.awakeMode == .always ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: model.awakeMode)
                Circle()
                    .fill(green)
                    .frame(width: 7, height: 7)
                    .shadow(color: green.opacity(0.85), radius: 3.5)
            }
            .phaseAnimator([0.5, 1.0]) { dot, phase in
                dot.opacity(phase)
            } animation: { _ in .easeInOut(duration: 1.5) }
        } else {
            Circle()
                .fill(Theme.chromeMuted.opacity(0.45))
                .frame(width: 7, height: 7)
        }
    }

    private var helpText: String {
        switch model.awakeMode {
        case .always:
            return "Always awake — Mac never sleeps (click to turn off)"
        case .auto:
            if sleepGuard.lidSleepDisabled { return "Keeping Mac awake — even with the lid closed (click for always)" }
            if sleepGuard.isKeepingAwake { return "Keeping Mac awake — agent or SSH session active (click for always)" }
            return "Keep awake: auto — holds while agents or SSH work (click for always)"
        case .off:
            return "Keep awake: off (click for auto)"
        }
    }
}

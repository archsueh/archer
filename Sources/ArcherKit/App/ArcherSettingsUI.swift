import AppKit
import SwiftUI

/// `@Observable` mirror of the typed slice of `~/.archer/settings.json` we
/// expose in the Settings UI. Loads on init, debounces writes back to disk
/// so rapid `Stepper` taps don't thrash the file. Only knows about keys that
/// have working bindings in libghostty today — archer-specific keys
/// (`agent.*`, `sidebar.*`, …) live in settings.json but aren't surfaced in
/// the UI yet, because their behavior isn't wired and shipping a hollow
/// toggle is worse than no toggle.
@Observable
@MainActor
final class ArcherSettingsModel {
    /// Singleton so non-Settings UI surfaces (TabBarView's `+` menu, etc.)
    /// observe the same instance and react to user edits without a reload.
    static let shared = ArcherSettingsModel()

    var fontFamily: String = ""
    /// `nil` = not overridden — let libghostty fall back to ghostty's own
    /// config (or its default). Writing a default 13 unconditionally would
    /// silently shadow the user's `~/.config/ghostty/config` font-size.
    var fontSize: Int?
    var cursorStyle: String = "block"
    /// `terminal.background-blur` — one of ghostty's `macos-glass-*` values
    /// turns on macOS 26 Liquid Glass chrome. No UI control yet (set it in
    /// settings.json or ghostty config); kept observable so chrome re-renders
    /// live when it changes. `nil` = opaque chrome.
    var backgroundBlur: String?
    /// `terminal.background-opacity` (0...1). Drives both libghostty's surface
    /// alpha and archer's glass tint. `nil` = unset (libghostty default).
    var backgroundOpacity: Double?
    /// Picker selection for the terminal theme row. Values are one of:
    /// `defaultThemeSelection`, `customThemeSelection`, or a theme choice id.
    var terminalThemeSelection: String = ArcherSettingsModel.defaultThemeSelection
    var terminalThemeChoices: [ArcherTerminalTheme] = ArcherTerminalTheme.availableThemes()
    /// Unknown raw `terminal.theme` values from hand-edited settings.json.
    /// Kept so saving an unrelated Settings field doesn't delete a custom
    /// Ghostty theme path/name that the picker cannot represent as a preset.
    private var customTerminalThemeRawValue: String?

    /// User-customised order for the `+` menu agent list (Terminal stays
    /// pinned first regardless). Empty = use `AgentTemplate.all` order.
    /// Unknown ids are dropped on load; ids absent from this array but
    /// present in `AgentTemplate.all` are appended after, so a new agent
    /// shipped in a future archer still shows up.
    var agentOrder: [String] = []
    var hiddenAgents: Set<String> = []
    /// Per-agent CLI options appended after the binary name when launching.
    /// E.g. `agentOptions["claude-code"] = "--model opus"` → ARCHER_AGENT
    /// becomes `claude --model opus`. The wrapper rc's `eval` splits on
    /// whitespace, so users handle their own quoting for spaces.
    var agentOptions: [String: String] = [:]
    /// `id` of the template that `+` / `⌘T` should open without prompting.
    /// `nil` (or pointing to a now-hidden / unknown agent) means "ask each
    /// time" — the popover stays. Terminal is always a valid choice.
    var defaultAgentId: String?
    /// User-defined agent entries (`agents.custom` in settings.json). Each
    /// becomes a runtime `AgentTemplate` via `AgentTemplate.fromCustom`,
    /// joins the `+` menu / Settings list alongside the builtin agents,
    /// and supports the same visibility / order / options machinery.
    var customAgents: [CustomAgentData] = []
    /// User-defined "Terminal at <path>" presets (`terminals.presets` in
    /// settings.json). Independent of `agentOrder` / `hiddenAgents` /
    /// `agentOptions` — presets have their own list under Settings →
    /// Terminals, not a sub-section of the Agents one.
    var terminalPresets: [TerminalPreset] = []
    /// Sibling of `hiddenAgents` for the preset list. Hidden presets stay
    /// in `terminalPresets` so the user can re-enable without re-configuring.
    var hiddenPresets: Set<String> = []
    /// Pane status bar slots in user-chosen order. Default = the order
    /// archer shipped before customisation (`StatusBarItemKind.defaultOrder`).
    /// Hand-edited settings.json with an unknown raw value or a duplicate
    /// drops the offending entry; missing entries are appended in default
    /// order on load so a new kind shipped in a future archer still shows.
    var statusBarItems: [StatusBarItemKind] = StatusBarItemKind.defaultOrder
    /// Sibling of `hiddenAgents` for status bar slots. Hidden slots stay
    /// in `statusBarItems` so the user can re-enable without losing their
    /// custom order.
    var hiddenStatusBarItems: Set<StatusBarItemKind> = []
    /// Per-agent visibility of the tool-call activity pill, keyed by builtin
    /// agent id (`claude-code`, `pi`). Empty = every tool-reporting agent
    /// shows its pill (the default). An id in the set suppresses that agent's
    /// pill only — Claude and Pi toggle independently. Customs follow their
    /// base id, so a Claude-based custom honours the `claude-code` entry.
    /// Persisted under `statusbar.toolCallHidden`.
    var hiddenToolCallAgents: Set<String> = []
    /// Per-agent visibility of the usage gauge (Codex's account rate-limit
    /// windows), keyed like `hiddenToolCallAgents`. Empty = every usage-
    /// reporting agent shows its gauge (the default; currently only Codex).
    /// Persisted under `statusbar.usageHidden`. An open `Set` (not a closed
    /// enum) so a future usage-reporting agent's id round-trips untouched.
    var hiddenUsageAgents: Set<String> = []
    /// When true, archer launches Claude tabs with `--resume <id>` using the
    /// conversation id persisted on each tab (captured via Claude's hook
    /// payload). When false, every Claude tab starts fresh — but the
    /// persisted conversation id stays on disk so turning the toggle back
    /// on resumes from where the user left off.
    var resumeConversations: Bool = true
    /// Opt-in SSH integration for remote agent status. Disabled by default:
    /// when enabled, archer installs an `ssh` wrapper that injects temporary
    /// marker-emitting agent wrappers into plain interactive `ssh host`
    /// sessions. The marker receiver itself is always available.
    var sshRemoteAgentDetection: Bool = false
    /// Shows the `⌘P` search pill in the top chrome strip. When false the
    /// pill is hidden (the palette stays reachable via `⌘P` / the File menu).
    /// Persisted under `general.showSearchPill` (only when non-default).
    var showSearchPill: Bool = true
    /// Master switch for macOS notifications about a non-visible tab. When
    /// off, nothing is posted. The first post triggers the OS permission
    /// prompt. Persisted under `notifications.enabled` (only when non-default).
    /// prompt. Persisted under `notifications.enabled` (only when non-default).
    var notificationsEnabled: Bool = true
    /// Per-kind sub-toggles, gated behind `notificationsEnabled`: notify when
    /// an agent starts waiting on you, and when a command exits non-zero.
    /// Persisted under `notifications.attention` / `.failure` (non-default only).
    var notifyOnAttention: Bool = true
    var notifyOnFailure: Bool = true
    var notifyOnCompleted: Bool = true
    var notificationSound: String = "Submarine"
    var edgeGlowEnabled: Bool = true
    var edgeGlowScope: EdgeGlowScope = .allScreens
    var edgeGlowBrightness: Double = 0.35
    var edgeGlowWidth: Double = 3
    /// "Open in" picker (top-chrome split button): user-customised order of
    /// `OpenInApp` ids; installed apps absent from this list follow in catalog
    /// order. Persisted under `openin.order`.
    var openInAppOrder: [String] = []
    /// Installed "Open in" apps the user suppressed from the picker. Sibling of
    /// `hiddenAgents`. Persisted under `openin.hidden`.
    var hiddenOpenInApps: Set<String> = []
    /// Last app picked from the "Open in" control — drives the split button's
    /// icon + plain-click target. Persisted under `openin.lastUsed`.
    var lastOpenInAppId: String?

    private var saveWork: DispatchWorkItem?

    init() {
        load()
    }

    func load() {
        let parsed = ArcherSettings.loadParsed() ?? [:]
        terminalThemeChoices = ArcherTerminalTheme.availableThemes()
        let terminal = parsed["terminal"] as? [String: Any] ?? [:]
        fontFamily = (terminal["font-family"] as? String) ?? ""
        fontSize = nil
        if let n = terminal["font-size"] as? Int {
            fontSize = n
        } else if let d = terminal["font-size"] as? Double {
            fontSize = Int(d)
        }
        cursorStyle = (terminal["cursor-style"] as? String) ?? "block"
        // Tolerate a JSON bool / numeric `background-blur` so a hand-edited
        // `false` isn't read as "unset" and then deleted on the next save.
        backgroundBlur = ArcherSettings.blurString(from: terminal["background-blur"])
        if let o = terminal["background-opacity"] as? Double {
            backgroundOpacity = o
        } else if let i = terminal["background-opacity"] as? Int {
            backgroundOpacity = Double(i)
        } else {
            backgroundOpacity = nil
        }
        let themeState = Self.themeSelection(
            for: terminal["theme"] as? String,
            in: terminalThemeChoices
        )
        terminalThemeSelection = themeState.selection
        customTerminalThemeRawValue = themeState.customRawValue

        let agents = parsed["agents"] as? [String: Any] ?? [:]
        agentOrder = (agents["order"] as? [String]) ?? []
        hiddenAgents = Set((agents["hidden"] as? [String]) ?? [])
        agentOptions = (agents["options"] as? [String: String]) ?? [:]
        defaultAgentId = agents["default"] as? String
        resumeConversations = (agents["resumeConversations"] as? Bool) ?? true

        let ssh = parsed["ssh"] as? [String: Any] ?? [:]
        sshRemoteAgentDetection = (ssh["remoteAgentDetection"] as? Bool) ?? false

        let general = parsed["general"] as? [String: Any] ?? [:]
        showSearchPill = (general["showSearchPill"] as? Bool) ?? true

        let notifications = parsed["notifications"] as? [String: Any] ?? [:]
        notificationsEnabled = (notifications["enabled"] as? Bool) ?? true
        notifyOnAttention = (notifications["attention"] as? Bool) ?? true
        notifyOnFailure = (notifications["failure"] as? Bool) ?? true
        notifyOnCompleted = (notifications["completed"] as? Bool) ?? true
        notificationSound = (notifications["sound"] as? String) ?? "Submarine"

        let edgeGlow = parsed["edgeGlow"] as? [String: Any] ?? [:]
        edgeGlowEnabled = (edgeGlow["enabled"] as? Bool) ?? true
        edgeGlowScope = EdgeGlowScope(rawValue: (edgeGlow["scope"] as? String) ?? "") ?? .allScreens
        edgeGlowBrightness = (edgeGlow["brightness"] as? Double) ?? 0.35
        edgeGlowWidth = (edgeGlow["width"] as? Double) ?? 3

        let openin = parsed["openin"] as? [String: Any] ?? [:]
        openInAppOrder = (openin["order"] as? [String]) ?? []
        hiddenOpenInApps = Set((openin["hidden"] as? [String]) ?? [])
        lastOpenInAppId = openin["lastUsed"] as? String

        let rawCustom = (agents["custom"] as? [[String: Any]]) ?? []
        let builtinIds = Set(AgentTemplate.builtin.map(\.id))
        var seen: Set<String> = []
        customAgents = rawCustom.compactMap { dict -> CustomAgentData? in
            guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
            // Drop hand-edited collisions with builtin agents, and the
            // second occurrence of a duplicated id, so the live `all` list
            // is guaranteed-unique downstream.
            if builtinIds.contains(id) { return nil }
            if !seen.insert(id).inserted { return nil }
            return CustomAgentData(
                id: id,
                title: (dict["title"] as? String) ?? "",
                command: (dict["command"] as? String) ?? "",
                baseAgentId: (dict["baseAgentId"] as? String) ?? "",
                iconAsset: (dict["iconAsset"] as? String) ?? "",
                symbol: (dict["symbol"] as? String) ?? "",
                tintHex: (dict["tintHex"] as? String) ?? "",
                env: (dict["env"] as? String) ?? ""
            )
        }

        let statusbar = parsed["statusbar"] as? [String: Any] ?? [:]
        if let rawOrder = statusbar["order"] as? [String] {
            var seen: Set<StatusBarItemKind> = []
            let parsedOrder = rawOrder.compactMap { raw -> StatusBarItemKind? in
                guard let item = StatusBarItemKind(rawValue: raw), !seen.contains(item) else { return nil }
                seen.insert(item)
                return item
            }
            // Insert any items shipped in a archer version newer than the
            // user's saved file at the position they hold in `defaultOrder`,
            // not blindly appended. Appending would break the equality
            // check at `statusOrderIsDefault` for upgrading users whose
            // saved order was the old default — they'd start writing an
            // explicit (now non-default) `statusbar.order` block to
            // settings.json on first save and `hasCustomisation` would
            // report true forever even though they never customised.
            let missing = StatusBarItemKind.allCases.filter { !seen.contains($0) }
            var rebuilt = parsedOrder
            for newKind in missing {
                // The default position is the slot it occupies in defaultOrder.
                // Anchor relative to the nearest already-present neighbour so
                // user-customised orders preserve the intent (e.g., if the
                // user moved gitDiff first, .toolCallActivity still inserts
                // before pythonVenv — its defaultOrder right neighbour).
                let defaultIndex = StatusBarItemKind.defaultOrder.firstIndex(of: newKind) ?? rebuilt.count
                let rightNeighbours = StatusBarItemKind.defaultOrder.suffix(from: defaultIndex + 1)
                let insertBefore = rebuilt.firstIndex(where: { rightNeighbours.contains($0) }) ?? rebuilt.count
                rebuilt.insert(newKind, at: insertBefore)
            }
            statusBarItems = rebuilt
        } else {
            statusBarItems = StatusBarItemKind.defaultOrder
        }
        let rawHiddenStatus = (statusbar["hidden"] as? [String]) ?? []
        hiddenStatusBarItems = Set(rawHiddenStatus.compactMap(StatusBarItemKind.init(rawValue:)))
        hiddenToolCallAgents = Set((statusbar["toolCallHidden"] as? [String]) ?? [])
        hiddenUsageAgents = Set((statusbar["usageHidden"] as? [String]) ?? [])

        let terminals = parsed["terminals"] as? [String: Any] ?? [:]
        hiddenPresets = Set((terminals["hidden"] as? [String]) ?? [])
        let rawPresets = (terminals["presets"] as? [[String: Any]]) ?? []
        // Same id-uniqueness defence as customAgents — a hand-edited
        // settings.json with a duplicate or a builtin-colliding preset id
        // would otherwise produce two AgentTemplate rows with the same id
        // (visibleOrdered would still surface both, but ForEach renders
        // glitchy and id-based lookups become non-deterministic).
        var presetSeen: Set<String> = []
        let customIds = Set(customAgents.map(\.id))
        terminalPresets = rawPresets.compactMap { dict -> TerminalPreset? in
            guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
            if builtinIds.contains(id) || customIds.contains(id) { return nil }
            if !presetSeen.insert(id).inserted { return nil }
            return TerminalPreset(
                id: id,
                title: (dict["title"] as? String) ?? "",
                path: (dict["path"] as? String) ?? ""
            )
        }
    }

    /// Schedules a debounced write. UI bindings call this on every change;
    /// the 300ms timer collapses a burst of edits (Stepper, typing, etc.)
    /// into one write.
    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Cancels the pending debounce and writes synchronously. Called from
    /// the Restart flow so the new instance is guaranteed to see the user's
    /// latest edits.
    func flushSave() {
        saveWork?.cancel()
        saveWork = nil
        save()
    }

    private func save() {
        var parsed = ArcherSettings.loadParsed() ?? [:]
        var terminal = parsed["terminal"] as? [String: Any] ?? [:]
        let previousTerminal = terminal
        // Sentinel values (empty string / nil / "block") drop the key so
        // libghostty falls back to ghostty's own config or its own default.
        terminal["font-family"] = fontFamily.isEmpty ? nil : fontFamily
        terminal["font-size"] = fontSize
        terminal["cursor-style"] = cursorStyle == "block" ? nil : cursorStyle
        terminal["background-blur"] = backgroundBlur
        terminal["background-opacity"] = backgroundOpacity
        terminal["theme"] = Self.persistedThemeValue(
            selection: terminalThemeSelection,
            customRawValue: customTerminalThemeRawValue,
            in: terminalThemeChoices
        )
        parsed["terminal"] = terminal

        let nonEmptyOptions = agentOptions.filter { !$0.value.isEmpty }
        let serialisedCustom: [[String: Any]] = customAgents.compactMap { c in
            guard !c.id.isEmpty else { return nil }
            var dict: [String: Any] = ["id": c.id]
            if !c.title.isEmpty { dict["title"] = c.title }
            if !c.command.isEmpty { dict["command"] = c.command }
            if !c.baseAgentId.isEmpty { dict["baseAgentId"] = c.baseAgentId }
            if !c.iconAsset.isEmpty { dict["iconAsset"] = c.iconAsset }
            if !c.symbol.isEmpty { dict["symbol"] = c.symbol }
            if !c.tintHex.isEmpty { dict["tintHex"] = c.tintHex }
            if !c.env.isEmpty { dict["env"] = c.env }
            return dict
        }
        let allDefaults = agentOrder.isEmpty
            && hiddenAgents.isEmpty
            && nonEmptyOptions.isEmpty
            && defaultAgentId == nil
            && serialisedCustom.isEmpty
            && resumeConversations // default-true is the no-op case
        if allDefaults {
            parsed.removeValue(forKey: "agents")
        } else {
            var agents = parsed["agents"] as? [String: Any] ?? [:]
            agents["order"] = agentOrder.isEmpty ? nil : agentOrder
            agents["hidden"] = hiddenAgents.isEmpty ? nil : Array(hiddenAgents).sorted()
            agents["options"] = nonEmptyOptions.isEmpty ? nil : nonEmptyOptions
            agents["default"] = defaultAgentId
            agents["custom"] = serialisedCustom.isEmpty ? nil : serialisedCustom
            // Only serialise when non-default to keep settings.json lean.
            agents["resumeConversations"] = resumeConversations ? nil : false
            parsed["agents"] = agents
        }

        var ssh = parsed["ssh"] as? [String: Any] ?? [:]
        ssh["remoteAgentDetection"] = sshRemoteAgentDetection ? true : nil
        if ssh.isEmpty {
            parsed.removeValue(forKey: "ssh")
        } else {
            parsed["ssh"] = ssh
        }

        var general = parsed["general"] as? [String: Any] ?? [:]
        general["showSearchPill"] = showSearchPill ? nil : false
        if general.isEmpty {
            parsed.removeValue(forKey: "general")
        } else {
            parsed["general"] = general
        }

        var notifications = parsed["notifications"] as? [String: Any] ?? [:]
        notifications["enabled"] = notificationsEnabled ? nil : false
        notifications["attention"] = notifyOnAttention ? nil : false
        notifications["failure"] = notifyOnFailure ? nil : false
        notifications["completed"] = notifyOnCompleted ? nil : false
        notifications["sound"] = notificationSound == "Submarine" ? nil : notificationSound
        if notifications.isEmpty {
            parsed.removeValue(forKey: "notifications")
        } else {
            parsed["notifications"] = notifications
        }

        var edgeGlow = parsed["edgeGlow"] as? [String: Any] ?? [:]
        edgeGlow["enabled"] = edgeGlowEnabled ? nil : false
        edgeGlow["scope"] = edgeGlowScope == .allScreens ? nil : edgeGlowScope.rawValue
        edgeGlow["brightness"] = edgeGlowBrightness == 0.35 ? nil : edgeGlowBrightness
        edgeGlow["width"] = edgeGlowWidth == 3 ? nil : edgeGlowWidth
        if edgeGlow.isEmpty {
            parsed.removeValue(forKey: "edgeGlow")
        } else {
            parsed["edgeGlow"] = edgeGlow
        }

        var openin = parsed["openin"] as? [String: Any] ?? [:]
        openin["order"] = openInAppOrder.isEmpty ? nil : openInAppOrder
        openin["hidden"] = hiddenOpenInApps.isEmpty ? nil : Array(hiddenOpenInApps).sorted()
        openin["lastUsed"] = lastOpenInAppId
        if openin.isEmpty {
            parsed.removeValue(forKey: "openin")
        } else {
            parsed["openin"] = openin
        }

        let serialisedPresets: [[String: Any]] = terminalPresets.compactMap { p in
            guard !p.id.isEmpty else { return nil }
            var dict: [String: Any] = ["id": p.id]
            if !p.title.isEmpty { dict["title"] = p.title }
            if !p.path.isEmpty { dict["path"] = p.path }
            return dict
        }
        if serialisedPresets.isEmpty && hiddenPresets.isEmpty {
            parsed.removeValue(forKey: "terminals")
        } else {
            var terminals = parsed["terminals"] as? [String: Any] ?? [:]
            terminals["presets"] = serialisedPresets.isEmpty ? nil : serialisedPresets
            terminals["hidden"] = hiddenPresets.isEmpty ? nil : Array(hiddenPresets).sorted()
            parsed["terminals"] = terminals
        }

        let statusOrderIsDefault = statusBarItems == StatusBarItemKind.defaultOrder
        if statusOrderIsDefault && hiddenStatusBarItems.isEmpty && hiddenToolCallAgents.isEmpty && hiddenUsageAgents.isEmpty {
            parsed.removeValue(forKey: "statusbar")
        } else {
            var statusbar = parsed["statusbar"] as? [String: Any] ?? [:]
            statusbar["order"] = statusOrderIsDefault ? nil : statusBarItems.map(\.rawValue)
            statusbar["hidden"] = hiddenStatusBarItems.isEmpty ? nil : hiddenStatusBarItems.map(\.rawValue).sorted()
            statusbar["toolCallHidden"] = hiddenToolCallAgents.isEmpty ? nil : Array(hiddenToolCallAgents).sorted()
            statusbar["usageHidden"] = hiddenUsageAgents.isEmpty ? nil : Array(hiddenUsageAgents).sorted()
            parsed["statusbar"] = statusbar
        }

        ArcherSettings.write(parsed)
        ArcherShellIntegration.refreshClaudeCustomSettings(customAgents: customAgents)
        ArcherShellIntegration.refreshSshRemoteAgentDetection(enabled: sshRemoteAgentDetection)
        // Theme or glass (blur / opacity) diff triggers the chrome /
        // window-appearance refresh — font and cursor changes also flow
        // through `reloadConfig` so libghostty picks up the new values, but
        // they don't change chrome tokens, so skip the window pass for them.
        let themeChanged = (previousTerminal["theme"] as? String) != (terminal["theme"] as? String)
        let glassChanged = (previousTerminal["background-blur"] as? String) != (terminal["background-blur"] as? String)
            || (previousTerminal["background-opacity"] as? NSNumber) != (terminal["background-opacity"] as? NSNumber)
        let terminalChanged = !NSDictionary(dictionary: previousTerminal).isEqual(to: terminal)
        if terminalChanged {
            LibghosttyApp.shared.reloadConfig()
            if themeChanged || glassChanged {
                (NSApp.delegate as? AppDelegate)?.refreshThemeAppearances()
            }
        }
    }

    func resetAgentCustomisation() {
        agentOrder = []
        hiddenAgents = []
        agentOptions = [:]
        defaultAgentId = nil
        customAgents = []
        scheduleSave()
    }

    static let defaultThemeSelection = "__archer-default-theme"
    static let customThemeSelection = "__archer-custom-theme"

    var selectedTerminalTheme: ArcherTerminalTheme? {
        terminalThemeChoices.first { $0.id == terminalThemeSelection }
    }

    var customTerminalThemeLabel: String? {
        guard terminalThemeSelection == Self.customThemeSelection else { return nil }
        guard let raw = customTerminalThemeRawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return "Custom (\(raw))"
    }

    var bundledTerminalThemes: [ArcherTerminalTheme] {
        terminalThemeChoices.filter(\.isBundled)
    }

    var darkBundledThemes: [ArcherTerminalTheme] {
        bundledTerminalThemes.filter(\.isDark)
    }

    var lightBundledThemes: [ArcherTerminalTheme] {
        bundledTerminalThemes.filter { !$0.isDark }
    }

    var ghosttyUserThemes: [ArcherTerminalTheme] {
        terminalThemeChoices.filter { !$0.isBundled }
    }

    static func themeSelection(
        for rawTheme: String?,
        in themes: [ArcherTerminalTheme] = ArcherTerminalTheme.presets
    ) -> (selection: String, customRawValue: String?) {
        guard let rawTheme,
              !rawTheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return (defaultThemeSelection, nil)
        }
        if let theme = ArcherTerminalTheme.theme(for: rawTheme, in: themes) {
            return (theme.id, nil)
        }
        return (customThemeSelection, rawTheme)
    }

    static func persistedThemeValue(
        selection: String,
        customRawValue: String?,
        in themes: [ArcherTerminalTheme] = ArcherTerminalTheme.presets
    ) -> String? {
        if selection == defaultThemeSelection {
            return nil
        }
        if selection == customThemeSelection {
            let raw = customRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : raw
        }
        return themes.first { $0.id == selection }?.storedValue
    }

    /// Appends a new blank custom agent. The id is `custom-N`, the title is
    /// empty (user fills it inline) — `AgentTemplate.fromCustom` falls back
    /// to showing the id as title until the user edits it.
    func addCustomAgent() {
        let usedIds = Set(AgentTemplate.builtin.map(\.id) + customAgents.map(\.id))
        var n = customAgents.count + 1
        var candidate = "custom-\(n)"
        while usedIds.contains(candidate) {
            n += 1; candidate = "custom-\(n)"
        }
        customAgents.append(CustomAgentData(id: candidate))
        scheduleSave()
    }

    func deleteCustomAgent(id: String) {
        customAgents.removeAll { $0.id == id }
        agentOrder.removeAll { $0 == id }
        hiddenAgents.remove(id)
        agentOptions.removeValue(forKey: id)
        if defaultAgentId == id { defaultAgentId = nil }
        scheduleSave()
    }

    /// `preset-N` slug deliberately doesn't reuse the `custom-N` namespace
    /// so a hand-edited settings.json with a preset id stays distinct
    /// from a custom-agent id on the same numeric tail.
    func addTerminalPreset() {
        let usedIds = Set(
            AgentTemplate.builtin.map(\.id)
                + customAgents.map(\.id)
                + terminalPresets.map(\.id)
        )
        var n = terminalPresets.count + 1
        while usedIds.contains("preset-\(n)") {
            n += 1
        }
        terminalPresets.append(TerminalPreset(id: "preset-\(n)"))
        scheduleSave()
    }

    func resetStatusBar() {
        statusBarItems = StatusBarItemKind.defaultOrder
        hiddenStatusBarItems = []
        hiddenToolCallAgents = []
        hiddenUsageAgents = []
        scheduleSave()
    }

    /// Clears "Open in" order + hidden customisation. Leaves `lastOpenInAppId`
    /// so the split button keeps pointing at the app the user last used.
    func resetOpenIn() {
        openInAppOrder = []
        hiddenOpenInApps = []
        scheduleSave()
    }

    func deleteTerminalPreset(id: String) {
        terminalPresets.removeAll { $0.id == id }
        hiddenPresets.remove(id)
        // Stale-default cleanup: if the user had this preset set as the
        // default for `+` / `⌘T`, the saved id would otherwise point at a
        // now-gone row → `defaultLaunchTemplate` returns nil → +/⌘T
        // silently fall back to the popover. Matches `deleteCustomAgent`.
        if defaultAgentId == id { defaultAgentId = nil }
        scheduleSave()
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, codingAgents, terminalPresets, openIn, statusBar, notifications, advanced

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .codingAgents: return "Agents"
        case .terminalPresets: return "Terminals"
        case .openIn: return "Open in"
        case .statusBar: return "Status Bar"
        case .notifications: return "Notifications"
        case .advanced: return "Advanced"
        }
    }
}

/// Settings panel. Brutalist-minimal:
///   - sidebar list reads like a config-key index: mono font, `▸` prefix on
///     the selected row, no pill highlights, no icons
///   - detail surface is unboxed — rows are hairline-separated, labels are
///     kebab-case config keys in mono, headers use Onest display for the
///     single human-readable hook
///   - all separators are 1pt hairlines, all corners are sharp
/// The goal is to feel like polishing a `.toml` in a clean GUI, not a SaaS
/// settings panel.
struct ArcherSettingsView: View {
    @Bindable var model: ArcherSettingsModel
    let onOpenInTab: () -> Void
    @State private var selected: SettingsCategory = .general

    var body: some View {
        // The autosave `.onChange` observers are split across two statements
        // via an intermediate `let`: a single chain this long (16 modifiers)
        // overruns the Swift type-checker's budget ("unable to type-check in
        // reasonable time"). Each half stays comfortably under the limit.
        let core = HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.chromeHairline).frame(width: 1)
            ScrollView { detail }
                .frame(maxWidth: .infinity)
        }
        .glassWindowBackground(fallback: Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onChange(of: model.fontFamily) { _, _ in model.scheduleSave() }
        .onChange(of: model.fontSize) { _, _ in model.scheduleSave() }
        .onChange(of: model.cursorStyle) { _, _ in model.scheduleSave() }
        .onChange(of: model.terminalThemeSelection) { _, _ in model.flushSave() }
        .onChange(of: model.backgroundBlur) { _, _ in model.flushSave() }
        .onChange(of: model.agentOrder) { _, _ in model.scheduleSave() }
        .onChange(of: model.hiddenAgents) { _, _ in model.scheduleSave() }
        .onChange(of: model.agentOptions) { _, _ in model.scheduleSave() }
        .onChange(of: model.defaultAgentId) { _, _ in model.scheduleSave() }
        .onChange(of: model.openInAppOrder) { _, _ in model.scheduleSave() }
        .onChange(of: model.hiddenOpenInApps) { _, _ in model.scheduleSave() }

        let core2 = core
            .onChange(of: model.customAgents) { _, _ in model.scheduleSave() }
            .onChange(of: model.resumeConversations) { _, _ in model.scheduleSave() }
            .onChange(of: model.sshRemoteAgentDetection) { _, _ in model.scheduleSave() }
            .onChange(of: model.showSearchPill) { _, _ in model.scheduleSave() }
            .onChange(of: model.terminalPresets) { _, _ in model.scheduleSave() }
            .onChange(of: model.hiddenPresets) { _, _ in model.scheduleSave() }
            .onChange(of: model.statusBarItems) { _, _ in model.scheduleSave() }
            .onChange(of: model.hiddenStatusBarItems) { _, _ in model.scheduleSave() }
            .onChange(of: model.hiddenToolCallAgents) { _, _ in model.scheduleSave() }
            .onChange(of: model.hiddenUsageAgents) { _, _ in model.scheduleSave() }

        return core2
            .onChange(of: model.notificationsEnabled) { _, _ in model.scheduleSave() }
            .onChange(of: model.notifyOnAttention) { _, _ in model.scheduleSave() }
            .onChange(of: model.notifyOnFailure) { _, _ in model.scheduleSave() }
            .onChange(of: model.notifyOnCompleted) { _, _ in model.scheduleSave() }
            .onChange(of: model.notificationSound) { _, _ in model.scheduleSave() }
            .onChange(of: model.edgeGlowEnabled) { _, _ in model.scheduleSave(); EdgeGlowController.shared.refresh() }
            .onChange(of: model.edgeGlowScope) { _, _ in model.scheduleSave(); EdgeGlowController.shared.refresh() }
            .onChange(of: model.edgeGlowBrightness) { _, _ in model.scheduleSave() }
            .onChange(of: model.edgeGlowWidth) { _, _ in model.scheduleSave() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .font(Theme.mono(10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(Theme.chromeMuted.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 18)
            ForEach(SettingsCategory.allCases) { category in
                sidebarRow(category)
            }
            Spacer()
        }
        .frame(width: 168, alignment: .topLeading)
        .background(Theme.chromeFaint.opacity(0.08))
    }

    private func sidebarRow(_ category: SettingsCategory) -> some View {
        let isSelected = selected == category
        return HStack(spacing: 0) {
            Text(isSelected ? "▸" : " ")
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.chromeForeground : Color.clear)
                .frame(width: 14, alignment: .leading)
            Text(category.title)
                .font(Theme.mono(12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.chromeForeground : Theme.chromeMuted)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { selected = category }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text(selected.title)
                    .font(Theme.display(22, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                // The Notifications section's master switch lives on the title
                // row; its per-kind sub-toggles sit in the body below.
                if selected == .notifications {
                    Spacer(minLength: 14)
                    Toggle("", isOn: $model.notificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 22)
            Rectangle()
                .fill(Theme.chromeHairline)
                .frame(width: 32, height: 1)
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            switch selected {
            case .general: generalDetail
            case .appearance: appearanceDetail
            case .codingAgents: codingAgentsDetail
            case .terminalPresets: terminalPresetsDetail
            case .openIn: openInDetail
            case .statusBar: statusBarDetail
            case .notifications: notificationsDetail
            case .advanced: advancedDetail
            }
            Spacer(minLength: 28)
        }
    }

    private var appearanceDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "theme") {
                themeControl
            }
            SettingsHairline()
            SettingsRow(label: "font-family") {
                Picker("", selection: $model.fontFamily) {
                    Text("Default").tag("")
                    Divider()
                    ForEach(Self.monospaceFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180, alignment: .trailing)
            }
            SettingsHairline()
            SettingsRow(label: "font-size") {
                HStack(spacing: 8) {
                    Text("\(model.fontSize ?? Self.defaultFontSize)")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.chromeForeground)
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                    Stepper("", value: fontSizeBinding, in: 8 ... 32)
                        .labelsHidden()
                }
            }
            SettingsHairline()
            SettingsRow(label: "cursor-style") {
                Picker("", selection: $model.cursorStyle) {
                    Text("Block").tag("block")
                    Text("Underline").tag("underline")
                    Text("Bar").tag("bar")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180, alignment: .trailing)
            }
            SettingsHairline()
            SettingsRow(label: "liquid-glass") {
                // Real Liquid Glass on macOS 26+; no effect on older systems.
                // Tags are ghostty's `background-blur` values; "Off" stores
                // `false` so it overrides a glassy ghostty config.
                Picker("", selection: glassSelection) {
                    Text("Off").tag("false")
                    Text("Regular").tag("macos-glass-regular")
                    Text("Clear").tag("macos-glass-clear")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180, alignment: .trailing)
            }
            Text("Requires macOS 26 or later.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 10)
            terminalRestartCallout
        }
    }

    private var generalDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "default-new-tab") {
                Picker("", selection: $model.defaultAgentId) {
                    Text("Ask each time").tag(String?.none)
                    Divider()
                    ForEach(AgentTemplate.visibleOrdered(model: model)) { template in
                        Text(template.title).tag(String?.some(template.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180, alignment: .trailing)
            }
            SettingsHairline()
            SettingsRow(label: "top-bar-search") {
                Toggle("", isOn: $model.showSearchPill)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsHairline()
            // SSH remote agent detection lives here now (it was its own
            // one-toggle category before). The settings.json key stays
            // `ssh.remoteAgentDetection`; only the UI home moved.
            SettingsRow(label: "remote-agent-detection") {
                Toggle("", isOn: $model.sshRemoteAgentDetection)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var terminalPresetsDetail: some View {
        TerminalPresetsList(model: model)
    }

    private var openInDetail: some View {
        OpenInReorderList(model: model)
    }

    private var statusBarDetail: some View {
        StatusBarReorderList(model: model)
    }

    private var codingAgentsDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentReorderList(model: model)
            SettingsHairline()
            SettingsRow(label: "resume-conversation-when-reopen") {
                Toggle("", isOn: $model.resumeConversations)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var notificationsDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "agent") {
                Toggle("", isOn: $model.notifyOnAttention)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.notificationsEnabled)
            }
            SettingsRow(label: "command") {
                Toggle("", isOn: $model.notifyOnFailure)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.notificationsEnabled)
            }
            SettingsRow(label: "completed") {
                Toggle("", isOn: $model.notifyOnCompleted)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.notificationsEnabled)
            }
            SettingsRow(label: "sound") {
                Picker("", selection: $model.notificationSound) {
                    Text("Submarine").tag("Submarine")
                    Text("Basso").tag("Basso")
                    Text("Blow").tag("Blow")
                    Text("Bottle").tag("Bottle")
                    Text("Frog").tag("Frog")
                    Text("Funk").tag("Funk")
                    Text("Glass").tag("Glass")
                    Text("Hero").tag("Hero")
                    Text("Morse").tag("Morse")
                    Text("Ping").tag("Ping")
                    Text("Pop").tag("Pop")
                    Text("Purr").tag("Purr")
                    Text("Sosumi").tag("Sosumi")
                    Text("Tink").tag("Tink")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!model.notificationsEnabled)
                .onChange(of: model.notificationSound) { _, newValue in
                    NSSound(named: NSSound.Name(newValue))?.play()
                }
            }
            SettingsRow(label: "edge glow") {
                Toggle("", isOn: $model.edgeGlowEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(label: "  ▸ screens") {
                Picker("", selection: $model.edgeGlowScope) {
                    Text("all").tag(EdgeGlowScope.allScreens)
                    Text("current").tag(EdgeGlowScope.currentScreen)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120)
                .disabled(!model.edgeGlowEnabled)
            }
            SettingsRow(label: "  ▸ brightness") {
                BrutalistSlider(value: $model.edgeGlowBrightness, range: 0.1 ... 1)
                    .frame(width: 120)
                    .disabled(!model.edgeGlowEnabled)
            }
            SettingsRow(label: "  ▸ width") {
                BrutalistSlider(value: $model.edgeGlowWidth, range: 1 ... 8)
                    .frame(width: 120)
                    .disabled(!model.edgeGlowEnabled)
            }
        }
    }

    private var advancedDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "~/.archer/settings.json") {
                BracketButton("open in new tab", action: onOpenInTab)
            }
            Text("Edit the raw JSON for any key not exposed above. Comments (`//`, `/* */`) are accepted.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .padding(.horizontal, 28)
                .padding(.top, 16)
        }
    }

    private var terminalRestartCallout: some View {
        HStack(spacing: 12) {
            Text("Theme reloads existing panes. Font and cursor changes may need restart.")
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeMuted)
            Spacer()
            BracketButton("restart archer", action: restartApp)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }

    private func restartApp() {
        // Naively `openApplication` + `terminate` races: the new instance
        // boots while the old one still holds `~/Library/Application
        // Support/archer/socket` and the persisted workspace file. The new
        // instance reads stale state and binds to the socket that the old
        // `applicationWillTerminate` is about to delete, leaving ArcherHook
        // unable to reach anyone.
        //
        // Fix: sync-flush settings, detach a bash helper that waits for the
        // current PID to fully exit, then `open` a fresh instance. The
        // helper inherits PID 1 once archer dies, so it keeps running after
        // our terminate.
        model.flushSave()
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundle = ArcherShellIntegration.quote(Bundle.main.bundlePath)
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; sleep 0.3; open -n \(bundle)",
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    private var themeControl: some View {
        Picker("", selection: $model.terminalThemeSelection) {
            Text("Default").tag(ArcherSettingsModel.defaultThemeSelection)
            if let customLabel = model.customTerminalThemeLabel {
                Text(customLabel).tag(ArcherSettingsModel.customThemeSelection)
            }
            Section("Dark") {
                ForEach(model.darkBundledThemes) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            Section("Light") {
                ForEach(model.lightBundledThemes) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            if !model.ghosttyUserThemes.isEmpty {
                Section("Custom") {
                    ForEach(model.ghosttyUserThemes) { theme in
                        Text(theme.title).tag(theme.id)
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 220, alignment: .trailing)
    }

    /// Falls back to 13 when the user hasn't explicitly chosen a size —
    /// matches libghostty's own default so the Stepper display doesn't lie.
    private static let defaultFontSize = 13

    /// Bridges `model.fontSize: Int?` to `Stepper`'s required `Binding<Int>`.
    /// Reading the Stepper always shows a concrete number; writing sets the
    /// optional, which `save()` then writes only when non-nil.
    private var fontSizeBinding: Binding<Int> {
        Binding(
            get: { model.fontSize ?? Self.defaultFontSize },
            set: { model.fontSize = $0 }
        )
    }

    /// The picker shows what's *in effect* (archer's own value, else the ghostty
    /// fallback, else off), but always writes an explicit value — so picking
    /// "Off" stores `false` rather than clearing the key, keeping it distinct
    /// from "never set" (which is what defers to the ghostty config).
    ///
    /// The blur→opacity coupling lives in `ArcherSettings.apply` (the libghostty
    /// config builder), not here — so it holds for every config path and never
    /// clobbers a `background-opacity` the user set by hand.
    private var glassSelection: Binding<String> {
        Binding(
            get: {
                switch Theme.effectiveBlurRaw {
                case "macos-glass-regular": return "macos-glass-regular"
                case "macos-glass-clear": return "macos-glass-clear"
                default: return "false"
                }
            },
            set: { model.backgroundBlur = $0 }
        )
    }

    private static let monospaceFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .compactMap { family -> String? in
            guard let font = NSFont(name: family, size: 12), font.isFixedPitch else { return nil }
            return family
        }
        .sorted()
}

private struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(Theme.mono(12.5))
                .foregroundStyle(Theme.chromeForeground)
            Spacer(minLength: 14)
            trailing()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 11)
    }
}

private struct SettingsHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.chromeHairline.opacity(0.55))
            .frame(height: 1)
            .padding(.horizontal, 28)
    }
}

/// Reorderable list of non-terminal agent templates. The user's saved order
/// (`model.agentOrder`) is the source of truth; templates absent from it
/// (e.g. a fresh archer install, or a new agent in a future version) are
/// appended in their default `AgentTemplate.all` position.
private struct AgentReorderList: View {
    @Bindable var model: ArcherSettingsModel
    @State private var draggingId: String?
    @State private var endTargeted: Bool = false
    @State private var expandedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, template in
                if index > 0 { SettingsHairline() }
                AgentRow(
                    template: template,
                    visible: !model.hiddenAgents.contains(template.id),
                    isDragging: draggingId == template.id,
                    isExpanded: expandedId == template.id,
                    isCustom: isCustomId(template.id),
                    options: Binding(
                        get: { model.agentOptions[template.id] ?? "" },
                        set: { model.agentOptions[template.id] = $0 }
                    ),
                    title: customBinding(id: template.id, \.title),
                    command: customBinding(id: template.id, \.command),
                    baseAgentId: customBinding(id: template.id, \.baseAgentId),
                    env: customBinding(id: template.id, \.env),
                    onToggleVisible: { toggle(template.id) },
                    onToggleExpanded: {
                        expandedId = expandedId == template.id ? nil : template.id
                    },
                    onBeginDrag: { draggingId = template.id },
                    onDrop: { droppedId in
                        defer { draggingId = nil }
                        return reorder(draggedId: droppedId, before: template.id)
                    },
                    onDelete: isCustomId(template.id) ? { model.deleteCustomAgent(id: template.id) } : nil
                )
            }
            // Trailing drop catcher — drag past the last row to send the
            // agent to the end of the list. Without this, the bottom-most
            // position is only reachable by dropping onto the second-to-last
            // row, which reads wrong.
            Color.clear
                .frame(height: 10)
                .contentShape(Rectangle())
                .dropIndicator(active: endTargeted, on: .top, offset: 4)
                .dropDestination(for: String.self) { items, _ in
                    defer { draggingId = nil }
                    guard let id = items.first else { return false }
                    return moveToEnd(id)
                } isTargeted: { endTargeted = $0 }
            HStack {
                Button {
                    let newId = model.customAgents.last?.id
                    model.addCustomAgent()
                    if let id = model.customAgents.last?.id, id != newId {
                        expandedId = id
                    }
                } label: {
                    Text("+ add custom agent")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(Theme.chromeForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .bracketBorder()
                }
                .buttonStyle(.plain)
                Spacer()
                if hasCustomisation {
                    Button("reset to defaults") { model.resetAgentCustomisation() }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeMuted)
                        .underline()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
        }
    }

    private func isCustomId(_ id: String) -> Bool {
        model.customAgents.contains(where: { $0.id == id })
    }

    /// Binding into a specific custom agent's field. Returns a no-op binding
    /// if the row is a built-in agent (`AgentRow` ignores these bindings
    /// when `isCustom == false`).
    private func customBinding(id: String, _ key: WritableKeyPath<CustomAgentData, String>) -> Binding<String> {
        Binding(
            get: { model.customAgents.first(where: { $0.id == id })?[keyPath: key] ?? "" },
            set: { newValue in
                guard let idx = model.customAgents.firstIndex(where: { $0.id == id }) else { return }
                model.customAgents[idx][keyPath: key] = newValue
            }
        )
    }

    /// All non-terminal templates in the user's chosen order — visible and
    /// hidden alike. Hidden agents render greyed out but stay wherever the
    /// user dragged them, so toggling visibility doesn't move them. The
    /// `+` menu's filter to visible-only lives in `AgentTemplate.visibleOrdered`.
    private var rows: [AgentTemplate] {
        AgentTemplate.ordered(model: model)
    }

    private var hasCustomisation: Bool {
        !model.agentOrder.isEmpty
            || !model.hiddenAgents.isEmpty
            || model.agentOptions.values.contains(where: { !$0.isEmpty })
            || model.defaultAgentId != nil
            || !model.customAgents.isEmpty
    }

    private func toggle(_ id: String) {
        if model.hiddenAgents.contains(id) {
            model.hiddenAgents.remove(id)
        } else {
            model.hiddenAgents.insert(id)
        }
    }

    private func reorder(draggedId: String, before targetId: String) -> Bool {
        var ids = rows.map(\.id)
        guard let sourceIdx = ids.firstIndex(of: draggedId),
              let targetIdx = ids.firstIndex(of: targetId),
              sourceIdx != targetIdx else { return false }
        let item = ids.remove(at: sourceIdx)
        // After remove, target index shifts left by 1 if source was earlier.
        let adjustedTarget = sourceIdx < targetIdx ? targetIdx - 1 : targetIdx
        ids.insert(item, at: adjustedTarget)
        withAnimation(.easeInOut(duration: 0.18)) {
            model.agentOrder = ids
        }
        return true
    }

    private func moveToEnd(_ draggedId: String) -> Bool {
        var ids = rows.map(\.id)
        guard let sourceIdx = ids.firstIndex(of: draggedId),
              sourceIdx != ids.count - 1 else { return false }
        let item = ids.remove(at: sourceIdx)
        ids.append(item)
        withAnimation(.easeInOut(duration: 0.18)) {
            model.agentOrder = ids
        }
        return true
    }
}

private struct AgentRow: View {
    let template: AgentTemplate
    let visible: Bool
    let isDragging: Bool
    let isExpanded: Bool
    let isCustom: Bool
    @Binding var options: String
    /// Title binding — only consulted when `isCustom` so the user can rename
    /// their custom agent inline. Bound to a no-op for builtin rows.
    @Binding var title: String
    /// Launch-command binding — same scoping rule as `title`.
    @Binding var command: String
    /// `baseAgentId` binding — same scoping rule as `title`/`command`. Empty
    /// string = no base (generic icon + no wrapper inheritance).
    @Binding var baseAgentId: String
    /// Env-block binding (`.env` syntax) — same scoping rule as `title`;
    /// additionally only shown for Claude-Code-based customs.
    @Binding var env: String
    let onToggleVisible: () -> Void
    let onToggleExpanded: () -> Void
    let onBeginDrag: () -> Void
    let onDrop: (String) -> Bool
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ReorderHandle(payload: template.id, onBeginDrag: onBeginDrag)
                AgentIconView(asset: template.iconAsset, fallbackSymbol: template.symbol, size: 14)
                    .opacity(visible ? 1.0 : 0.35)
                Text(template.title)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(visible ? Theme.chromeForeground : Theme.chromeMuted)
                Spacer(minLength: 14)
                disclosureButton
                Toggle("", isOn: Binding(get: { visible }, set: { _ in onToggleVisible() }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(ReorderDropZone(row: template.id, isDragging: isDragging, decode: { $0 }, onDrop: onDrop))
            if isExpanded { expandedForm }
        }
        .opacity(isDragging ? 0.35 : 1.0)
    }

    private var disclosureButton: some View {
        Button(action: onToggleExpanded) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.chromeMuted.opacity(isExpanded ? 1.0 : 0.7))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Indent the expansion sub-row so it visually hangs under the agent
    /// name. Approximates `row hpad + handle + spacing + icon` from the
    /// HStack above; a magic-but-named constant keeps the layout legible
    /// without reaching for `.alignmentGuide`.
    private static let optionsRowIndent: CGFloat = 56

    private var expandedForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isCustom {
                basedOnRow
                editRow(label: "title", placeholder: "My Agent", text: $title)
                if baseAgentId.isEmpty {
                    editRow(label: "command", placeholder: "aichat --model gpt-4", text: $command)
                }
                if baseAgentId == AgentTemplate.claudeCodeID {
                    editRow(
                        label: "env",
                        placeholder: "ANTHROPIC_BASE_URL=https://...\nANTHROPIC_AUTH_TOKEN=sk-...",
                        text: $env,
                        axis: .vertical
                    )
                }
            }
            editRow(label: "options", placeholder: "--model opus", text: $options)
            if isCustom {
                HStack {
                    Spacer()
                    if let onDelete {
                        Button("delete", action: onDelete)
                            .buttonStyle(.plain)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.activityFailure.opacity(0.85))
                            .underline()
                    }
                }
                .padding(.leading, Self.optionsRowIndent)
                .padding(.trailing, 22)
                .padding(.top, 4)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
        .id(template.id)
    }

    /// "based on" picker — inherits icon / tint / wrapper / launch binary
    /// from the chosen builtin. Empty = generic SF Symbol fallback,
    /// no wrapper-fired lifecycle, `command` field required.
    /// Switching to a non-empty base clears `command` so a stale override
    /// can't silently win over the base's binary.
    private var basedOnRow: some View {
        HStack(spacing: 10) {
            Text("based on")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .frame(width: 50, alignment: .leading)
            Picker("", selection: $baseAgentId) {
                Text("(none)").tag("")
                Divider()
                ForEach(AgentTemplate.builtin.filter { !$0.isShell }) { template in
                    Text(template.title).tag(template.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 160)
            .onChange(of: baseAgentId) { _, new in
                if !new.isEmpty { command = "" }
            }
        }
        .padding(.leading, Self.optionsRowIndent)
        .padding(.trailing, 22)
    }

    private func editRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        axis: Axis = .horizontal
    ) -> some View {
        HStack(alignment: axis == .vertical ? .top : .center, spacing: 10) {
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .frame(width: 50, alignment: .leading)
                // drop the label to the multi-line field's first text line
                .padding(.top, axis == .vertical ? 6 : 0)
            Group {
                if axis == .vertical {
                    TextField(placeholder, text: text, axis: .vertical).lineLimit(3 ... 12)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(Theme.mono(12))
            .foregroundStyle(Theme.chromeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .bracketBorder()
        }
        .padding(.leading, Self.optionsRowIndent)
        .padding(.trailing, 22)
    }
}

/// Singleton NSWindowController so reopening Settings reuses the same window
/// (preserves position, doesn't stack). `show(storeProvider:)` is the only
/// entry point; the provider resolves the *current* active window's store
/// each time "Open in New Tab" runs — a captured store would dangle once
/// its window closed.
@MainActor
final class ArcherSettingsWindowController: NSWindowController {
    static let shared = ArcherSettingsWindowController()
    private let model = ArcherSettingsModel.shared
    private var storeProvider: (() -> WorkspaceStore?)?
    private var host: NSHostingController<ArcherSettingsView>?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    static func show(storeProvider: @escaping () -> WorkspaceStore?) {
        let controller = shared
        controller.storeProvider = storeProvider
        controller.buildWindowIfNeeded()
        controller.model.load()
        if controller.window?.isVisible != true {
            controller.window?.center()
        }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindowIfNeeded() {
        guard window == nil else { return }
        let view = ArcherSettingsView(model: model) { [weak self] in
            self?.openSettingsInNewTab()
        }
        let host = NSHostingController(rootView: view)
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        // Keep the title set (Window menu / accessibility) but hide the text in
        // the bar, matching the main window + About + the floating panels.
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 680, height: 460))
        window.isReleasedWhenClosed = false
        window.appearance = Theme.windowAppearance
        // Glass runs edge to edge under a transparent full-size titlebar;
        // content keeps its safe-area inset, so rows still sit below the bar.
        window.configureGlassChrome()
        self.window = window
    }

    /// Opens `~/.archer/settings.json` in a new archer tab via `$EDITOR`
    /// (defaulting to `vi`). Falls back to the system default editor (via
    /// NSWorkspace) when no active workspace exists.
    private func openSettingsInNewTab() {
        // Ensure the file exists so the editor lands in a real document.
        if !FileManager.default.fileExists(atPath: ArcherSettings.url.path) {
            ArcherSettings.writeDefaultTemplate()
        }
        guard let store = storeProvider?(), let workspace = store.active else {
            NSWorkspace.shared.open(ArcherSettings.url)
            return
        }
        // ARCHER_AGENT is auto-evaluated by the wrapper rcfile; shell expands
        // `${EDITOR:-vi}` at runtime, so the user's chosen editor wins.
        let template = AgentTemplate(
            id: "archer-settings-editor",
            title: "settings.json",
            symbol: "doc.text",
            iconAsset: nil,
            tintHex: nil,
            initialCommand: "${EDITOR:-vi} \(ArcherShellIntegration.quote(ArcherSettings.url.path))"
        )
        let session = store.addTab(in: workspace, template: template)
        session.customTitle = "settings.json"
        window?.orderOut(nil)
    }
}

private struct TerminalPresetsList: View {
    @Bindable var model: ArcherSettingsModel
    @State private var draggingId: String?
    @State private var endTargeted: Bool = false
    @State private var expandedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.terminalPresets.enumerated()), id: \.element.id) { index, preset in
                if index > 0 { SettingsHairline() }
                TerminalPresetRow(
                    id: preset.id,
                    visible: !model.hiddenPresets.contains(preset.id),
                    isDragging: draggingId == preset.id,
                    isExpanded: expandedId == preset.id,
                    title: titleBinding(id: preset.id),
                    path: pathBinding(id: preset.id),
                    onToggleVisible: { toggleVisible(preset.id) },
                    onToggleExpanded: {
                        expandedId = expandedId == preset.id ? nil : preset.id
                    },
                    onChooseFolder: { chooseFolder(forPresetId: preset.id) },
                    onDelete: { model.deleteTerminalPreset(id: preset.id) },
                    onBeginDrag: { draggingId = preset.id },
                    onDrop: { droppedId in
                        defer { draggingId = nil }
                        return reorder(draggedId: droppedId, before: preset.id)
                    }
                )
            }
            // Trailing drop catcher — drop past the last row to send the
            // preset to the bottom of the list. Without this, the bottom
            // slot is only reachable by dropping ON the last row (which
            // means "before it"), which reads wrong.
            Color.clear
                .frame(height: 10)
                .contentShape(Rectangle())
                .dropIndicator(active: endTargeted, on: .top, offset: 4)
                .dropDestination(for: String.self) { items, _ in
                    defer { draggingId = nil }
                    guard let id = items.first else { return false }
                    return moveToEnd(id)
                } isTargeted: { endTargeted = $0 }
            HStack {
                Button {
                    // Auto-expand the freshly-added preset so the user
                    // doesn't have to chase the disclosure chevron.
                    // Matches `AgentReorderList`'s "+ add custom agent".
                    let priorId = model.terminalPresets.last?.id
                    model.addTerminalPreset()
                    if let newId = model.terminalPresets.last?.id, newId != priorId {
                        expandedId = newId
                    }
                } label: {
                    Text("+ add terminal preset")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(Theme.chromeForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .bracketBorder()
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, model.terminalPresets.isEmpty ? 6 : 14)

            if model.terminalPresets.isEmpty {
                Text("Each preset becomes a Terminal entry in the + menu that always spawns in the configured folder, regardless of the active workspace.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.chromeMuted)
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
            }
        }
    }

    /// Resolves bindings by id (not by index) so a deletion that shifts
    /// indices doesn't leave a row writing into the wrong preset.
    private func titleBinding(id: String) -> Binding<String> {
        Binding(
            get: { model.terminalPresets.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                guard let idx = model.terminalPresets.firstIndex(where: { $0.id == id }) else { return }
                model.terminalPresets[idx].title = newValue
            }
        )
    }

    private func pathBinding(id: String) -> Binding<String> {
        Binding(
            get: { model.terminalPresets.first(where: { $0.id == id })?.path ?? "" },
            set: { newValue in
                guard let idx = model.terminalPresets.firstIndex(where: { $0.id == id }) else { return }
                model.terminalPresets[idx].path = newValue
            }
        )
    }

    /// Opens NSOpenPanel as a sheet on the Settings window. Sheet-modal
    /// blocks edits to the underlying view, so resolving the preset by id
    /// in the completion handler is race-free.
    private func chooseFolder(forPresetId id: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for this terminal preset."
        let assign: (URL) -> Void = { url in
            // Resolve by id so a concurrent deletion (or a parallel
            // Settings window mutating the same singleton) doesn't write
            // into the wrong row. Stored with `~` for HOME so the preset
            // survives a `$HOME` move.
            guard let idx = model.terminalPresets.firstIndex(where: { $0.id == id }) else { return }
            model.terminalPresets[idx].path = (url.path as NSString).abbreviatingWithTildeInPath
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { assign(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            assign(url)
        }
    }

    private func toggleVisible(_ id: String) {
        if model.hiddenPresets.contains(id) {
            model.hiddenPresets.remove(id)
        } else {
            model.hiddenPresets.insert(id)
        }
    }

    /// Reorder by moving `draggedId` to just before `targetId`. Same shift-
    /// adjust as `AgentReorderList.reorder` — removing from a position earlier
    /// than the target shifts every later index left by one.
    private func reorder(draggedId: String, before targetId: String) -> Bool {
        let ids = model.terminalPresets.map(\.id)
        guard let sourceIdx = ids.firstIndex(of: draggedId),
              let targetIdx = ids.firstIndex(of: targetId),
              sourceIdx != targetIdx else { return false }
        var presets = model.terminalPresets
        let item = presets.remove(at: sourceIdx)
        let adjustedTarget = sourceIdx < targetIdx ? targetIdx - 1 : targetIdx
        presets.insert(item, at: adjustedTarget)
        withAnimation(.easeInOut(duration: 0.18)) {
            model.terminalPresets = presets
        }
        return true
    }

    private func moveToEnd(_ draggedId: String) -> Bool {
        guard let sourceIdx = model.terminalPresets.firstIndex(where: { $0.id == draggedId }),
              sourceIdx != model.terminalPresets.count - 1 else { return false }
        var presets = model.terminalPresets
        let item = presets.remove(at: sourceIdx)
        presets.append(item)
        withAnimation(.easeInOut(duration: 0.18)) {
            model.terminalPresets = presets
        }
        return true
    }
}

private struct TerminalPresetRow: View {
    let id: String
    let visible: Bool
    let isDragging: Bool
    let isExpanded: Bool
    @Binding var title: String
    @Binding var path: String
    let onToggleVisible: () -> Void
    let onToggleExpanded: () -> Void
    let onChooseFolder: () -> Void
    let onDelete: () -> Void
    let onBeginDrag: () -> Void
    let onDrop: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ReorderHandle(payload: id, onBeginDrag: onBeginDrag)
                AgentIconView(
                    asset: AgentTemplate.terminal.iconAsset,
                    fallbackSymbol: AgentTemplate.terminal.symbol,
                    size: 14
                )
                .opacity(visible ? 1.0 : 0.35)
                Text(displayTitle)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(visible ? Theme.chromeForeground : Theme.chromeMuted)
                Spacer(minLength: 14)
                disclosureButton
                Toggle("", isOn: Binding(get: { visible }, set: { _ in onToggleVisible() }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(ReorderDropZone(row: id, isDragging: isDragging, decode: { $0 }, onDrop: onDrop))
            if isExpanded { expandedForm }
        }
        .opacity(isDragging ? 0.35 : 1.0)
    }

    private var displayTitle: String {
        TerminalPreset(id: id, title: title, path: path).displayTitle
    }

    private var disclosureButton: some View {
        Button(action: onToggleExpanded) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.chromeMuted.opacity(isExpanded ? 1.0 : 0.7))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Indent the expansion sub-rows so they visually hang under the row
    /// title, matching `AgentRow.optionsRowIndent`.
    private static let editRowIndent: CGFloat = 56

    private var expandedForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            editRow(label: "name", placeholder: "Work", text: $title)
            HStack(alignment: .center, spacing: 10) {
                Text("path")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.chromeMuted)
                    .frame(width: 50, alignment: .leading)
                TextField("~/projects/foo", text: $path)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .bracketBorder()
                Button("choose") { onChooseFolder() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.chromeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .bracketBorder()
            }
            .padding(.leading, Self.editRowIndent)
            .padding(.trailing, 22)
            HStack {
                Spacer()
                Button("delete", action: onDelete)
                    .buttonStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.activityFailure.opacity(0.85))
                    .underline()
            }
            .padding(.leading, Self.editRowIndent)
            .padding(.trailing, 22)
            .padding(.top, 4)
        }
        .padding(.bottom, 12)
    }

    private func editRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .frame(width: 50, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.chromeForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .bracketBorder()
        }
        .padding(.leading, Self.editRowIndent)
        .padding(.trailing, 22)
    }
}

private struct StatusBarReorderList: View {
    @Bindable var model: ArcherSettingsModel
    @State private var draggingItem: StatusBarItemKind?
    @State private var endTargeted: Bool = false

    /// Items that participate in drag-reorder + right-side FlowLayout
    /// rendering. Excludes `.toolCallActivity` because its visual position
    /// is hardcoded (leftmost in the bar) and reordering wouldn't change
    /// anything visible. It still appears in the list under the "claude
    /// code" section, but without a drag handle.
    private var reorderableItems: [StatusBarItemKind] {
        model.statusBarItems.filter { !$0.isHardcodedSlot }
    }

    /// Builtin agents that report account usage (Codex). Their section shows a
    /// usage-gauge toggle.
    private var usageAgentIds: Set<String> {
        [AgentTemplate.codex.id]
    }

    /// Builtin agents with any status-bar feature (tool-call activity and/or a
    /// usage gauge), in builtin order — so the per-agent sections read
    /// Claude Code → Codex → Pi. Each renders one section (header + the
    /// feature toggles that apply to it); a future agent slots in by its
    /// builtin position automatically.
    private var statusAgents: [AgentTemplate] {
        AgentTemplate.builtin.filter { $0.reportsToolCalls || usageAgentIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Environment")
            ForEach(Array(reorderableItems.enumerated()), id: \.element) { index, item in
                if index > 0 { SettingsHairline() }
                StatusBarRow(
                    item: item,
                    visible: !model.hiddenStatusBarItems.contains(item),
                    isDragging: draggingItem == item,
                    reorderable: true,
                    onToggleVisible: { toggleVisible(item) },
                    onBeginDrag: { draggingItem = item },
                    onDrop: { droppedItem in
                        defer { draggingItem = nil }
                        return reorder(draggedItem: droppedItem, before: item)
                    }
                )
            }
            // One section per agent (header = icon + name), grouped by agent,
            // not by feature. Each agent's section shows the toggles for the
            // status-bar features it supports — tool-call pill and/or usage
            // gauge. Ordered Claude Code → Codex → Pi via `statusAgents`.
            ForEach(statusAgents) { agent in
                SettingsHairline()
                sectionHeader(agent.title, agentAsset: agent.iconAsset)
                if agent.reportsToolCalls {
                    StatusBarRow(
                        item: .toolCallActivity,
                        visible: !model.hiddenToolCallAgents.contains(agent.id),
                        isDragging: false,
                        reorderable: false,
                        onToggleVisible: { model.hiddenToolCallAgents.formSymmetricDifference([agent.id]) },
                        onBeginDrag: nil,
                        onDrop: nil
                    )
                }
                if usageAgentIds.contains(agent.id) {
                    StatusBarRow(
                        item: .codexUsage,
                        visible: !model.hiddenUsageAgents.contains(agent.id),
                        isDragging: false,
                        reorderable: false,
                        onToggleVisible: { model.hiddenUsageAgents.formSymmetricDifference([agent.id]) },
                        onBeginDrag: nil,
                        onDrop: nil
                    )
                }
            }
            Color.clear
                .frame(height: 10)
                .contentShape(Rectangle())
                .dropIndicator(active: endTargeted, on: .top, offset: 4)
                .dropDestination(for: String.self) { items, _ in
                    defer { draggingItem = nil }
                    guard let raw = items.first,
                          let dropped = StatusBarItemKind(rawValue: raw),
                          !dropped.isHardcodedSlot
                    else { return false }
                    return moveToEnd(dropped)
                } isTargeted: { endTargeted = $0 }

            HStack {
                Spacer()
                if hasCustomisation {
                    Button("reset to defaults") { model.resetStatusBar() }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeMuted)
                        .underline()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
        }
    }

    /// Brutalist mono section heading. `agentAsset`, when set, prepends
    /// the agent's iconAsset (e.g. `AgentTemplate.claudeCode.iconAsset`
    /// → the AgentIconView's rendered Claude mark) so a section belonging
    /// to a specific agent reads at a glance without a wall of text.
    private func sectionHeader(_ text: String, agentAsset: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let agentAsset {
                AgentIconView(asset: agentAsset, fallbackSymbol: "sparkles", size: 16)
            }
            Text(text)
                .font(Theme.mono(12, weight: .medium))
                .foregroundStyle(Theme.chromeMuted)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var hasCustomisation: Bool {
        model.statusBarItems != StatusBarItemKind.defaultOrder
            || !model.hiddenStatusBarItems.isEmpty
            || !model.hiddenToolCallAgents.isEmpty
            || !model.hiddenUsageAgents.isEmpty
    }

    private func toggleVisible(_ item: StatusBarItemKind) {
        if model.hiddenStatusBarItems.contains(item) {
            model.hiddenStatusBarItems.remove(item)
        } else {
            model.hiddenStatusBarItems.insert(item)
        }
    }

    private func reorder(draggedItem: StatusBarItemKind, before target: StatusBarItemKind) -> Bool {
        var order = model.statusBarItems
        guard let src = order.firstIndex(of: draggedItem),
              let dst = order.firstIndex(of: target),
              src != dst else { return false }
        let moved = order.remove(at: src)
        let adjusted = src < dst ? dst - 1 : dst
        order.insert(moved, at: adjusted)
        withAnimation(.easeInOut(duration: 0.18)) {
            model.statusBarItems = order
        }
        return true
    }

    private func moveToEnd(_ item: StatusBarItemKind) -> Bool {
        var order = model.statusBarItems
        guard let src = order.firstIndex(of: item), src != order.count - 1 else { return false }
        let moved = order.remove(at: src)
        order.append(moved)
        withAnimation(.easeInOut(duration: 0.18)) {
            model.statusBarItems = order
        }
        return true
    }
}

private struct StatusBarRow: View {
    let item: StatusBarItemKind
    let visible: Bool
    let isDragging: Bool
    /// When `false` the drag handle is replaced by an invisible spacer
    /// (matching `ReorderHandle`'s 22pt frame so the icon column stays
    /// aligned) and the row no longer hosts a `ReorderDropZone`. Used by
    /// the `.toolCallActivity` row whose position is hardcoded in the bar.
    let reorderable: Bool
    let onToggleVisible: () -> Void
    let onBeginDrag: (() -> Void)?
    let onDrop: ((StatusBarItemKind) -> Bool)?

    var body: some View {
        HStack(spacing: 12) {
            if reorderable, let onBeginDrag {
                ReorderHandle(payload: item.rawValue, onBeginDrag: onBeginDrag)
            }
            // No else — non-reorderable rows skip the handle column
            // entirely and the label hugs the row's left edge. Their
            // visual alignment matches the section header above (both
            // start 22pt in from the panel edge via the row padding).
            if let symbol = item.symbol {
                // Kinds with their own SF Symbol surface it here (Python
                // venv "p.circle.fill" etc.). `.toolCallActivity` returns
                // nil — its visual identity comes from the tool-call section
                // header's agent marks (Claude + Pi) rather than a per-row glyph.
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(visible ? Theme.chromeForeground : Theme.chromeMuted)
                    .frame(width: 14)
                    .opacity(visible ? 1.0 : 0.4)
            }
            Text(item.displayName)
                .font(Theme.mono(12.5))
                .foregroundStyle(visible ? Theme.chromeForeground : Theme.chromeMuted)
            Spacer(minLength: 14)
            Toggle("", isOn: Binding(get: { visible }, set: { _ in onToggleVisible() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(reorderableBackground)
        .opacity(isDragging ? 0.35 : 1.0)
    }

    @ViewBuilder
    private var reorderableBackground: some View {
        if reorderable, let onDrop {
            ReorderDropZone(row: item, isDragging: isDragging,
                            decode: StatusBarItemKind.init(rawValue:),
                            onDrop: onDrop)
        }
    }
}

/// Settings → Open in. Lists the catalog apps installed on this Mac (Finder
/// always present) with a visibility toggle + drag-reorder; the order + hidden
/// set drive the top-chrome split button's picker. Uninstalled catalog apps
/// are omitted — there's nothing to toggle. Mirrors `StatusBarReorderList`.
private struct OpenInReorderList: View {
    @Bindable var model: ArcherSettingsModel
    @State private var draggingId: String?
    @State private var endTargeted = false
    /// Bumped in `onAppear` after invalidating the resolver cache, to force
    /// `apps` to re-resolve this appearance (cache-clear alone isn't an
    /// observable change). See `onAppear` below.
    @State private var refreshTick = 0

    private var apps: [OpenInApp] {
        OpenInResolver.installedApps(model: model)
    }

    var body: some View {
        // Reading `refreshTick` registers the dependency so its onAppear bump
        // (below) invalidates this body and re-resolves `apps` against the
        // freshly-cleared resolver cache.
        let _ = refreshTick
        return VStack(alignment: .leading, spacing: 0) {
            Text("Apps installed on this Mac. The top-bar button opens the current tab's folder in your last-used one.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)

            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { SettingsHairline() }
                OpenInRow(
                    app: app,
                    visible: !model.hiddenOpenInApps.contains(app.id),
                    isDragging: draggingId == app.id,
                    onToggleVisible: { toggleVisible(app.id) },
                    onBeginDrag: { draggingId = app.id },
                    onDrop: { droppedId in
                        defer { draggingId = nil }
                        return reorder(draggedId: droppedId, before: app.id)
                    }
                )
            }

            Color.clear
                .frame(height: 10)
                .contentShape(Rectangle())
                .dropIndicator(active: endTargeted, on: .top, offset: 4)
                .dropDestination(for: String.self) { items, _ in
                    defer { draggingId = nil }
                    guard let id = items.first else { return false }
                    return moveToEnd(id)
                } isTargeted: { endTargeted = $0 }

            HStack {
                Spacer()
                if hasCustomisation {
                    Button("reset to defaults") { model.resetOpenIn() }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.chromeMuted)
                        .underline()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
        }
        // Drop any stale install/uninstall cache the top-bar button populated
        // during this session, then bump `refreshTick` so the list re-resolves
        // `apps` against the cleared cache on this same appearance — clearing
        // the cache isn't observable, so without the bump a newly-installed app
        // wouldn't show (or an uninstalled one wouldn't drop) until an unrelated
        // re-render.
        .onAppear {
            OpenInResolver.invalidate()
            refreshTick += 1
        }
    }

    private var hasCustomisation: Bool {
        !model.openInAppOrder.isEmpty || !model.hiddenOpenInApps.isEmpty
    }

    private func toggleVisible(_ id: String) {
        if model.hiddenOpenInApps.contains(id) {
            model.hiddenOpenInApps.remove(id)
        } else {
            model.hiddenOpenInApps.insert(id)
        }
    }

    /// Rewrites `openInAppOrder` to the full installed sequence after the move
    /// so the saved order is meaningful (rather than the sparse default).
    private func reorder(draggedId: String, before targetId: String) -> Bool {
        var order = apps.map(\.id)
        guard let src = order.firstIndex(of: draggedId),
              let dst = order.firstIndex(of: targetId),
              src != dst else { return false }
        let moved = order.remove(at: src)
        let adjusted = src < dst ? dst - 1 : dst
        order.insert(moved, at: adjusted)
        persistOrder(order)
        return true
    }

    private func moveToEnd(_ id: String) -> Bool {
        var order = apps.map(\.id)
        guard let src = order.firstIndex(of: id), src != order.count - 1 else { return false }
        let moved = order.remove(at: src)
        order.append(moved)
        persistOrder(order)
        return true
    }

    /// Persist a reordered *installed* sequence, keeping any previously-saved
    /// ids that aren't currently installed (appended at the tail) so an
    /// uninstall → reorder → reinstall round-trip doesn't drop that app's slot.
    private func persistOrder(_ installedOrder: [String]) {
        let installedSet = Set(installedOrder)
        let preserved = model.openInAppOrder.filter { !installedSet.contains($0) }
        withAnimation(.easeInOut(duration: 0.18)) {
            model.openInAppOrder = installedOrder + preserved
        }
    }
}

private struct OpenInRow: View {
    let app: OpenInApp
    let visible: Bool
    let isDragging: Bool
    let onToggleVisible: () -> Void
    let onBeginDrag: () -> Void
    let onDrop: (String) -> Bool

    var body: some View {
        HStack(spacing: 12) {
            ReorderHandle(payload: app.id, onBeginDrag: onBeginDrag)
            OpenInAppIcon(app: app, size: 16)
                .opacity(visible ? 1.0 : 0.4)
            Text(app.title)
                .font(Theme.mono(12.5))
                .foregroundStyle(visible ? Theme.chromeForeground : Theme.chromeMuted)
            Spacer(minLength: 14)
            Toggle("", isOn: Binding(get: { visible }, set: { _ in onToggleVisible() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(ReorderDropZone(row: app.id, isDragging: isDragging, decode: { $0 }, onDrop: onDrop))
        .opacity(isDragging ? 0.35 : 1.0)
    }
}

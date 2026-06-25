@testable import ArcherKit
import XCTest

@MainActor
final class AgentTemplateTests: XCTestCase {
    func testTerminalTemplateHasNoAgentEnv() {
        XCTAssertNil(AgentTemplate.terminal.makeSessionConfig().environment["ARCHER_AGENT"])
    }

    func testAgentTemplatesPublishArcherAgentEnv() {
        for template in AgentTemplate.all where template.id != "terminal" {
            XCTAssertEqual(
                template.makeSessionConfig().environment["ARCHER_AGENT"],
                template.initialCommand,
                "agent template \(template.id) must publish ARCHER_AGENT matching its initialCommand"
            )
        }
    }

    func testAllTemplatesAreUniqueAndIncludeTerminal() {
        let ids = AgentTemplate.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids must be unique")
        XCTAssertTrue(ids.contains("terminal"))
    }

    func testTerminalTemplateUsesUserDefaultShell() {
        // Terminal respects the user's shell, but bash/zsh route through an
        // integration wrapper (bash → archer-bash-launch-*, zsh → /bin/zsh);
        // only unwrapped shells (fish/nu/...) surface $SHELL verbatim. Assert
        // per detected shell so the test holds on bash CI runners too.
        let cmd = AgentTemplate.terminal.makeSessionConfig().command
        switch ArcherShellIntegration.detectedUserShell {
        case .zsh:
            XCTAssertEqual(cmd, ArcherShellIntegration.zshPath)
        case .bash:
            XCTAssertTrue(cmd.contains("archer-bash-launch-"), "bash terminal must use the launcher wrapper: \(cmd)")
        case .fish:
            XCTAssertEqual(cmd, ProcessInfo.processInfo.environment["SHELL"] ?? "/usr/local/bin/fish")
        case .other:
            XCTAssertEqual(cmd, ProcessInfo.processInfo.environment["SHELL"] ?? ArcherShellIntegration.zshPath)
        }
    }

    func testAgentTemplatesPickAShellWithIntegrationWrapper() {
        // Agent must run under one of our wrappers (zsh ZDOTDIR, bash --rcfile,
        // or fish XDG_DATA_DIRS) — anything else means ARCHER_AGENT never fires.
        for template in AgentTemplate.all where template.id != "terminal" {
            let cmd = template.makeSessionConfig().command
            let isFish = cmd.hasSuffix("/fish")
            XCTAssertTrue(
                cmd == "/bin/zsh" || cmd.contains("archer-bash-launch-") || isFish,
                "agent template \(template.id) launched without a archer shell wrapper: \(cmd)"
            )
        }
    }

    func testBuiltinTemplatesHaveNoBaseAgentId() {
        for template in AgentTemplate.builtin {
            XCTAssertNil(template.baseAgentId, "builtin \(template.id) must not declare a base")
        }
    }

    func testFromCustomSnapshotsBaseAgentId() {
        let data = CustomAgentData(id: "claude-opus", baseAgentId: "claude-code")
        XCTAssertEqual(AgentTemplate.fromCustom(data).baseAgentId, "claude-code")
    }

    func testFromCustomTreatsEmptyBaseAsNil() {
        let data = CustomAgentData(id: "loose-custom", command: "aichat")
        XCTAssertNil(AgentTemplate.fromCustom(data).baseAgentId)
    }

    @MainActor
    func testOrderedKeepsHalfConfiguredCustoms() {
        // Regression: when `ordered(model:)` filtered with `!isShell`, a
        // freshly-added custom agent (initialCommand still nil until the
        // user fills `command` or picks a `baseAgentId`) vanished from
        // Settings → Agents — the user couldn't continue editing the row
        // they just created. `ordered` must keep these visible; the
        // `+` menu's own `initialCommand != nil` gate (in `visibleOrdered`)
        // is what hides them from the launch surface.
        //
        // `ordered` reads `customAgents` off `ArcherSettingsModel.shared`
        // (via `all`), so the test snapshots + restores the singleton
        // rather than constructing a fresh model.
        let model = ArcherSettingsModel.shared
        let snapshot = model.customAgents
        defer { model.customAgents = snapshot }
        model.customAgents = [CustomAgentData(id: "draft-custom")]
        let ordered = AgentTemplate.ordered(model: model)
        XCTAssertTrue(ordered.contains(where: { $0.id == "draft-custom" }),
                      "half-configured custom must stay in Settings list")
    }

    // MARK: - Terminal presets

    func testFromTerminalPresetSnapshotsPathAsExtraCwd() {
        let preset = TerminalPreset(id: "preset-1", title: "Work", path: "~/projects/foo")
        let template = AgentTemplate.fromTerminalPreset(preset)
        XCTAssertEqual(template.id, "preset-1")
        XCTAssertEqual(template.title, "Work")
        XCTAssertEqual(template.extraCwd, "~/projects/foo")
        XCTAssertNil(template.initialCommand, "presets are terminals — must not carry a binary")
        XCTAssertEqual(template.iconAsset, AgentTemplate.terminal.iconAsset)
    }

    func testFromTerminalPresetTitleFallsBackToBasename() {
        // Blank title is fine — many users will rename later. Until they
        // do, the path basename reads better than `preset-1`.
        let preset = TerminalPreset(id: "preset-1", title: "", path: "~/projects/foo")
        XCTAssertEqual(AgentTemplate.fromTerminalPreset(preset).title, "foo")
    }

    func testFromTerminalPresetTitleFallsBackToIdWhenAllBlank() {
        let preset = TerminalPreset(id: "preset-1", title: "", path: "")
        XCTAssertEqual(AgentTemplate.fromTerminalPreset(preset).title, "preset-1")
    }

    func testFromTerminalPresetTreatsEmptyPathAsNilExtraCwd() {
        // Empty path = no override → addTab falls through to the workspace
        // cwd instead of trying to expand "" via NSString.
        let preset = TerminalPreset(id: "preset-1", title: "Untouched", path: "")
        XCTAssertNil(AgentTemplate.fromTerminalPreset(preset).extraCwd)
    }

    func testVisibleOrderedDropsHiddenPresets() {
        // Toggling a preset off in Settings → Terminals should remove it
        // from the `+` menu but keep its config alive — symmetric with
        // hiding an agent via the Agents toggle.
        let model = ArcherSettingsModel()
        model.terminalPresets = [
            TerminalPreset(id: "preset-shown", title: "Shown", path: "/tmp"),
            TerminalPreset(id: "preset-hidden", title: "Hidden", path: "/var"),
        ]
        model.hiddenPresets = ["preset-hidden"]
        model.hiddenAgents = []
        model.agentOrder = []
        let ids = AgentTemplate.visibleOrdered(model: model).map(\.id)
        XCTAssertTrue(ids.contains("preset-shown"))
        XCTAssertFalse(ids.contains("preset-hidden"), "hidden preset must not appear in + menu")
    }

    func testVisibleOrderedDropsPresetsWithBlankPath() {
        // A just-added preset with no path entered yet must not pollute
        // the `+` menu — it would render as a no-op duplicate of the
        // default Terminal under a misleading "preset-N" label.
        let model = ArcherSettingsModel()
        model.terminalPresets = [
            TerminalPreset(id: "preset-blank", title: "Blank", path: ""),
            TerminalPreset(id: "preset-whitespace", title: "Whitespace", path: "   "),
            TerminalPreset(id: "preset-real", title: "Real", path: "/tmp"),
        ]
        model.hiddenAgents = []
        model.agentOrder = []
        let ids = AgentTemplate.visibleOrdered(model: model).map(\.id)
        XCTAssertFalse(ids.contains("preset-blank"), "blank-path preset must not appear in + menu")
        XCTAssertFalse(ids.contains("preset-whitespace"), "whitespace-only path counts as blank")
        XCTAssertTrue(ids.contains("preset-real"), "path-bearing preset still surfaces")
    }

    func testVisibleOrderedInsertsPresetsBetweenTerminalAndAgents() {
        // A fresh model reads the user's actual settings.json — overwrite
        // the slots we care about so the test stays deterministic across
        // machines and across whatever the developer has saved locally.
        let model = ArcherSettingsModel()
        model.terminalPresets = [
            TerminalPreset(id: "preset-a", title: "A", path: "/tmp"),
            TerminalPreset(id: "preset-b", title: "B", path: "/var"),
        ]
        model.hiddenAgents = []
        model.agentOrder = []
        let list = AgentTemplate.visibleOrdered(model: model)
        XCTAssertEqual(list.first?.id, "terminal")
        XCTAssertEqual(list[1].id, "preset-a")
        XCTAssertEqual(list[2].id, "preset-b")
        XCTAssertEqual(list[3].id, AgentTemplate.claudeCodeID,
                       "agents must follow the preset block; Claude is the first builtin agent after Terminal")
    }

    func testMakeSessionConfigInjectsResumeFlagForClaude() {
        let config = AgentTemplate.claudeCode.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude --resume abc-123")
    }

    func testMakeSessionConfigCombinesResumeAndExtras() {
        let config = AgentTemplate.claudeCode.makeSessionConfig(extraOptions: "--model opus", resumeId: "abc-123")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude --resume abc-123 --model opus")
    }

    func testMakeSessionConfigSkipsResumeWhenIdEmpty() {
        let config = AgentTemplate.claudeCode.makeSessionConfig(resumeId: "")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude")
    }

    func testMakeSessionConfigIgnoresResumeOnUnsupportedBuiltins() {
        // Codex / Cursor / Gemini / OpenCode / Copilot / Amp / Grok /
        // Antigravity all support a resume flag syntactically but archer
        // doesn't have a reliable id-capture path for them yet, so we
        // don't inject the flag — see AgentTemplate.supportsResume /
        // resumeFlag.
        let codexConfig = AgentTemplate.codex.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(codexConfig.environment["ARCHER_AGENT"], "codex")
        let copilotConfig = AgentTemplate.copilot.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(copilotConfig.environment["ARCHER_AGENT"], "copilot")
        let grokConfig = AgentTemplate.grok.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(grokConfig.environment["ARCHER_AGENT"], "grok")
        let antigravityConfig = AgentTemplate.antigravity.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(antigravityConfig.environment["ARCHER_AGENT"], "agy")
        let kimiConfig = AgentTemplate.kimi.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(kimiConfig.environment["ARCHER_AGENT"], "kimi")
        let kiroConfig = AgentTemplate.kiro.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(kiroConfig.environment["ARCHER_AGENT"], "kiro-cli")
        let hermesConfig = AgentTemplate.hermes.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(hermesConfig.environment["ARCHER_AGENT"], "hermes")
    }

    func testSupportsResumeMatchesResumeFlag() {
        XCTAssertTrue(AgentTemplate.claudeCode.supportsResume)
        XCTAssertFalse(AgentTemplate.codex.supportsResume)
        XCTAssertFalse(AgentTemplate.copilot.supportsResume)
        XCTAssertFalse(AgentTemplate.grok.supportsResume)
        XCTAssertFalse(AgentTemplate.antigravity.supportsResume)
        XCTAssertFalse(AgentTemplate.kimi.supportsResume)
        XCTAssertFalse(AgentTemplate.kiro.supportsResume)
        XCTAssertFalse(AgentTemplate.hermes.supportsResume)
        XCTAssertTrue(AgentTemplate.pi.supportsResume)
    }

    func testMakeSessionConfigInjectsResumeForClaudeBasedCustom() {
        let custom = CustomAgentData(id: "claude-opus", baseAgentId: "claude-code")
        let template = AgentTemplate.fromCustom(custom)
        let config = template.makeSessionConfig(resumeId: "xyz")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude --resume xyz")
    }

    func testMakeSessionConfigInjectsResumeForPi() {
        // Pi takes a launch-time `--session <id>`; the extension captures the
        // session id and reports it via `archer-hook pi conversation <id>`.
        let config = AgentTemplate.pi.makeSessionConfig(resumeId: "abc-123")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "pi --session abc-123")
    }

    func testReportsToolCallsOnlyForToolFeedingAgents() {
        // Claude (hooks) + Pi (extension tool_execution_* events) feed archer
        // per-tool-call activity; every other builtin (incl. shells) does not.
        XCTAssertTrue(AgentTemplate.claudeCode.reportsToolCalls)
        XCTAssertTrue(AgentTemplate.pi.reportsToolCalls)
        XCTAssertFalse(AgentTemplate.terminal.reportsToolCalls)
        XCTAssertFalse(AgentTemplate.codex.reportsToolCalls)
        XCTAssertFalse(AgentTemplate.gemini.reportsToolCalls)
        XCTAssertFalse(AgentTemplate.kimi.reportsToolCalls)
        XCTAssertFalse(AgentTemplate.copilot.reportsToolCalls)
        XCTAssertFalse(AgentTemplate.kiro.reportsToolCalls)
        XCTAssertFalse(AgentTemplate.hermes.reportsToolCalls)
    }

    func testFromCustomInheritsReportsToolCallsFromBase() {
        // A custom built on Claude / Pi inherits the tool-call pill; one built
        // on a non-reporting base (or none) does not — mirrors resumeFlag.
        XCTAssertTrue(AgentTemplate.fromCustom(CustomAgentData(id: "c1", baseAgentId: "claude-code")).reportsToolCalls)
        XCTAssertTrue(AgentTemplate.fromCustom(CustomAgentData(id: "c2", baseAgentId: "pi")).reportsToolCalls)
        XCTAssertFalse(AgentTemplate.fromCustom(CustomAgentData(id: "c3", baseAgentId: "codex")).reportsToolCalls)
        XCTAssertFalse(AgentTemplate.fromCustom(CustomAgentData(id: "c4", baseAgentId: "")).reportsToolCalls)
    }

    // MARK: - initialPrompt (Ask <agent> right-click path)

    func testMakeSessionConfigPositionalPromptForClaude() {
        let config = AgentTemplate.claudeCode.makeSessionConfig(initialPrompt: "fix this error")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude -- 'fix this error'")
    }

    func testMakeSessionConfigFlagPromptForCopilot() {
        let config = AgentTemplate.copilot.makeSessionConfig(initialPrompt: "fix this error")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "copilot -p 'fix this error'")
    }

    func testMakeSessionConfigFlagPromptForAmp() {
        let config = AgentTemplate.amp.makeSessionConfig(initialPrompt: "fix this error")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "amp -x 'fix this error'")
    }

    func testMakeSessionConfigFlagPromptForAntigravity() {
        let config = AgentTemplate.antigravity.makeSessionConfig(initialPrompt: "fix this error")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "agy -i 'fix this error'")
    }

    func testMakeSessionConfigFlagPromptForKimi() {
        let config = AgentTemplate.kimi.makeSessionConfig(initialPrompt: "fix this error")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "kimi -p 'fix this error'")
    }

    func testMakeSessionConfigFlagPromptForHermes() {
        let config = AgentTemplate.hermes.makeSessionConfig(initialPrompt: "fix this error")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "hermes -p 'fix this error'")
    }

    func testMakeSessionConfigFlagPromptForPi() {
        let config = AgentTemplate.pi.makeSessionConfig(initialPrompt: "fix this error")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "pi -p 'fix this error'")
    }

    // MARK: - Monochrome icon theming

    func testMonochromeIconSetReferencesRealBuiltinAssets() {
        // A typo in `monochromeAssets` would silently skip theme-adaptive
        // tinting for that agent, so pin every entry to a real builtin iconAsset.
        let builtinAssets = Set(AgentTemplate.builtin.compactMap(\.iconAsset))
        for name in AgentIcon.monochromeAssets {
            XCTAssertTrue(builtinAssets.contains(name),
                          "monochrome asset \(name) matches no builtin iconAsset")
        }
    }

    func testMonochromeBrandsTintedAndColorBrandsRenderedAsIs() {
        // The white-mark brands get template-tinted so they survive a light
        // theme; the color brands keep their own pixels on every theme.
        for mono in ["opencode", "cursor", "githubcopilot", "grok", "kimi", "pi"] {
            XCTAssertTrue(AgentIcon.isMonochrome(mono), "\(mono) should be template-tinted")
        }
        for color in ["claudecode", "codex", "gemini", "amp", "antigravity", "kiro", "hermes"] {
            XCTAssertFalse(AgentIcon.isMonochrome(color), "\(color) is a color brand, render as-is")
        }
    }

    func testMakeSessionConfigPositionalPromptForFlaglessAgents() {
        let pairs: [(AgentTemplate, String)] = [
            (.codex, "codex"),
            (.cursor, "cursor-agent"),
            (.gemini, "gemini"),
            (.opencode, "opencode"),
            (.grok, "grok"),
            (.kiro, "kiro-cli"),
        ]
        for (template, bin) in pairs {
            let config = template.makeSessionConfig(initialPrompt: "hello")
            XCTAssertEqual(config.environment["ARCHER_AGENT"], "\(bin) -- 'hello'", "agent \(template.id)")
        }
    }

    func testMakeSessionConfigQuotesSingleQuotesInPrompt() {
        // POSIX wrap: `'` inside single quotes becomes `'\''`
        let config = AgentTemplate.claudeCode.makeSessionConfig(initialPrompt: "don't fix it")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude -- 'don'\\''t fix it'")
    }

    func testMakeSessionConfigCombinesPromptAndExtras() {
        let config = AgentTemplate.claudeCode.makeSessionConfig(extraOptions: "--model opus", initialPrompt: "review this")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude -- 'review this' --model opus")
    }

    func testInitialPromptSuppressesResume() {
        // Ask <agent> is a fresh question — don't graft onto a stale
        // conversation. Both supplied → prompt wins, resume dropped.
        let config = AgentTemplate.claudeCode.makeSessionConfig(resumeId: "old-convo", initialPrompt: "new question")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "claude -- 'new question'")
    }

    func testEmptyInitialPromptIgnored() {
        let blankConfig = AgentTemplate.claudeCode.makeSessionConfig(initialPrompt: "   ")
        XCTAssertEqual(blankConfig.environment["ARCHER_AGENT"], "claude")
        let resumeConfig = AgentTemplate.claudeCode.makeSessionConfig(resumeId: "abc", initialPrompt: "")
        XCTAssertEqual(resumeConfig.environment["ARCHER_AGENT"], "claude --resume abc")
    }

    func testFromCustomInheritsPromptLaunchFlagFromCopilotBase() {
        // Codex P2 (v0.10.9): a Copilot-based custom must inherit Copilot's
        // `-p` flag — otherwise right-click Ask sends the prompt as a
        // positional argv that Copilot ignores.
        let custom = CustomAgentData(id: "copilot-beta", baseAgentId: "copilot")
        let template = AgentTemplate.fromCustom(custom)
        let config = template.makeSessionConfig(initialPrompt: "hello")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "copilot -p 'hello'")
    }

    func testFromCustomInheritsPromptLaunchFlagFromAmpBase() {
        let custom = CustomAgentData(id: "amp-beta", baseAgentId: "amp")
        let template = AgentTemplate.fromCustom(custom)
        let config = template.makeSessionConfig(initialPrompt: "hello")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "amp -x 'hello'")
    }

    func testPositionalPromptWithDashPrefixRoutedThroughSeparator() {
        // Real-world bug: user right-clicks `ls -la` output, the first
        // line begins `-rw-r--r--@`. Without the `--` separator the
        // agent's argparse would reject it as an unknown flag. The
        // POSIX separator + POSIX-quoted prompt together neutralise it.
        let config = AgentTemplate.codex.makeSessionConfig(initialPrompt: "-rw-r--r--@  1 mac staff  44")
        XCTAssertEqual(config.environment["ARCHER_AGENT"], "codex -- '-rw-r--r--@  1 mac staff  44'")
    }

    // MARK: - parseEnv (custom-agent environment block)

    func testParseEnvBasicPair() {
        XCTAssertEqual(
            AgentTemplate.parseEnv("ANTHROPIC_BASE_URL=https://api.example.com"),
            ["ANTHROPIC_BASE_URL": "https://api.example.com"]
        )
    }

    func testParseEnvMultipleLines() {
        XCTAssertEqual(
            AgentTemplate.parseEnv("ANTHROPIC_BASE_URL=https://api.example.com\nANTHROPIC_AUTH_TOKEN=sk-abc123"),
            ["ANTHROPIC_BASE_URL": "https://api.example.com", "ANTHROPIC_AUTH_TOKEN": "sk-abc123"]
        )
    }

    func testParseEnvSkipsBlankAndCommentLines() {
        XCTAssertEqual(
            AgentTemplate.parseEnv("# a comment\nFOO=bar\n\n   # indented comment\nBAZ=qux"),
            ["FOO": "bar", "BAZ": "qux"]
        )
    }

    func testParseEnvStripsExportPrefix() {
        XCTAssertEqual(AgentTemplate.parseEnv("export FOO=bar"), ["FOO": "bar"])
    }

    func testParseEnvStripsExportWithTab() {
        XCTAssertEqual(AgentTemplate.parseEnv("export\tFOO=bar"), ["FOO": "bar"])
    }

    func testParseEnvHandlesCRLFLineEndings() {
        // A block pasted from a Windows editor / web copy uses \r\n — the
        // parser must split it into separate pairs, not collapse the whole
        // block into the first key's value.
        XCTAssertEqual(
            AgentTemplate.parseEnv("FOO=bar\r\nBAZ=qux\rZIP=zap"),
            ["FOO": "bar", "BAZ": "qux", "ZIP": "zap"]
        )
    }

    func testParseEnvSplitsOnFirstEquals() {
        // A value containing `=` (URL query string) must survive intact.
        XCTAssertEqual(
            AgentTemplate.parseEnv("URL=https://x.com/path?a=1&b=2"),
            ["URL": "https://x.com/path?a=1&b=2"]
        )
    }

    func testParseEnvUnwrapsSurroundingQuotes() {
        XCTAssertEqual(AgentTemplate.parseEnv(#"FOO="hello world""#), ["FOO": "hello world"])
        XCTAssertEqual(AgentTemplate.parseEnv("FOO='single'"), ["FOO": "single"])
    }

    func testParseEnvTrimsWhitespace() {
        XCTAssertEqual(AgentTemplate.parseEnv("  FOO = bar  "), ["FOO": "bar"])
    }

    func testParseEnvDropsInvalidKeys() {
        // Leading digit, space in key, empty key, and a line with no `=`
        // are all dropped — only `GOOD` survives.
        XCTAssertEqual(
            AgentTemplate.parseEnv("1FOO=bad\nMY VAR=bad\n=bad\ngarbage line\nGOOD=ok"),
            ["GOOD": "ok"]
        )
    }

    func testParseEnvDropsArcherPrefixedKeys() {
        // A custom agent must not shadow archer's own env — ARCHER_SURFACE_ID
        // in particular routes hook pings to the right tab.
        XCTAssertEqual(AgentTemplate.parseEnv("ARCHER_SURFACE_ID=evil\nFOO=ok"), ["FOO": "ok"])
    }

    func testParseEnvLaterLineWinsOnDuplicateKey() {
        XCTAssertEqual(AgentTemplate.parseEnv("FOO=first\nFOO=second"), ["FOO": "second"])
    }

    func testParseEnvEmptyBlockYieldsEmptyDict() {
        XCTAssertTrue(AgentTemplate.parseEnv("").isEmpty)
        XCTAssertTrue(AgentTemplate.parseEnv("\n\n   \n").isEmpty)
    }

    // MARK: - extraEnv snapshot

    func testFromCustomParsesEnvIntoExtraEnv() {
        let custom = CustomAgentData(
            id: "claude-mirror",
            baseAgentId: "claude-code",
            env: "ANTHROPIC_BASE_URL=https://mirror.example.com\nANTHROPIC_AUTH_TOKEN=sk-xyz"
        )
        let template = AgentTemplate.fromCustom(custom)
        XCTAssertEqual(template.extraEnv, [
            "ANTHROPIC_BASE_URL": "https://mirror.example.com",
            "ANTHROPIC_AUTH_TOKEN": "sk-xyz",
        ])
    }

    func testBuiltinTemplatesHaveEmptyExtraEnv() {
        for template in AgentTemplate.builtin {
            XCTAssertTrue(template.extraEnv.isEmpty, "builtin \(template.id) must not carry extraEnv")
        }
    }
}

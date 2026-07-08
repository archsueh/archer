# Project: Archer

Rebranded from Kooky/Sailor. Archer is a lightweight, vibe-coding developer cockpit featuring a terminal, sidebars, file tree, glass aesthetics, and AI agent integration.

## Working Memory — read first, write last

- **开局必读**: Before doing anything, read [`STATE.md`](STATE.md) — it holds verified facts (paths/ports/schema), general rules distilled from past bugs, open in-progress work, and a resume pointer. Treat its **Verified facts** as ground truth; don't re-derive them. If a fact there contradicts the live repo, the repo wins — fix `STATE.md`.
- **走前必写**: Before ending a nontrivial session, update `STATE.md` — what was tried, what passed/failed, any new rule that survived, and the **Last session** resume pointer. If a session doesn't finish with a write, the next one restarts from zero.

**Project Memory Pattern** (from long-term practice): Use this CLAUDE.md + STATE.md + DESIGN.md + specs/ as living memory. On new session or handoff, paste key sections (data models, design decisions, current progress, open questions). This pattern has been validated across multiple ongoing projects (e.g. cost-tracking apps, design systems, toolchains).

## Key Commands

- **Build**: `swift build`
- **Test**: `swift test`
- **Run**: `swift run`
- **Clean Build Cache**: `rm -rf .build`

## Interaction & Engineering Style

Cross-project user preferences live in global memory (`~/.claude/.../memory/`: `feedback-response-style`, `feedback-laoguiju-review`, `user-identity`) — honesty-first, expert depth, evidence-only reviews, full ready-to-run artifacts. Not duplicated here per STATE.md's 分工 rule: project files carry project facts only.

## Code & Design Standards

- **Branding**: Always use **Archer** (case-preserving: `ARCHER`, `Archer`, `archer`). Avoid referencing `Kooky` or `Sailor`.
- **Annotations**: Retain and use `// [archer]` for developer annotations.
- **Glass Aesthetics**: Back windows with native `NSVisualEffectView` backing (HUD vibrancy) behind translucent views. Keep chrome surfaces translucent.
- **Glass params are global defaults — do not change them per theme**: `Theme.glassOpacity`, `chromeBackgroundBlur`, and `chromeBackgroundSaturate` in `Theme.swift` are the baseline for all themes. Adding a new terminal theme (e.g. `liquid-glass`) must NOT silently alter these values. If a theme needs different glass feel, expose it as a per-theme override — never hardcode new defaults that override the user's slider-aligned settings. The `aver-light` ivory-white (`#FDF9F4`) daytime theme is the canonical reference; its appearance must be preserved.
- **No Placeholders**: Never use placeholder images. Generate assets as needed.
- **Indentation**: Swift standard 4-space indentation.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

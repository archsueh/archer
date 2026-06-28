# Project: Archer

Rebranded from Kooky/Sailor. Archer is a lightweight, vibe-coding developer cockpit featuring a terminal, sidebars, file tree, glass aesthetics, and AI agent integration.

## Key Commands

- **Build**: `swift build`
- **Test**: `swift test`
- **Run**: `swift run`
- **Clean Build Cache**: `rm -rf .build`

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

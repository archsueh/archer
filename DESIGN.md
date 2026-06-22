---
version: alpha
name: Archer
description: Brutalist-minimal developer cockpit console featuring sharp corners, glass aesthetics, and dynamic low-contrast chrome.
colors:
  primary: "#EFEFF1"      # chrome-foreground
  secondary: "#9E9EA0"    # chrome-muted
  neutral: "#282C34"      # terminal-surface
  chrome-hairline: "rgba(255, 255, 255, 0.07)"
  chrome-hover: "rgba(255, 255, 255, 0.07)"
  chrome-active: "rgba(255, 255, 255, 0.15)"
  active-running: "#69B0D6"
  active-attention: "#E8B068"
  active-failure: "#E86666"
  git-insertion: "#73C780"
  git-deletion: "#E86666"
typography:
  display-label:
    fontFamily: Onest
    fontSize: 13px
    fontWeight: 400
  mono-button:
    fontFamily: "JetBrains Mono"
    fontSize: 11.5px
    fontWeight: 500
rounded:
  brutalist: 0px
spacing:
  space1: 4px
  space2: 8px
  space3: 12px
  space4: 16px
  space5: 24px
components:
  bracket-button:
    backgroundColor: "{colors.chrome-hover}"
    textColor: "{colors.primary}"
    rounded: "{rounded.brutalist}"
    padding: "5px 10px"
  terminal-pane:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
  pane-border:
    backgroundColor: "{colors.chrome-hairline}"
  session-tab-active:
    backgroundColor: "{colors.chrome-active}"
    textColor: "{colors.primary}"
  status-indicator-running:
    textColor: "{colors.active-running}"
  status-indicator-attention:
    textColor: "{colors.active-attention}"
  status-indicator-failure:
    textColor: "{colors.active-failure}"
  git-indicator-insertion:
    textColor: "{colors.git-insertion}"
  git-indicator-deletion:
    textColor: "{colors.git-deletion}"
---

## Overview

Archer is a native macOS developer cockpit hub featuring a terminal (based on libghostty), dynamic sidebars, a file tree, usage monitoring, and a glass-vibrancy skin. It uses a **Brutalist-Minimal** aesthetic that balances functional engineering density with low-key structural chrome.

## Colors

The visual elements dynamically adapt to the active terminal theme. The resolved color tokens are derived from `selectedTerminalTheme`:
- **Primary / Chrome Foreground:** `#EFEFF1` (default active text color).
- **Secondary / Chrome Muted:** `#9E9EA0` (secondary status/labels).
- **Neutral / Terminal Surface:** `#282C34` (the central terminal surface background color).
- **Active Statuses:** `Theme.activityRunning` (cool blue `#69B0D6`), `Theme.activityAttention` (warm amber `#E8B068`), `Theme.activityFailure` (warm red `#E86666`).
- **Git status indicators:** `Theme.gitInsertion` (green `#73C780`) and `Theme.gitDeletion` (red `#E86666`).

## Typography

Archer bundles two primary typefaces:
- **Onest:** Primary sans-serif display font for labels, settings, and structural text.
- **JetBrains Mono:** Monospace font used for terminal output, command palettes, and `[bracketed]` interactive controls.

## Layout

- **4-Pixel Spacing Grid:** Spacing conforms strictly to the `space1` through `space5` tokens, maintaining rigid horizontal and vertical alignment.
- **Chrome Breathing:** Margin and padding defaults favor `space3` (12pt) and `space4` (16pt) to give functional text breathing room.

## Elevation & Depth

Archer relies on flat surfaces and sharp borders rather than drop shadows:
- **Zero Shadow:** Surfaces sit on a flat grid layer.
- **Brutalist Borders:** Custom hairline frames are built using the `.bracketBorder()` modifier, rendering a 1pt hairline stroke (`Theme.chromeHairline`) around containers.
- **Glassmorphism:** The overall window has a native `NSVisualEffectView` backing (HUD vibrancy) with translucent view styling. Window background opacity is fixed at `Theme.glassOpacity` (`0.72`).

## Shapes

- **Brutalist Sharpness:** Corner radius is strictly configured to `0px` (`rounded.brutalist`). Standard macOS rounded buttons and rounded rectangles are suppressed in favor of sharp rects.

## Components

### bracket-button
A custom interactive primitive representing a plain-text `[bracketed]` control:
- Background: Changes to `{colors.chrome-hover}` on hover.
- Font: `{typography.mono-button}`.
- Border: 1pt hairline stroke via `bracketBorder()`.

### edge-glow
A screen-edge activity glow that mirrors the chime: a thin, sharp-cornered hairline stroke painted around the screen edge on a transparent click-through overlay window. Color comes **only** from the activity tokens — running `{colors.active-running}` (turn complete, brief pulse), attention `{colors.active-attention}` and failure `{colors.active-failure}` (held until archer regains focus). Low default brightness, narrow width, zero corner radius, no rainbow. Off-by-toggle. See `docs/edge-glow-spec.md`.

## Do's and Don'ts

### Do
- Use sharp corners (`cornerRadius = 0`) on all buttons, text fields, and panels.
- Retain and use `// [archer]` for developer annotations to keep upstream diff tracking clean.
- Reference the unified `Theme.glassOpacity` (`0.72`) for translucent panels.
- Keep spacer gaps aligned to multiples of 4 (`space1` to `space5`).

### Don't
- Do not use default rounded rectangles or soft drop shadows.
- Do not hardcode hex colors for the chrome; colors must be computed dynamically using the dynamic `Theme.resolved` values.
- Do not use custom animations; transition speeds must match `Theme.chromeTransition` (`easeInOut(duration: 0.2)`).

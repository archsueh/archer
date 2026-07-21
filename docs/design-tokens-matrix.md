# Design Tokens Matrix · 0357fb47 ↔ Theme

> PR0 · Verified 2026-07-21  
> Design: `~/Downloads/archer-old-0357fb47/styles.css`  
> Production: `Sources/ArcherKit/App/Theme.swift` + root `DESIGN.md`  
> **Red line**: do not change `glassOpacity` / `chromeBackgroundBlur` / `chromeBackgroundSaturate` defaults.

| Design CSS | Value | Swift / DESIGN | Status |
|------------|-------|----------------|--------|
| `--primary` | `#EFEFF1` | `Theme.chromeForeground` (default FG) | ✅ |
| `--secondary` | `#9E9EA0` | `Theme.chromeMuted` (derived mix) | ✅ |
| `--neutral` | `#282C34` | terminal surface (theme-driven; default `#2A2A2A`) | ✅ ~ |
| `--surface-2` | `#21242b` | no dedicated symbol; use `chromeSurface` / derived chrome bg | ⚪ doc-only |
| `--chrome-hairline` | `rgba(255,255,255,.07)` | `Theme.chromeHairline` (dark) | ✅ |
| `--chrome-hover` | `rgba(255,255,255,.07)` | `Theme.chromeHover` (dark) | ✅ |
| `--chrome-active` | `rgba(255,255,255,.15)` | `Theme.chromeActive` (dark) | ✅ |
| `--active-running` | `#69B0D6` | `Theme.activityRunning` | ✅ |
| `--active-attention` | `#E8B068` | `Theme.activityAttention` | ✅ |
| `--active-failure` | `#E86666` | `Theme.activityFailure` | ✅ |
| `--git-insertion` | `#73C780` | `Theme.gitInsertion` | ✅ |
| `--git-deletion` | `#E86666` | `Theme.gitDeletion` | ✅ |
| `--glass-opacity` | `0.72` | `Theme.glassOpacity` | ✅ **immutable default** |
| `--font-sans` | Onest | `Theme.display(_:)` | ✅ |
| `--font-mono` | JetBrains Mono | `Theme.mono(_:)` | ✅ |
| space1–5 | 4/8/12/16/24 | `Theme.space1`…`space5` | ✅ |
| chrome transition | 0.2s easeInOut | `Theme.chromeTransition` | ✅ |
| glass blur/sat | blur 40 / sat 1.4 (HTML preview) | `chromeBackgroundBlur` 30 / `Saturate` 1.3 | ✅ intentional (native vibrancy ≠ CSS) |

## Layout density (interface.html → production)

| Spec | Design | Production target |
|------|--------|-------------------|
| Titlebar height | 48 | ContentView topStrip 48 ✅ |
| Tab bar | 44 | TabBarView 40 (~ close) |
| Pane head / tab label | mono 11–11.5 + `@label` running | TabBarItem + `@id` (this slice) |
| Bridge bar head | 30h, mono 11 | `BridgeActivityBar` |
| Sidebar width | 230 | `PanelWidths.sidebar` (user-resizable) |
| Files width | 300 | `PanelWidths.rightPanel` |

## Glass decision

- **Production**: real `NSVisualEffectView` + `Theme.glassOpacity` — not CSS radial fake wallpaper.
- **Design HTML**: floating 18px radius window is preview chrome only; main app keeps system window chrome.
- Light / `aver-light`: hairline/hover opacities already branch in `Theme.Resolved` — keep.

## Gaps deferred (not blocking)

- Expose `surface-2` only if a fixed dark panel needs non-theme color (prefer theme-derived).
- CSS blur 40 vs native 30: leave; do not raise global blur to “match HTML”.

# Archer Design System & Tokens (DESIGN.md)

This specification defines the brutalist-minimal visual design system for **Archer**.

## 1. Visual Aesthetics & Philosophy

Archer uses a **Brutalist-Minimal** aesthetic:
* **Sharp Corners**: All layout containers, inputs, buttons, and windows must have sharp corners (`cornerRadius = 0`). Do not use default rounded rectangles.
* **Low Contrast Chrome**: Chrome panels (Sidebar, TabBar, Settings) use low contrast background and foreground tones derived dynamically from the selected terminal theme.
* **Framed Terminal Canvas**: The terminal or editor pane represents the central canvas, with other chrome views sitting exactly one step off the surface.
* **Precedence over default styles**: Use `.bracketBorder()` (1pt hairline stroke with `Theme.chromeHairline`) to build custom brutalist frames.

## 2. Spacing & Grid Rhythm

All components must align to a strict 4-pixel spacing grid. Use the spacing tokens defined in `Theme`:
* `space1 = 4pt`: Micro paddings, icon margins.
* `space2 = 8pt`: Standard item-spacing within lists/grids.
* `space3 = 12pt`: Core padding inside table/list rows and side bars.
* `space4 = 16pt`: Layout margin gaps, container spacing.
* `space5 = 24pt`: Generous margin padding for dashboard views/settings sections.

## 3. Micro-Interactions & Animation

* **Buttons**: Use `BrutalistButtonStyle` to provide high-end, responsive hover (`Theme.chromeHover`) and press (`Theme.chromeActive`) feedback.
* **Transitions**: Use `Theme.chromeTransition` (`easeInOut(duration: 0.2)`) for panel collapses, tab switching, and detail view expansions. Use `.transition(.opacity)` for dynamic forms inside settings.
* **Glassmorphism**: Window/terminal background opacity is fixed at `Theme.glassOpacity` (`0.72`) to maintain a consistent unified glass aesthetic.

## 4. Color Hierarchy

Colors are dynamically computed from `selectedTerminalTheme` inside `Theme.Resolved`:
* **Active Status**: `Theme.activityRunning` (cool blue), `Theme.activityAttention` (warm amber), `Theme.activityFailure` (warm red).
* **Git Actions**: `Theme.gitInsertion` (green), `Theme.gitDeletion` (red).
* **Typography**:
  - `Theme.chromeForeground`: Primary headings, editable fields.
  - `Theme.chromeMuted`: Sub-labels, inactive states.
  - `Theme.chromeFaint`: Placeholder text, help blocks.

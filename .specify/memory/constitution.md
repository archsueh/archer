# Archer Constitution

## Core Principles

### I. Brutalist-Minimal Design
All UI corners must be strictly configured to 0px (`rounded.brutalist`). Soft drop shadows are banned. Layout grids must align to multiples of 4 (space1 to space5). All colors must be resolved dynamically from the active terminal theme via `Theme.resolved`; hardcoding hex values in Swift UI views is strictly prohibited.

### II. HUD Vibrancy & Transparency
The app backing uses native `NSVisualEffectView` HUD vibrancy with translucent panels. Background opacity for these translucent panels is fixed at `Theme.glassOpacity` (`0.72`) to maintain spatial consistency.

### III. Restrained Motion
Transitions and animation speeds must strictly conform to `Theme.chromeTransition` (`easeInOut(duration: 0.2)`). Keyboard-initiated actions (such as opening the command palette via ⌘P) must NEVER animate to keep the interface responsive and instantaneous.

### IV. Annotated Diff Discipline
All upstream modifications to SwiftUI defaults or external integrations must be clearly annotated with the `// [archer]` comment. This isolates Archer's custom styling from standard system components, making diff tracking clean.

### V. Mono & Sans-Serif Typographic Order
The typographic system uses exactly two fonts: `Onest` (for sans-serif display text, labels, and settings) and `JetBrains Mono` (for terminal contents, terminal logs, and `[bracket-button]` interactive controls).

### VI. Project Independence
Archer must maintain absolute project independence. In the future, this project will diverge significantly from Kooky (or Sailor). Avoid referencing, copying, or aligning design patterns back to Kooky unless explicitly instructed. All new features, sidebars, command palettes, and visual chrome designs must build on Archer's own identity as a premium developer cockpit, emphasizing distinctive, high-end visual design and motion dynamics.


## Architecture & Modularity
- SwiftUI views and themes must be separated into modular subfolders under the `ArcherKit` target.
- UI elements must sit on flat grid layers with zero elevation shadows. Borders are rendered as 1pt hairline strokes using the `.bracketBorder()` modifier.

## Verification & Quality Gates
- Swift Compilation: Code must compile cleanly with zero errors.
- Visual Alignment: Spacers and margins must be audited to ensure they align to the 4pt grid system.
- Easing check: All animations must utilize `Theme.chromeTransition` or be completely instant (for keyboard actions).

## Governance
- This constitution is the visual and code quality source of truth for the Archer project.
- Any change to the layout rules, colors, or typography requires updating the `DESIGN.md` and this constitution.

**Version**: 1.0.0 | **Ratified**: 2026-06-19 | **Last Amended**: 2026-06-19

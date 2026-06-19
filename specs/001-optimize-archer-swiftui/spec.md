# Feature Specification: Optimize Archer SwiftUI View Animations, Transitions, Hover, and Active States

**Feature Branch**: `001-optimize-archer-swiftui`

**Created**: 2026-06-19

**Status**: Draft

**Input**: User description: "Optimize Archer SwiftUI view animations, transitions, hover states, and active states"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Instant Keyboard Interactions (Priority: P1)
As a developer, when I trigger keyboard-initiated panels like the Command Palette (⌘P) or dismiss them (Escape), the panel must open or close instantly without any transition lag.
**Why this priority**: Keyboard operations are executed hundreds of times daily. Any delay makes the app feel sluggish and disconnected from key presses.
**Independent Test**: Press `⌘P` in the app, confirm the search pill pops open instantaneously. Press `Escape`, confirm it vanishes instantly without any fade or scaling lags.

**Acceptance Scenarios**:
1. **Given** the app is active, **When** the user presses `⌘P`, **Then** the Command Palette panel opens immediately with zero transition delay.
2. **Given** the Command Palette is visible, **When** the user presses `Escape`, **Then** the panel is dismissed instantly with no transition duration.

---

### User Story 2 - Consistent Brutalist View Transitions (Priority: P1)
As a user, when I toggle UI sidebars or change views, the transition must be smooth and use the unified transition timing of `Theme.chromeTransition`.
**Why this priority**: Prevents jarring layout shifts while ensuring that visual transitions feel unified and high-craft across different parts of the application.
**Independent Test**: Click the sidebar toggle icon in the top strip, confirm the sidebar panel slides out smoothly using the `easeInOut(duration: 0.2)` transition.

**Acceptance Scenarios**:
1. **Given** the sidebar is open, **When** the user toggles it shut, **Then** the panel collapses smoothly utilizing `Theme.chromeTransition` without stutter.

---

### User Story 3 - Tactile Button Press Feedback (Priority: P2)
As a user, when I hover or tap on interactive controls like `BracketButton` or Settings, I must get instant visual feedback confirming my interaction.
**Why this priority**: Visual cues for hover and active state (click feedback) make the interface tactile, responsive, and alive.
**Independent Test**: Hover over a `[bracket-button]`, confirm its background changes to `Theme.chromeHover`. Click it, confirm its scale slightly shrinks to `0.97` or `0.98` and background deepens.

**Acceptance Scenarios**:
1. **Given** a bracket button is rendered, **When** the mouse hovers over it, **Then** its background highlights using `Theme.chromeHover`.
2. **Given** the mouse clicks down on the button, **When** it is pressed, **Then** it scales down to `0.97` and overlays `Theme.chromeActive`.

---

## Edge Cases

- **Rapid Multiple Triggers**: What happens when the user clicks a button or toggles panels repeatedly?
  - Easing transitions must be interruptible (Springs or short linear easings) and must not accumulate lag.
- **System Reduced Motion Active**: How does the system handle SwiftUI animations when macOS `prefers-reduced-motion` is enabled?
  - Transitions must disable spatial movement (sliding) and fall back to a simple, immediate visibility change or gentle fade.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST configure all SwiftUI transitions for UI state changes (such as sidebar toggle) to use `Theme.chromeTransition`.
- **FR-002**: System MUST bypass animations for keyboard-initiated window operations (including the Command Palette open/close).
- **FR-003**: Custom buttons (like `BracketButton` or `HoverableIconButton`) MUST implement active press shrink feedback (e.g. `.scaleEffect(isPressed ? 0.98 : 1)`).
- **FR-004**: Custom buttons MUST implement hover state feedback using `.onHover` mapping to `Theme.chromeHover`.
- **FR-005**: All spacer bounds, paddings, and margin gaps MUST strictly adhere to the multiples of 4 spacing grid (`space1` to `space5`).

### Key Entities

- **Theme**: Unified design token source containing `glassOpacity`, spacing, color scheme, and the `chromeTransition` definition.
- **BracketButton**: A text-based `[button]` view inheriting the brutalist border and active/hover states.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Command Palette opens/closes in `<16ms` (instantaneous frame target) upon keyboard input.
- **SC-002**: Sidebars slide-open transition matches exactly `0.2s` with `easeInOut` curve.
- **SC-003**: 100% of custom interactive buttons expose explicit `:active` state changes (shrink/press styling).

## Assumptions

- We assume Swift 5.9+ and SwiftUI for macOS 14+ are the baseline targets for the project.
- macOS system appearance features (like dark mode and prefers-color-scheme) are automatically captured by SwiftUI's environment context.

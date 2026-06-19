# Implementation Plan: Optimize Archer SwiftUI View Animations, Transitions, Hover, and Active States

**Branch**: `001-optimize-archer-swiftui` | **Date**: 2026-06-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-optimize-archer-swiftui/spec.md`

## Summary

We will optimize the SwiftUI motion, active states, and hover states in Archer. We will align transitions to `Theme.chromeTransition`, remove animations from keyboard-triggered views, enforce hover states to use dynamic tokens, and add button-press shrink feedback.

## Technical Context

- **Language/Version**: Swift 5.9+ / macOS 14+
- **Primary Dependencies**: SwiftUI, AppKit
- **Testing**: Manual UI verification and compilation check
- **Target Platform**: macOS 14+
- **Project Type**: Native macOS app (SwiftUI/AppKit hybrid)
- **Performance Goals**: 60 FPS transitions, <16ms response time for keyboard action dismissal
- **Constraints**: No default soft drop shadows, cornerRadius must be 0 (except where native controls require minor rounding).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*
- Core Principle I: Corner radius configured to 0px. Spacers multiples of 4. (Pass)
- Core Principle II: HUD transparency Unified at `Theme.glassOpacity = 0.72`. (Pass)
- Core Principle III: Restrained Motion. Keyboard-initiated actions have no animations. (Pass)

## Files to Modify

```text
Sources/ArcherKit/
├── App/
│   ├── Theme.swift               # Implement scale/active easing parameters
│   └── CommandPalette.swift      # Verify instantaneous keyboard-triggered pop open/dismiss
├── Sidebar/
│   └── HoverableIconButton.swift # Replace hardcoded white opacity hover color with Theme.chromeHover, add active scale effect
```

## Detailed Proposed Changes

### 1. Unified Active Click Scale Easing (`Sources/ArcherKit/App/Theme.swift`)
- Check `BrutalistButtonStyle` in `Theme.swift`.
- Modify `BrutalistButtonStyle` to add scale shrink effect on press:
  ```swift
  struct BrutalistButtonStyle: ButtonStyle {
      func makeBody(configuration: Configuration) -> some View {
          configuration.label
              .background(configuration.isPressed ? Theme.chromeActive : Color.clear)
              .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
              .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
              .contentShape(Rectangle())
      }
  }
  ```

### 2. Hover Token Clean & Shrink Feedback (`Sources/ArcherKit/Sidebar/HoverableIconButton.swift`)
- Modify hover background to use `Theme.chromeHover` instead of `Color.white.opacity(0.12)`.
- Replace `.buttonStyle(.plain)` with a custom scale-feedback button style:
  ```swift
  struct BrutalistIconButtonStyle: ButtonStyle {
      func makeBody(configuration: Configuration) -> some View {
          configuration.label
              .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
              .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
      }
  }
  ```
  And apply it as `.buttonStyle(BrutalistIconButtonStyle())`.

### 3. Keyboard Action Verification (`Sources/ArcherKit/App/CommandPalette.swift`)
- Review `CommandPalette.swift` logic to ensure `dismiss()` and `show()` perform instant visual toggle without SwiftUI animation wrapper overrides.

---

## Verification Plan

1. **Compilation Check**: Run compilation check to ensure clean build.
2. **Hover Verification**: Inspect `HoverableIconButton` instances in the sidebar to ensure hover highlight matches `Theme.chromeHover`.
3. **Active State Verification**: Hold down click on a `BracketButton` and `HoverableIconButton`, confirm they shrink slightly (`0.98` and `0.96` scale factor respectively) and return to normal scale when released.
4. **Instantaneous Keyboard Panel Toggle**: Press ⌘P to verify instant display. Press Escape to verify instant removal.

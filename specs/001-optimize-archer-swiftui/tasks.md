---
description: "Task list for optimizing Archer SwiftUI view animations and transitions"
---

# Tasks: Optimize Archer SwiftUI View Animations, Transitions, Hover, and Active States

**Input**: Design documents from `specs/001-optimize-archer-swiftui/`

**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic verification

- [ ] T001 Verify `spec.md` and `plan.md` are aligned and that no syntax errors exist.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Verify the current layout and theme files compile before starting modifications

- [ ] T002 Verify that `Sources/ArcherKit/App/Theme.swift` compiles cleanly before making edits.

---

## Phase 3: User Story 1 - Instant Keyboard Interactions (Priority: P1)

**Goal**: Command Palette window open/close acts instantly without animations

- [ ] T003 Verify `Sources/ArcherKit/App/CommandPalette.swift` uses `makeKeyAndOrderFront` and `orderOut` directly without animation wraps.

---

## Phase 4: User Story 2 - Consistent Brutalist View Transitions (Priority: P1)

**Goal**: Sidebar panels slide-open transitions match Theme.chromeTransition

- [ ] T004 Audit and ensure all sidebar and panel toggle transitions in `Sources/ArcherKit/App/ContentView.swift` use `.animation(Theme.chromeTransition)` where transitions are declared.

---

## Phase 5: User Story 3 - Tactile Button Press Feedback (Priority: P2)

**Goal**: Custom buttons highlight on hover and shrink slightly when pressed

- [ ] T005 [P] [US3] Modify `BrutalistButtonStyle` in `Sources/ArcherKit/App/Theme.swift` to add `.scaleEffect(configuration.isPressed ? 0.98 : 1.0)` and `.animation(.easeOut(duration: 0.1), value: configuration.isPressed)`.
- [ ] T006 [P] [US3] Modify `HoverableIconButton` in `Sources/ArcherKit/Sidebar/HoverableIconButton.swift` to replace `Color.white.opacity(0.12)` with `Theme.chromeHover`, add `BrutalistIconButtonStyle` with scale shrink effect, and apply it.

---

## Phase 6: Verification

**Purpose**: Confirm all requirements are satisfied

- [ ] T007 Run build/compilation check to ensure no Swift compilation errors.
- [ ] T008 Manually run the application to verify button hover highlighting, button click shrink animation, and instant ⌘P keyboard panel actions.

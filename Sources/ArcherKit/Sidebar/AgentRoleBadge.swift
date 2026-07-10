// AgentRoleBadge.swift
// Tiny UI signal for a fable-advisor-style architect/implementer split
// (github.com/DannyMac180/fable-advisor). Purely informational — Archer
// never coerces routing; the badge just reminds the user which lane an
// agent occupies so they can compose cheap-typing + expensive-judgment runs.

import SwiftUI

// [archer] removed empty `enum AgentRoleBadge {}` placeholder — it
// collided with the `struct AgentRoleBadge: View` below (Swift forbids
// two declarations of the same name). The struct is the real one.

extension AgentRole {
    var label: String {
        switch self {
        case .architect: return "architect"
        case .implementer: return "implementer"
        case .general: return "agent"
        }
    }

    @MainActor // [archer] Theme.chromeMuted is main-actor-isolated
    var tint: Color {
        switch self {
        case .architect: return Color(red: 0.85, green: 0.69, blue: 0.40) // warm judgment
        case .implementer: return Color(red: 0.48, green: 0.62, blue: 1.0) // cool typing
        case .general: return Theme.chromeMuted
        }
    }

    /// One-line doctrine hint shown in launch sheets.
    var doctrine: String {
        switch self {
        case .architect: return "贵模型·判断/规格/审查,只发少量 token"
        case .implementer: return "便宜模型·按 spec 打字实现,发大量 token"
        case .general: return "通用 agent"
        }
    }
}

struct AgentRoleBadge: View {
    let role: AgentRole

    var body: some View {
        Text(role.label)
            .font(Theme.mono(8, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(role.tint.opacity(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(role.tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(role.tint.opacity(0.3), lineWidth: 0.5))
    }
}

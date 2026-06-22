import SwiftUI

/// Which screens the edge glow paints on.
enum EdgeGlowScope: String, CaseIterable {
    case allScreens
    case currentScreen
}

/// Color tone for the screen-edge activity glow. Bound to the activity tokens
/// only — no new hues, no rainbow (see docs/edge-glow-spec.md non-goals).
enum EdgeGlowTone: Equatable {
    case running, attention, failure

    @MainActor
    var color: Color {
        switch self {
        case .running: return Theme.activityRunning
        case .attention: return Theme.activityAttention
        case .failure: return Theme.activityFailure
        }
    }
}

/// Visual state of the edge glow.
enum EdgeGlowState: Equatable {
    case idle
    /// Brief flash that auto-clears — a finished turn.
    case pulse(EdgeGlowTone)
    /// Stays lit until the user focuses archer — attention / failure.
    case hold(EdgeGlowTone)
    /// PR2: sustained marquee while an agent is running.
    case running

    var tone: EdgeGlowTone? {
        switch self {
        case .idle: return nil
        case let .pulse(t), let .hold(t): return t
        case .running: return .running
        }
    }

    /// Hold states linger until archer gains focus; pulse / running do not.
    var lingers: Bool {
        if case .hold = self { return true }
        return false
    }

    /// Higher wins when signals compete: failure > attention > running > pulse.
    var priority: Int {
        switch self {
        case .idle: return 0
        case .pulse: return 1
        case .running: return 2
        case let .hold(t): return t == .failure ? 4 : 3
        }
    }
}

/// Pure mapping from a notification kind to the glow it produces. Called from
/// AppDelegate's alert dispatch alongside the chime — no side effects here.
enum EdgeGlow {
    static func state(for kind: SessionAlertKind) -> EdgeGlowState {
        switch kind {
        case .completed: return .pulse(.running)
        case .attention: return .hold(.attention)
        case .failure: return .hold(.failure)
        }
    }
}

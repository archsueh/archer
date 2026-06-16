import Foundation

/// One rate-limit window. `utilization` is 0.0–1.0+ (1.0 = 100%, can exceed).
struct RateLimit: Equatable, Sendable {
    let utilization: Double
    let resetsAt: Date
    var percent: Int { Int((utilization * 100).rounded()) }
}

/// Claude usage: rolling 5-hour and weekly windows (+ Sonnet weekly).
struct ServiceUsage: Equatable, Sendable {
    let fiveHour: RateLimit?
    let weekly: RateLimit?
    let weeklySonnet: RateLimit?
}

/// Errors surfaced by the Claude usage pipeline. Trimmed from TokenChecker's
/// DomainError to the Claude path, plain-English (no localization dependency).
enum UsageError: Error, Equatable, LocalizedError, Sendable {
    case keychainTokenMissing
    case anthropicUnauthorized
    case anthropicRateLimited(retryAfter: TimeInterval?)
    case anthropicHTTP(status: Int)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .keychainTokenMissing:
            return "No Claude token in Keychain — run `claude login`."
        case .anthropicUnauthorized:
            return "Anthropic 401 — re-login with `claude login`."
        case .anthropicRateLimited(let retryAfter):
            if let sec = retryAfter { return "Rate limited — retry in ~\(max(1, Int(sec / 60)))m." }
            return "Rate limited (429)."
        case .anthropicHTTP(let status):
            return "Anthropic API error (\(status))."
        case .decoding(let detail):
            return "Decode failed: \(detail)"
        case .network(let detail):
            return "Network error: \(detail)"
        }
    }
}

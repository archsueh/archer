import Foundation

/// [archer] P2: resizable panel widths. Pure model — clamp + defaults + Codable
/// for persistence. UI drag handle lives in PanelResizer; persistence in Persistence.
public enum PanelKind: String, Codable, Sendable, CaseIterable {
    case sidebar
    case rightPanel
}

public struct PanelWidths: Codable, Sendable, Equatable {
    public var sidebar: Double
    public var rightPanel: Double

    public init(sidebar: Double = 220, rightPanel: Double = 280) {
        self.sidebar = sidebar
        self.rightPanel = rightPanel
    }

    public static let sidebarRange: ClosedRange<Double> = 160 ... 420
    public static let rightRange: ClosedRange<Double> = 220 ... 560

    public static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    public mutating func resize(_ kind: PanelKind, to value: Double) {
        switch kind {
        case .sidebar: sidebar = Self.clamp(value, to: Self.sidebarRange)
        case .rightPanel: rightPanel = Self.clamp(value, to: Self.rightRange)
        }
    }
}

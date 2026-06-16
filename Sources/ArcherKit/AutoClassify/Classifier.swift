import Foundation

public struct ClassifyRule: Hashable, Sendable {
    public let `extension`: String
    public let folder: String
    public let priority: Int

    public init(extension: String, folder: String, priority: Int) {
        self.`extension` = `extension`.lowercased()
        self.folder = folder
        self.priority = priority
    }
}

public struct ClassifyResult: Sendable, Hashable {
    public let source: URL
    public let destination: URL
    public let rule: ClassifyRule?

    public init(source: URL, destination: URL, rule: ClassifyRule?) {
        self.source = source
        self.destination = destination
        self.rule = rule
    }
}

public enum Classifier {
    private static let builtInRules: [ClassifyRule] = [
        ClassifyRule(extension: "swift", folder: "Sources", priority: 1),
        ClassifyRule(extension: "m", folder: "Sources", priority: 1),
        ClassifyRule(extension: "png", folder: "Assets", priority: 1),
        ClassifyRule(extension: "jpg", folder: "Assets", priority: 1),
        ClassifyRule(extension: "heic", folder: "Assets", priority: 1),
        ClassifyRule(extension: "md", folder: "Docs", priority: 1),
        ClassifyRule(extension: "pdf", folder: "Docs", priority: 1),
        ClassifyRule(extension: "json", folder: "Config", priority: 1),
        ClassifyRule(extension: "yaml", folder: "Config", priority: 1),
    ]

    public static func suggestMove(for fileURL: URL, baseDir: URL) -> ClassifyResult? {
        guard let fileExtension = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension.lowercased() else {
            return nil
        }

        let matchingRules = builtInRules.filter { $0.extension == fileExtension }
        guard let bestRule = matchingRules.min(by: { $0.priority < $1.priority }) else {
            return nil
        }

        let destination = baseDir.appendingPathComponent(bestRule.folder).appendingPathComponent(fileURL.lastPathComponent)
        return ClassifyResult(source: fileURL, destination: destination, rule: bestRule)
    }
}

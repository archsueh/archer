import Foundation

public struct ClassifyRule: Hashable, Sendable, Codable, Identifiable {
    public var id: String {
        `extension`
    }

    public let `extension`: String
    public let folder: String
    public let priority: Int

    public init(extension: String, folder: String, priority: Int) {
        self.extension = `extension`.lowercased()
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

    public static func loadRules() -> [ClassifyRule] {
        guard let parsed = ArcherSettings.loadParsed(),
              let classify = parsed["classify"] as? [[String: Any]]
        else {
            return builtInRules
        }
        var rules: [ClassifyRule] = []
        for dict in classify {
            if let ext = dict["extension"] as? String,
               let folder = dict["folder"] as? String,
               let priority = dict["priority"] as? Int
            {
                rules.append(ClassifyRule(extension: ext, folder: folder, priority: priority))
            }
        }
        return rules.isEmpty ? builtInRules : rules
    }

    public static func saveRules(_ rules: [ClassifyRule]) {
        var parsed = ArcherSettings.loadParsed() ?? [:]
        let rawRules = rules.map { rule -> [String: Any] in
            return [
                "extension": rule.extension,
                "folder": rule.folder,
                "priority": rule.priority,
            ]
        }
        parsed["classify"] = rawRules
        if let data = try? JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted]) {
            try? data.write(to: ArcherSettings.url)
        }
    }

    public static func suggestMove(for fileURL: URL, baseDir: URL) -> ClassifyResult? {
        guard let fileExtension = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension.lowercased() else {
            return nil
        }

        let rules = loadRules()
        let matchingRules = rules.filter { $0.extension == fileExtension }
        guard let bestRule = matchingRules.min(by: { $0.priority < $1.priority }) else {
            return nil
        }

        let destination = baseDir.appendingPathComponent(bestRule.folder).appendingPathComponent(fileURL.lastPathComponent)
        return ClassifyResult(source: fileURL, destination: destination, rule: bestRule)
    }
}

import Foundation
import SwiftUI

@Observable
@MainActor
final class UpdatesStore: ObservableObject {
    private(set) var snippets: [RecentUpdateSnippet] = []

    func loadUpdates(for workspacePath: String) async {
        let trimmed = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            snippets = []
            return
        }

        do {
            let result = try await runGitDiffNameStatus(rootPath: trimmed)
            snippets = result.map { status, path in
                RecentUpdateSnippet(status: status, path: path)
            }
        } catch {
            snippets = []
        }
    }

    private func runGitDiffNameStatus(rootPath: String) async throws -> [(status: Character, path: String)] {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["git", "-C", rootPath, "diff", "--name-status", "HEAD~1"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            task.terminationHandler = { process in
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: NSError(domain: "git", code: Int(process.terminationStatus)))
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let parsed = output
                        .split(separator: "\n")
                        .compactMap { line -> (status: Character, path: String)? in
                            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedLine.isEmpty else { return nil }
                            let parts = trimmedLine.split(separator: "\t", maxSplits: 1)
                            guard let statusString = parts.first, let first = statusString.first else { return nil }
                            let path = parts.count > 1 ? String(parts[1]) : ""
                            return (status: first, path: path)
                        }
                    continuation.resume(returning: parsed)
                }
            }
            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct RecentUpdateSnippet: Identifiable {
    let id = UUID()
    let status: Character
    let path: String
    var title: String {
        switch status {
        case "A": return "Added"
        case "M": return "Modified"
        case "D": return "Deleted"
        case "R": return "Renamed"
        case "C": return "Copied"
        default: return String(status)
        }
    }
}

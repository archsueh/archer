// MemoryDedup.swift
// mem0-inspired dedup / conflict-resolution — offline, no LLM.
//
// Before a user creates a new memo from the Memory Bank "+" button, this
// module checks the candidate against existing memories using deterministic,
// rule-based rules (no model call, no network). It NEVER deletes or rewrites
// files — it only returns ranked suggestions so the human curator decides.
// This preserves Archer's "human high-signal curation over auto full-capture"
// memory philosophy.

import Foundation

/// A proposed new memory, supplied by the UI before it is written to disk.
struct MemoCandidate {
    let title: String
    let tags: Set<String>
    let links: Set<String>
    let body: String
}

/// What the dedup logic recommends for a candidate-vs-existing match.
enum DedupVerdict: Hashable {
    /// Title already exists — do not create a duplicate.
    case discard
    /// Near-identical (tag/link signature or high body overlap) — merge instead.
    case merge
    /// Only weakly related — keep, but surface a human-confirmation warning.
    case keep
}

/// One match between a candidate and an existing memory.
struct DedupMatch: Identifiable, Hashable {
    let id: String // existingTitle
    let existingTitle: String
    let score: Double // 0...1
    let reason: String
    let verdict: DedupVerdict
}

/// Deterministic, offline dedup check over a `MemoryGraph`.
struct MemoryDedup {
    let graph: MemoryGraph
    let bodyThreshold: Double

    init(graph: MemoryGraph, bodyThreshold: Double = 0.85) {
        self.graph = graph
        self.bodyThreshold = bodyThreshold
    }

    // MARK: - Public

    /// Check `candidate` against all existing memories.
    /// Returns matches sorted by score descending. Empty array = no conflict.
    func check(_ candidate: MemoCandidate) -> [DedupMatch] {
        let normTitle = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var matches: [DedupMatch] = []

        for (title, node) in graph.nodes {
            // 1. Exact title match (case-insensitive, trimmed) -> discard.
            if title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normTitle {
                matches.append(DedupMatch(
                    id: title, existingTitle: title, score: 1.0,
                    reason: "标题已存在", verdict: .discard
                ))
                continue
            }

            // 2. Identical tag + link signature -> merge.
            if node.tags == candidate.tags, node.links == candidate.links, !candidate.tags.isEmpty {
                matches.append(DedupMatch(
                    id: title, existingTitle: title, score: 0.9,
                    reason: "标签与链接完全一致", verdict: .merge
                ))
                continue
            }

            // 3. Body Jaccard similarity.
            let jaccard = bodyJaccard(candidateBody: candidate.body, existingURL: node.id)
            if jaccard >= bodyThreshold {
                matches.append(DedupMatch(
                    id: title, existingTitle: title, score: jaccard,
                    reason: "正文高度相似", verdict: .merge
                ))
            } else if jaccard >= 0.6 {
                matches.append(DedupMatch(
                    id: title, existingTitle: title, score: jaccard,
                    reason: "正文部分相似，请人工确认", verdict: .keep
                ))
            }
        }

        return matches.sorted { $0.score > $1.score }
    }

    // MARK: - Body similarity (Jaccard over content words)

    /// Jaccard similarity between `candidateBody` and the file at `existingURL`.
    private func bodyJaccard(candidateBody: String, existingURL: URL) -> Double {
        let a = contentWords(candidateBody)
        let b = contentWords(of: existingURL)
        let union = a.union(b)
        guard !union.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }

    /// Lowercased content words (length >= 3, stopwords removed).
    private func contentWords(_ text: String) -> Set<String> {
        let stripped = text.replacingOccurrences(
            of: #"[#*_`\[\]()]"#, with: " ", options: .regularExpression
        )
        return Set(stripped.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 3 && !DedupStopwords.contains($0) })
    }

    /// Read a note body from disk and extract content words.
    private func contentWords(of url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return contentWords(text)
    }
}

/// Minimal English/Chinese-safe stopword set for token-overlap scoring.
private let DedupStopwords: Set<String> = [
    "the", "and", "for", "with", "this", "that", "from", "into", "your", "will",
    "have", "are", "was", "but", "not", "you", "our", "can", "all", "any", "out",
    "use", "using", "via", "when", "what", "how", "who", "which", "their", "they",
    "them", "has", "had", "been", "were", "does", "did", "than", "then", "now",
]

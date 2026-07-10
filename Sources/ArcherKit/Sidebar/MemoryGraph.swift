// MemoryGraph.swift
// Local, dependency-free memory network inspired by A-mem (agiresearch/A-mem):
// atomic markdown notes + automatic [[wikilink]] / #tag network, ranked by
// connection centrality. No LLM, no SQLite, no external services. The graph
// is read-only over disk; link proposals are surfaced for manual curation
// (the user decides what to connect) — this matches Archer's "human
// high-signal curation over auto full-capture" memory philosophy.

import Foundation

/// One memory note (a single `.md` file) in the Archer memory store.
struct MemoNode: Identifiable, Equatable, Hashable {
    /// File URL — stable identity across renames of the note body.
    let id: URL
    /// Note title (filename without extension), also the wikilink key.
    let title: String
    /// `#tag` values (without the leading `#`).
    let tags: Set<String>
    /// Outgoing `[[target]]` links, resolved to canonical titles.
    let links: Set<String>
    /// Incoming links: titles whose body links to this note.
    var backlinks: Set<String> = []

    /// Total degree = out + in. Central hubs surface first.
    var degree: Int {
        links.count + backlinks.count
    }
}

/// Pure model: scan a directory of markdown notes, build the link/tag graph,
/// and expose centrality ranking, tag clusters, orphans, and link suggestions.
/// All parsing is deterministic and side-effect free except the initial disk read.
struct MemoryGraph {
    private(set) var nodes: [String: MemoNode] = [:]
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        build()
    }

    /// Re-scan the directory and rebuild the graph (call when files change).
    mutating func build() {
        nodes.removeAll()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        let mdURLs = urls.filter { $0.pathExtension.lowercased() == "md" }

        // Pass 1: parse each note's tags and outgoing links.
        for url in mdURLs {
            let title = url.deletingPathExtension().lastPathComponent
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let (tags, links) = Self.parse(text)
            nodes[title] = MemoNode(id: url, title: title, tags: tags, links: links)
        }

        // Pass 2: resolve backlinks (only when the target note exists).
        for (title, node) in nodes {
            for link in node.links where nodes[link] != nil {
                nodes[link]?.backlinks.insert(title)
            }
        }
    }

    // MARK: - Parsing

    /// Extract `#tag` and `[[wikilink]]` (supports `[[Target|alias]]`) from text.
    /// Fenced and inline code spans are stripped first so literals like
    /// `#tag` / `[[x]]` inside code are not treated as tags/links.
    static func parse(_ text: String) -> (tags: Set<String>, links: Set<String>) {
        // Drop fenced ```...``` blocks, then inline `...` spans.
        let noFences = text.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        let cleaned = noFences.replacingOccurrences(of: #"`[^`\n]*?`"#, with: " ", options: .regularExpression)

        var tags = Set<String>()
        var links = Set<String>()

        let linkRegex = try! NSRegularExpression(pattern: #"\[\[([^\]\|]+)(?:\|[^\]]+)?\]\]"#)
        let tagRegex = try! NSRegularExpression(pattern: #"(?:^|\s)#([\p{L}\p{N}_/-]+)"#)
        let ns = cleaned as NSString

        for m in linkRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty { links.insert(raw) }
        }
        for m in tagRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty { tags.insert(raw) }
        }
        return (tags, links)
    }

    // MARK: - Queries

    /// Nodes ranked by connection centrality (degree desc), then title.
    /// Central ("hub") memories float to the top — the A-mem idea of a
    /// self-organizing memory network surfacing what matters.
    var ranked: [MemoNode] {
        nodes.values.sorted {
            if $0.degree != $1.degree { return $0.degree > $1.degree }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Tag -> member nodes, sorted by tag name then title.
    var tagClusters: [(tag: String, nodes: [MemoNode])] {
        var map: [String: [MemoNode]] = [:]
        for n in nodes.values {
            for t in n.tags {
                map[t, default: []].append(n)
            }
        }
        return map
            .map { (tag: $0.key, nodes: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    /// Notes with no links and no backlinks — prime candidates to connect.
    var orphans: [MemoNode] {
        nodes.values.filter { $0.links.isEmpty && $0.backlinks.isEmpty }
            .sorted { $0.title < $1.title }
    }

    /// Suggest unlinked notes for `title` via token-overlap (Jaccard) over
    /// body words + tags. Returns up to `limit` target titles. Never writes
    /// to disk — the user copies `[[target]]` and decides.
    func suggestedLinks(for title: String, limit: Int = 5) -> [String] {
        guard let src = nodes[title] else { return [] }
        let srcWords = words(of: src.id).union(src.tags)
        var scored: [(String, Double)] = []
        for (t, dst) in nodes where t != title && !src.links.contains(t) {
            let dstWords = words(of: dst.id).union(dst.tags)
            let union = srcWords.union(dstWords)
            guard !union.isEmpty else { continue }
            let j = Double(srcWords.intersection(dstWords).count) / Double(union.count)
            if j > 0.05 { scored.append((t, j)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    // MARK: - Private

    /// Lowercased content words (length >= 3, stopwords removed) for similarity.
    private func words(of url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let stripped = text.replacingOccurrences(of: #"[#*_`\[\]()]"#, with: " ", options: .regularExpression)
        return Set(stripped.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 3 && !MemoNodeStopwords.contains($0) })
    }
}

/// Minimal English/Chinese-safe stopword set for token-overlap scoring.
private let MemoNodeStopwords: Set<String> = [
    "the", "and", "for", "with", "this", "that", "from", "into", "your", "will",
    "have", "are", "was", "but", "not", "you", "our", "can", "all", "any", "out",
    "use", "using", "via", "when", "what", "how", "who", "which", "their", "they",
    "them", "has", "had", "been", "were", "does", "did", "than", "then", "now",
]

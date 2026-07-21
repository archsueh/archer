// MemoryEntityGraph.swift
// mem0-inspired graph memory — offline, no LLM.
//
// Like mem0's graph-memory layer, this turns atomic markdown notes into a
// typed entity-relation graph: notes ("memo" entities) and their #tags
// ("tag" entities) are nodes, and three deterministic relation kinds connect
// them:
//   • linksTo   — a memo's `[[wikilink]]` points at another memo (directed)
//   • sharesTag — a memo bears a #tag (bidirectional memo <-> tag edge)
//   • similar   — two memos share body vocabulary (Jaccard over content words)
//
// Everything is derived locally from `MemoryGraph` with pure Foundation APIs
// (FileManager / NSString / NSRegularExpression). There is no model call, no
// network, and no persistence — the graph is built in memory from disk state.

import Foundation

/// A node in the memory entity graph: either a memo (note) or a tag.
struct MemoryEntity: Identifiable, Hashable {
    let id: String
    let kind: MemoryEntityKind
    /// Relations originating from this entity. `degree` counts these.
    var relations: [MemoryRelation]
    /// Connectivity of this entity (outgoing relations).
    var degree: Int {
        relations.count
    }
}

/// What kind of node an entity is.
enum MemoryEntityKind: String, Codable, Hashable {
    case memo
    case tag
}

/// A typed, weighted edge between two entities.
struct MemoryRelation: Identifiable, Hashable {
    /// Stable id: `"<from>-><to>:<kind>"`.
    let id: String
    let from: String
    let to: String
    let kind: MemoryRelationKind
    let weight: Double

    init(from: String, to: String, kind: MemoryRelationKind, weight: Double) {
        self.from = from
        self.to = to
        self.kind = kind
        self.weight = weight
        id = "\(from)->\(to):\(kind.rawValue)"
    }
}

/// The kind of relationship an edge encodes.
enum MemoryRelationKind: String, Codable, Hashable {
    case linksTo
    case sharesTag
    case similar
}

/// A deterministic, offline entity-relation graph derived from a `MemoryGraph`.
///
/// Entities are memo titles plus `#tag` values; edges are derived from existing
/// structure (wikilinks, tag membership, and content-word Jaccard similarity).
/// No LLM, no network, no SQLite — pure Foundation.
struct MemoryEntityGraph {
    /// All entities keyed by id (memo id == title, tag id == `"tag:<name>"`).
    private(set) var entities: [String: MemoryEntity]
    /// Minimum Jaccard score required to add a `similar` edge.
    let threshold: Double

    // MARK: - Construction

    /// Build the entity graph from an already-built `MemoryGraph`.
    /// - Parameter similarThreshold: Jaccard cutoff for `similar` edges (default 0.1).
    init(graph: MemoryGraph, similarThreshold: Double = 0.1) {
        threshold = similarThreshold

        var built: [String: MemoryEntity] = [:]

        // 1. Memo entities (one per note, identified by title).
        for title in graph.nodes.keys {
            built[title] = MemoryEntity(id: title, kind: .memo, relations: [])
        }

        // 2. Tag entities. Namespaced as `tag:<name>` so a tag that happens to
        //    share a name with a memo title cannot collide in the entity map.
        var tagNames = Set<String>()
        for node in graph.nodes.values {
            tagNames.formUnion(node.tags)
        }
        for tag in tagNames {
            let tid = Self.tagEntityID(tag)
            built[tid] = MemoryEntity(id: tid, kind: .tag, relations: [])
        }

        // 3. Relations, deduped by relation id.
        var rels: [String: [MemoryRelation]] = [:]
        func add(_ r: MemoryRelation) {
            if let existing = rels[r.from], existing.contains(where: { $0.id == r.id }) { return }
            rels[r.from, default: []].append(r)
        }

        // linksTo: memo -> memo (directed), weight 1.0. Only when the target
        // note actually exists and isn't a self-link.
        for (title, node) in graph.nodes {
            for link in node.links where link != title && graph.nodes[link] != nil {
                add(MemoryRelation(from: title, to: link, kind: .linksTo, weight: 1.0))
            }
        }

        // sharesTag: memo <-> tag (bidirectional), weight 1.0. This gives tag
        // nodes degree and makes them first-class participants in the graph.
        // ("Two memos share a tag" is realized transitively through the tag node.)
        for (title, node) in graph.nodes {
            for tag in node.tags {
                let tid = Self.tagEntityID(tag)
                add(MemoryRelation(from: title, to: tid, kind: .sharesTag, weight: 1.0))
                add(MemoryRelation(from: tid, to: title, kind: .sharesTag, weight: 1.0))
            }
        }

        // similar: memo <-> memo via body-word Jaccard, only above the threshold.
        let titles = graph.nodes.keys.sorted()
        for i in 0 ..< titles.count {
            for j in (i + 1) ..< titles.count {
                guard let a = graph.nodes[titles[i]], let b = graph.nodes[titles[j]] else { continue }
                let wa = Self.contentWords(of: a.id)
                let wb = Self.contentWords(of: b.id)
                let union = wa.union(wb)
                guard !union.isEmpty else { continue }
                let jaccard = Double(wa.intersection(wb).count) / Double(union.count)
                if jaccard > threshold {
                    add(MemoryRelation(from: a.title, to: b.title, kind: .similar, weight: jaccard))
                    add(MemoryRelation(from: b.title, to: a.title, kind: .similar, weight: jaccard))
                }
            }
        }

        for (id, list) in rels {
            built[id]?.relations = list
        }

        entities = built
    }

    // MARK: - Queries

    /// Relations originating from `id` (empty if the entity is unknown).
    func neighbors(of id: String) -> [MemoryRelation] {
        entities[id]?.relations ?? []
    }

    /// Entities ranked by degree (descending), then by id (ascending).
    func rankedEntities(limit: Int? = nil) -> [MemoryEntity] {
        let sorted = entities.values.sorted {
            if $0.degree != $1.degree { return $0.degree > $1.degree }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        if let limit { return Array(sorted.prefix(limit)) }
        return Array(sorted)
    }

    /// All relations across the graph, sorted by weight (descending).
    /// `minWeight` filters out edges below the given weight.
    func relations(limit: Int? = nil, minWeight: Double = 0) -> [MemoryRelation] {
        let all = entities.values.flatMap { $0.relations }
            .filter { $0.weight >= minWeight }
            .sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        if let limit { return Array(all.prefix(limit)) }
        return all
    }

    // MARK: - Helpers

    /// Entity id for a tag (namespaced to avoid clashes with memo titles).
    static func tagEntityID(_ tag: String) -> String {
        "tag:\(tag)"
    }

    /// Lowercased content words (length >= 3, stopwords removed) for similarity.
    /// Reads the note body directly from its file URL — the same idea as
    /// `MemoryGraph.words(of:)`, reimplemented here so this type stays
    /// independent of that private method.
    private static func contentWords(of url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let stripped = text.replacingOccurrences(
            of: #"[#*_`\[\]()]"#, with: " ", options: .regularExpression
        )
        return Set(stripped.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 3 && !EntityGraphStopwords.contains($0) })
    }
}

/// Minimal English/Chinese-safe stopword set for token-overlap scoring.
private let EntityGraphStopwords: Set<String> = [
    "the", "and", "for", "with", "this", "that", "from", "into", "your", "will",
    "have", "are", "was", "but", "not", "you", "our", "can", "all", "any", "out",
    "use", "using", "via", "when", "what", "how", "who", "which", "their", "they",
    "them", "has", "had", "been", "were", "does", "did", "than", "then", "now",
]

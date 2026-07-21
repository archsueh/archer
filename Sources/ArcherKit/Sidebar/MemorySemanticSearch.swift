// MemorySemanticSearch.swift
// mem0-inspired semantic retrieval，local-first，graceful degrade
//
// Optional opt-in embedding-based semantic search for the Archer memory store.
// Local-first by design: embeddings are only used when the user flips the
// opt-in switch AND a local Ollama instance is reachable. Otherwise we degrade
// gracefully to lexical Jaccard overlap over memo bodies — never blocking the
// UI, never surfacing network errors to callers. No SQLite, no external cloud,
// no LLM. Pure Foundation.

import Foundation

/// Abstraction over an embedding backend. The default (and only networked)
/// implementation is `OllamaEmbeddingProvider`; tests supply deterministic
/// in-memory mocks. `available` is a synchronous reachability probe so callers
/// can branch without awaiting or catching network failures.
protocol EmbeddingProvider {
    /// Synchronous reachability check (no throwing). `false` must be returned
    /// on any failure (timeout, unreachable host, bad status) — never throw.
    var available: Bool { get }
    /// Embed a batch of texts into `[[Float]]`. Throws only on genuine,
    /// unexpected transport/parse errors; callers are expected to swallow
    /// these and fall back (see `MemorySemanticIndex`).
    func embed(_ texts: [String]) throws -> [[Float]]
}

/// Local Ollama embedding backend. This is the ONLY type in the module that
/// touches the network. All network access is guarded by `available`, which
/// uses a short (3s) timeout and never throws — so a missing/unreachable
/// Ollama simply degrades the feature rather than breaking the app.
struct OllamaEmbeddingProvider: EmbeddingProvider {
    let baseURL: URL
    let model: String

    var available: Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { sem.signal() }
            guard error == nil, let http = response as? HTTPURLResponse else { return }
            ok = (200 ..< 300).contains(http.statusCode)
        }
        task.resume()
        // Wait slightly longer than the request timeout so we always return.
        _ = sem.wait(timeout: .now() + 3.2)
        return ok
    }

    init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = "nomic-embed-text"
    ) {
        self.baseURL = baseURL
        self.model = model
    }

    func embed(_ texts: [String]) throws -> [[Float]] {
        var result: [[Float]] = []
        result.reserveCapacity(texts.count)
        for text in texts {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/embeddings"))
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["model": model, "prompt": text]
            )

            let (data, response) = try perform(request)
            guard
                let http = response as? HTTPURLResponse,
                (200 ..< 300).contains(http.statusCode)
            else {
                throw NSError(
                    domain: "OllamaEmbeddingProvider", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Ollama embeddings returned a non-2xx status"]
                )
            }
            guard
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let embedding = obj["embedding"] as? [NSNumber]
            else {
                throw NSError(
                    domain: "OllamaEmbeddingProvider", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Ollama embeddings payload missing 'embedding'"]
                )
            }
            result.append(embedding.map { $0.floatValue })
        }
        return result
    }

    // MARK: - Private

    private func perform(_ request: URLRequest) throws -> (Data, URLResponse) {
        var data: Data?
        var response: URLResponse?
        var error: Error?
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { d, r, e in
            data = d
            response = r
            error = e
            sem.signal()
        }
        task.resume()
        sem.wait()
        if let error { throw error }
        guard let d = data, let r = response else {
            throw NSError(
                domain: "OllamaEmbeddingProvider", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Ollama request produced no data"]
            )
        }
        return (d, r)
    }
}

/// A memo matched by a search, with its relevance score.
struct ScoredMemo: Identifiable, Hashable {
    let title: String
    let score: Double
    /// `Identifiable` conformance — title is the stable wikilink key.
    var id: String {
        title
    }
}

/// Semantic (embedding) search index over a `MemoryGraph`.
///
/// - When the provider is reachable and a cache has been built, `search`
///   ranks memos by cosine similarity of embeddings.
/// - Otherwise it degrades to lexical Jaccard overlap over memo bodies.
///
/// The embedding cache is persisted to `<directory>/.memsem.json`, keyed by
/// title + file mtime so unchanged memos are never re-embedded. All cache
/// read/write failures are swallowed (never surfaced to the UI).
struct MemorySemanticIndex {
    let directory: URL
    let provider: EmbeddingProvider

    /// Cached embeddings, keyed by memo title.
    private var embeddings: [String: [Float]] = [:]
    /// File modification times captured when `embeddings` was built.
    private var mtimes: [String: Double] = [:]
    /// Whether the on-disk cache has been loaded into this instance yet.
    private var cacheLoaded = false

    private var cacheURL: URL {
        directory.appendingPathComponent(".memsem.json")
    }

    init(directory: URL, provider: EmbeddingProvider) {
        self.directory = directory
        self.provider = provider
    }

    // MARK: - Refresh (build / load cache)

    /// Build or refresh the embedding cache. If the provider is unreachable,
    /// this returns immediately without throwing. Any embedding or cache IO
    /// error is swallowed — the feature simply stays at its current state.
    mutating func refresh(graph: MemoryGraph) throws {
        guard provider.available else { return }

        loadCache()

        var pendingTitles: [String] = []
        var pendingTexts: [String] = []
        for (title, node) in graph.nodes {
            let mtime = mtimeOf(node.id) ?? 0
            if let existing = embeddings[title], mtimes[title] == mtime, !existing.isEmpty {
                continue // unchanged — reuse cached embedding
            }
            pendingTitles.append(title)
            pendingTexts.append(textOf(node.id))
        }

        if !pendingTitles.isEmpty {
            // Swallow embedding failures: keep whatever we already have rather
            // than throwing a network error up to the caller.
            guard let newEmbeddings = try? provider.embed(pendingTexts) else { return }
            for (i, title) in pendingTitles.enumerated() {
                embeddings[title] = newEmbeddings[i]
                mtimes[title] = graph.nodes[title].map { mtimeOf($0.id) } ?? 0
            }
        }

        // Prune entries for memos that no longer exist in the graph.
        for title in Array(embeddings.keys) where graph.nodes[title] == nil {
            embeddings[title] = nil
            mtimes[title] = nil
        }

        saveCache()
    }

    // MARK: - Search

    /// Rank memos for `query`, returning up to `limit` results.
    ///
    /// Uses cosine similarity over cached embeddings when the provider is
    /// available and a cache exists; otherwise gracefully degrades to lexical
    /// Jaccard overlap. Never throws.
    func search(_ query: String, limit: Int, graph: MemoryGraph) -> [ScoredMemo] {
        let lim = max(0, limit)
        guard lim > 0 else { return [] }

        // Vector path: provider reachable + cache already built.
        if provider.available,
           let queryEmbedding = try? provider.embed([query]).first,
           !embeddings.isEmpty
        {
            var scored: [(String, Double)] = []
            scored.reserveCapacity(embeddings.count)
            for (title, embedding) in embeddings {
                scored.append((title, cosine(queryEmbedding, embedding)))
            }
            scored.sort { $0.1 > $1.1 }
            return scored.prefix(lim).map { ScoredMemo(title: $0.0, score: $0.1) }
        }

        // Graceful degrade: lexical Jaccard over memo bodies.
        let queryWords = tokenize(query)
        var scored: [(String, Double)] = []
        for (title, node) in graph.nodes {
            let words = tokenize(textOf(node.id))
            let union = queryWords.union(words)
            guard !union.isEmpty else { continue }
            let jaccard = Double(queryWords.intersection(words).count) / Double(union.count)
            scored.append((title, jaccard))
        }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(lim).map { ScoredMemo(title: $0.0, score: $0.1) }
    }

    // MARK: - Private helpers

    /// Cosine similarity of two equal-length float vectors. Returns 0 for
    /// mismatched lengths or zero vectors.
    private func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0 ..< a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return Double(dot / (sqrt(na) * sqrt(nb)))
    }

    /// Lightweight lexical tokenizer mirroring `MemoryGraph.words`: lowercase,
    /// strip markdown punctuation, drop short tokens and stopwords.
    private func tokenize(_ text: String) -> Set<String> {
        let stripped = text.replacingOccurrences(
            of: #"[#*_`\[\]()]"#, with: " ", options: .regularExpression
        )
        return Set(
            stripped.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count >= 3 && !MemSemStopwords.contains($0) }
        )
    }

    private func textOf(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func mtimeOf(_ url: URL) -> Double? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970
    }

    // MARK: - Cache (de)serialization — failures swallowed

    private struct CacheBlob: Codable {
        var embeddings: [String: [Float]]
        var mtimes: [String: Double]
    }

    private mutating func loadCache() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        guard let blob = try? JSONDecoder().decode(CacheBlob.self, from: data) else { return }
        embeddings = blob.embeddings
        mtimes = blob.mtimes
    }

    private func saveCache() {
        let blob = CacheBlob(embeddings: embeddings, mtimes: mtimes)
        guard let data = try? JSONEncoder().encode(blob) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

/// Minimal English/Chinese-safe stopword set for lexical token-overlap scoring.
private let MemSemStopwords: Set<String> = [
    "the", "and", "for", "with", "this", "that", "from", "into", "your", "will",
    "have", "are", "was", "but", "not", "you", "our", "can", "all", "any", "out",
    "use", "using", "via", "when", "what", "how", "who", "which", "their", "they",
    "them", "has", "had", "been", "were", "does", "did", "than", "then", "now",
]

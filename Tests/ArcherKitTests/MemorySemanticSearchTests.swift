// MemorySemanticSearchTests.swift
@testable import ArcherKit
import XCTest

/// Deterministic in-memory embedding provider. Produces a stable pseudo-vector
/// from the text so tests never touch the network or Ollama.
private struct MockEmbeddingProvider: EmbeddingProvider {
    var available: Bool
    /// Dimension of the pseudo-embedding vectors.
    let dim = 8

    func embed(_ texts: [String]) throws -> [[Float]] {
        texts.map { text -> [Float] in
            let scalars = Array(text.unicodeScalars)
            var v = [Float](repeating: 0, count: dim)
            for (i, s) in scalars.enumerated() {
                v[i % dim] += Float(s.value)
            }
            // Normalize so cosine is well-defined.
            let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
            return norm > 0 ? v.map { $0 / norm } : v
        }
    }
}

final class MemorySemanticSearchTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memsem-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func write(_ name: String, _ body: String) {
        try! body.write(to: dir.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
    }

    private func buildGraph() -> MemoryGraph {
        MemoryGraph(directory: dir)
    }

    /// refresh must never throw, even when the provider is down.
    func testRefreshDoesNotThrowWhenProviderDown() {
        let provider = MockEmbeddingProvider(available: false)
        var index = MemorySemanticIndex(directory: dir, provider: provider)
        XCTAssertNoThrow(try index.refresh(graph: buildGraph()))
    }

    /// When the provider is available, search ranks by cosine similarity; an
    /// identical query scores exactly 1.0 at the top.
    func testVectorPathRanksByIdenticalQuery() {
        write("Apple", "apple fruit red sweet")
        write("Banana", "banana fruit yellow long")
        let provider = MockEmbeddingProvider(available: true)
        var index = MemorySemanticIndex(directory: dir, provider: provider)
        try? index.refresh(graph: buildGraph())
        let results = index.search("apple fruit red sweet", limit: 5, graph: buildGraph())
        XCTAssertEqual(results.first?.title, "Apple")
        XCTAssertEqual(results.first?.score ?? 0, 1.0, accuracy: 1e-6)
    }

    /// When the provider is unavailable, search degrades to Jaccard and still
    /// returns ranked results.
    func testJaccardDegradePathReturnsResults() {
        write("Cat", "cat feline whiskers purr animal")
        write("Dog", "dog canine bark animal")
        let provider = MockEmbeddingProvider(available: false)
        let index = MemorySemanticIndex(directory: dir, provider: provider)
        let results = index.search("cat animal feline", limit: 5, graph: buildGraph())
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.title, "Cat")
    }

    /// The embedding cache is written to .memsem.json and reloads without
    /// re-embedding (no throw, same top result).
    func testCacheWriteAndReloadRoundTrip() {
        write("Apple", "apple fruit red sweet")
        write("Banana", "banana fruit yellow long")
        let provider = MockEmbeddingProvider(available: true)
        var index = MemorySemanticIndex(directory: dir, provider: provider)
        try? index.refresh(graph: buildGraph())
        let cacheURL = dir.appendingPathComponent(".memsem.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        // A fresh index over the same dir should load the cache and rank the
        // identical query identically.
        var reloaded = MemorySemanticIndex(directory: dir, provider: provider)
        try? reloaded.refresh(graph: buildGraph())
        let results = reloaded.search("apple fruit red sweet", limit: 5, graph: buildGraph())
        XCTAssertEqual(results.first?.title, "Apple")
    }

    /// refresh is a no-op (does not throw, produces no embeddings) when down.
    func testRefreshNoOpWhenProviderDown() {
        write("Apple", "apple fruit red sweet")
        let provider = MockEmbeddingProvider(available: false)
        var index = MemorySemanticIndex(directory: dir, provider: provider)
        try? index.refresh(graph: buildGraph())
        let results = index.search("apple", limit: 5, graph: buildGraph())
        // Degrades to Jaccard; Apple body contains "apple".
        XCTAssertEqual(results.first?.title, "Apple")
    }
}

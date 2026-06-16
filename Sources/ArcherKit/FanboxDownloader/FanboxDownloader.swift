import Foundation

// [archer] Fanbox response JSON models
private struct FanboxResponse: Decodable {
    struct Body: Decodable {
        let title: String
        let type: String
        let body: InnerBody?
    }
    struct InnerBody: Decodable {
        let text: String?
        let images: [FanboxImage]?
        let files: [FanboxFile]?
        let imageMap: [String: FanboxImage]?
        let fileMap: [String: FanboxFile]?
    }
    struct FanboxImage: Decodable {
        let id: String?
        let `extension`: String?
        let originalUrl: String
    }
    struct FanboxFile: Decodable {
        let id: String?
        let name: String
        let `extension`: String?
        let url: String
    }
    let body: Body?
}

public struct FanboxPost: Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let files: [URL]
    public let downloadedAt: Date
}

@MainActor
public enum Downloader {
    public static func download(
        postIds: [String],
        to directory: URL
    ) async throws -> [FanboxPost] {
        let baseURL = directory.appendingPathComponent("fanbox", conformingTo: .directory)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)

        var results: [FanboxPost] = []

        for postId in postIds {
            let postDirectory = baseURL.appendingPathComponent(postId, conformingTo: .directory)
            try fileManager.createDirectory(at: postDirectory, withIntermediateDirectories: true)

            var downloadedFiles: [URL] = []
            var postTitle = "Post \(postId)"

            do {
                // Fetch post metadata from public API endpoint
                let apiURL = URL(string: "https://api.fanbox.cc/post.info?postId=\(postId)")!
                var request = URLRequest(url: apiURL)
                request.setValue("https://www.fanbox.cc", forHTTPHeaderField: "Origin")
                request.setValue("https://www.fanbox.cc/", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw NSError(domain: "Downloader", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
                }

                let decoder = JSONDecoder()
                let decodedResponse = try decoder.decode(FanboxResponse.self, from: data)
                
                if let body = decodedResponse.body {
                    postTitle = body.title
                    
                    var filesToDownload: [(url: URL, name: String)] = []
                    
                    if let innerBody = body.body {
                        // 1. Files
                        if let files = innerBody.files {
                            for file in files {
                                if let url = URL(string: file.url) {
                                    filesToDownload.append((url: url, name: file.name))
                                }
                            }
                        }
                        // 2. Images
                        if let images = innerBody.images {
                            for img in images {
                                if let url = URL(string: img.originalUrl) {
                                    filesToDownload.append((url: url, name: url.lastPathComponent))
                                }
                            }
                        }
                        // 3. FileMap (articles)
                        if let fileMap = innerBody.fileMap {
                            for file in fileMap.values {
                                if let url = URL(string: file.url) {
                                    filesToDownload.append((url: url, name: file.name))
                                }
                            }
                        }
                        // 4. ImageMap (articles)
                        if let imageMap = innerBody.imageMap {
                            for img in imageMap.values {
                                if let url = URL(string: img.originalUrl) {
                                    filesToDownload.append((url: url, name: url.lastPathComponent))
                                }
                            }
                        }
                        
                        // Save post text if present
                        if let text = innerBody.text, !text.isEmpty {
                            let textURL = postDirectory.appendingPathComponent("post_text.md")
                            try text.write(to: textURL, atomically: true, encoding: .utf8)
                            
                            // Auto Classification hook for text description
                            if let classification = Classifier.suggestMove(for: textURL, baseDir: directory) {
                                let destDir = classification.destination.deletingLastPathComponent()
                                try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
                                if fileManager.fileExists(atPath: classification.destination.path) {
                                    try fileManager.removeItem(at: classification.destination)
                                }
                                try fileManager.moveItem(at: textURL, to: classification.destination)
                                downloadedFiles.append(classification.destination)
                            } else {
                                downloadedFiles.append(textURL)
                            }
                        }
                    }
                    
                    // Download all gathered files/images
                    for item in filesToDownload {
                        let tempDest = postDirectory.appendingPathComponent(item.name)
                        do {
                            try await downloadFile(from: item.url, to: tempDest)
                            
                            // Auto Classification hook!
                            if let classification = Classifier.suggestMove(for: tempDest, baseDir: directory) {
                                let destDir = classification.destination.deletingLastPathComponent()
                                try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
                                if fileManager.fileExists(atPath: classification.destination.path) {
                                    try fileManager.removeItem(at: classification.destination)
                                }
                                try fileManager.moveItem(at: tempDest, to: classification.destination)
                                downloadedFiles.append(classification.destination)
                            } else {
                                downloadedFiles.append(tempDest)
                            }
                        } catch {
                            NSLog("[archer] Failed to download \(item.url): \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                NSLog("[archer] Metadata fetch failed for postId \(postId), using fallback placeholder: \(error.localizedDescription)")
            }

            // Fallback if no files downloaded (e.g. network failure or text-only post without files)
            if downloadedFiles.isEmpty {
                let sampleURL = postDirectory.appendingPathComponent("\(postId).txt")
                try "placeholder: \(postId)".write(to: sampleURL, atomically: true, encoding: .utf8)
                
                // Auto Classification hook for fallback file
                if let classification = Classifier.suggestMove(for: sampleURL, baseDir: directory) {
                    let destDir = classification.destination.deletingLastPathComponent()
                    try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
                    if fileManager.fileExists(atPath: classification.destination.path) {
                        try fileManager.removeItem(at: classification.destination)
                    }
                    try fileManager.moveItem(at: sampleURL, to: classification.destination)
                    downloadedFiles.append(classification.destination)
                } else {
                    downloadedFiles.append(sampleURL)
                }
            }

            let post = FanboxPost(
                id: postId,
                title: postTitle,
                files: downloadedFiles,
                downloadedAt: Date()
            )
            results.append(post)
        }

        return results
    }

    private static func downloadFile(from url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("https://www.fanbox.cc", forHTTPHeaderField: "Origin")
        request.setValue("https://www.fanbox.cc/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "Downloader",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "Download failed with status \((response as? HTTPURLResponse)?.statusCode ?? -1)"]
            )
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
    }
}

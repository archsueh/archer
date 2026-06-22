import SwiftUI

// MARK: - TokenRank lightweight model

struct LeaderboardResponse: Decodable {
    var status: Int?
    var board: String
    var range: String
    var entries: [RankEntry]

    struct RankEntry: Decodable, Identifiable, Equatable {
        var id: String {
            userID
        }

        var rank: Int
        var userID: String
        var name: String
        var avatar: String?
        var score: Int
        var cost: Double
        var byTool: [String: Int]

        enum CodingKeys: String, CodingKey {
            case rank
            case userID = "userId"
            case name
            case avatar
            case score
            case cost
            case byTool
        }
    }
}

enum RankTab: String, CaseIterable, Identifiable {
    case usage = "用量"
    case rank = "烧 Token 榜"

    var id: String {
        rawValue
    }
}

@MainActor
final class TokenRankViewModel: ObservableObject {
    @Published var entries: [LeaderboardResponse.RankEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdated: Date?

    private var task: Task<Void, Never>?

    func load() {
        task?.cancel()
        isLoading = true
        error = nil

        task = Task { [weak self] in
            do {
                var components = URLComponents(
                    url: URL(string: "https://scys.com/tokenrank/api/subapp/leaderboard")!,
                    resolvingAgainstBaseURL: false
                )
                components?.queryItems = [
                    .init(name: "board", value: "total"),
                    .init(name: "range", value: "today"),
                ]
                guard let url = components?.url else { throw URLError(.badURL) }

                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let decoded = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
                guard decoded.status ?? 0 == 0 else { throw NSError(domain: "tokenrank", code: 1, userInfo: [NSLocalizedDescriptionKey: "榜单返回异常"]) }

                self?.entries = decoded.entries
                self?.lastUpdated = Date()
            } catch {
                self?.error = (error as NSError).localizedDescription
            }
            self?.isLoading = false
        }
    }

    deinit { task?.cancel() }
}

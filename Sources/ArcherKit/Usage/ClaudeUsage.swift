import CFNetwork
import Foundation

/// Reads the Claude Code OAuth access token from the macOS Keychain via
/// `security find-generic-password`. Lifted from TokenChecker.
struct KeychainTokenSource: Sendable {
    static let serviceName = "Claude Code-credentials"

    func readAccessToken() async throws -> String {
        let username = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-a", username, "-s", Self.serviceName, "-w"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in cont.resume() }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: UsageError.keychainTokenMissing)
                }
            }
        } catch {
            throw UsageError.keychainTokenMissing
        }
        guard process.terminationStatus == 0 else { throw UsageError.keychainTokenMissing }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let payload: KeychainPayload
        do {
            payload = try JSONDecoder().decode(KeychainPayload.self, from: data)
        } catch {
            throw UsageError.decoding("Keychain payload: \(error.localizedDescription)")
        }
        guard let token = payload.claudeAiOauth?.accessToken, !token.isEmpty else {
            throw UsageError.keychainTokenMissing
        }
        return token
    }
}

private struct KeychainPayload: Decodable {
    let claudeAiOauth: OAuth?
    struct OAuth: Decodable { let accessToken: String? }
}

/// Hits Anthropic's OAuth usage endpoint. Routes through a detected local proxy
/// and blocks redirects so the Bearer token can't leak. Lifted from TokenChecker.
struct AnthropicUsageAPIClient: Sendable {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch(accessToken: String) async throws -> AnthropicUsageDTO {
        let proxyPort = await ProxyDetector.detectProxyPort()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        if let port = proxyPort {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: "127.0.0.1",
                kCFNetworkProxiesHTTPPort: port, kCFNetworkProxiesHTTPSEnable: 1,
                kCFNetworkProxiesHTTPSProxy: "127.0.0.1", kCFNetworkProxiesHTTPSPort: port,
            ]
        }
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw UsageError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("Invalid response") }

        switch http.statusCode {
        case 200: break
        case 401: throw UsageError.anthropicUnauthorized
        case 429:
            let retry = (http.value(forHTTPHeaderField: "Retry-After")
                ?? http.value(forHTTPHeaderField: "retry-after")).flatMap(TimeInterval.init)
            throw UsageError.anthropicRateLimited(retryAfter: retry)
        default: throw UsageError.anthropicHTTP(status: http.statusCode)
        }
        do { return try JSONDecoder().decode(AnthropicUsageDTO.self, from: data) }
        catch { throw UsageError.decoding("Anthropic usage: \(error.localizedDescription)") }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()
    func urlSession(_ s: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection r: HTTPURLResponse, newRequest: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct AnthropicUsageDTO: Decodable, Sendable {
    let fiveHour: BucketDTO?
    let sevenDay: BucketDTO?
    let sevenDaySonnet: BucketDTO?
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour", sevenDay = "seven_day", sevenDaySonnet = "seven_day_sonnet"
    }
    struct BucketDTO: Decodable, Sendable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }
    }
}

extension AnthropicUsageDTO.BucketDTO {
    func toRateLimit() -> RateLimit? {
        guard let utilization, let resetsAt,
              let date = ISO8601DateFormatter.usageStandard.date(from: resetsAt)
                ?? ISO8601DateFormatter.usageFractional.date(from: resetsAt) else { return nil }
        return RateLimit(utilization: utilization / 100.0, resetsAt: date)
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let usageStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated(unsafe) static let usageFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
}

/// Keychain token → Anthropic usage endpoint → ServiceUsage.
struct ClaudeUsageProvider: Sendable {
    let keychain = KeychainTokenSource()
    let api = AnthropicUsageAPIClient()

    func fetch() async throws -> ServiceUsage {
        let token = try await keychain.readAccessToken()
        let dto = try await api.fetch(accessToken: token)
        return ServiceUsage(
            fiveHour: dto.fiveHour?.toRateLimit(),
            weekly: dto.sevenDay?.toRateLimit(),
            weeklySonnet: dto.sevenDaySonnet?.toRateLimit())
    }
}

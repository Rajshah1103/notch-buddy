import Foundation

public struct GitHubClient {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(token: String) async throws -> GitHubSnapshot {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("NotchHub", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": ResponseParser.query])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .timedOut, .cannotFindHost,
                                             .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed].contains(error.code) {
            throw GitHubError.offline
        }
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 401: throw GitHubError.unauthorized
            case 403, 429: throw GitHubError.rateLimited
            case 200..<300: break
            default: throw GitHubError.failed("GitHub returned \(http.statusCode)")
            }
        }
        return try ResponseParser.parse(data)
    }
}

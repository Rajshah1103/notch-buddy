import Foundation

public struct JenkinsClient: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        // Fail fast: when the VPN is off the request should give up in seconds, not minutes.
        self.session = session ?? {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }()
    }

    public func fetch(_ config: JenkinsConfig) async throws -> JenkinsSnapshot {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("api/json"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "tree", value: ResponseParser.treeQuery)]
        guard let url = components?.url else { throw JenkinsError.failed("Invalid address") }

        var request = URLRequest(url: url)
        let credentials = Data("\(config.username):\(config.token)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw JenkinsError.unreachable
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .secureConnectionFailed:
                throw JenkinsError.failed("The server's certificate isn't trusted by this Mac")
            default: throw JenkinsError.failed(error.localizedDescription)
            }
        }
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 401, 403: throw JenkinsError.unauthorized
            case 404: throw JenkinsError.notJenkins
            case 200..<300: break
            default: throw JenkinsError.failed("Jenkins returned \(http.statusCode)")
            }
        }
        return try ResponseParser.parse(data, filters: config.filters)
    }
}

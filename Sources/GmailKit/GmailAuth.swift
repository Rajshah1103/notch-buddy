import CryptoKit
import Foundation
import Network

/// Google sign-in for a desktop app: the system browser opens Google's page, and Google sends the
/// result to a short-lived server on this Mac (127.0.0.1), protected by PKCE.
public enum GmailAuth {
    public static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    public struct Tokens: Equatable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresAt: Date
    }

    // MARK: - PKCE

    public static func makeVerifier() -> String {
        base64URL(Data((0..<48).map { _ in UInt8.random(in: 0...255) }))
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func authorizationURL(clientID: String, redirect: String, challenge: String, state: String) -> URL {
        var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        parts.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
        ]
        return parts.url!
    }

    // MARK: - The whole flow

    /// Opens the browser (through `open`), waits for Google to answer, and trades the code for tokens.
    public static func signIn(clientID: String, clientSecret: String, open: @escaping @Sendable (URL) -> Void,
                              session: URLSession = .shared) async throws -> Tokens {
        let receiver = try LoopbackReceiver()
        let port = try await receiver.start()
        let redirect = "http://127.0.0.1:\(port)"
        let verifier = makeVerifier()
        let state = makeVerifier()
        open(authorizationURL(clientID: clientID, redirect: redirect, challenge: challenge(for: verifier), state: state))

        let answer = try await receiver.receive(timeout: 180)
        guard answer["state"] == state else { throw GmailError.failed("Sign-in answer did not match") }
        if let error = answer["error"] { throw GmailError.failed(error == "access_denied" ? "Sign-in was cancelled" : error) }
        guard let code = answer["code"] else { throw GmailError.failed("Google sent no code") }
        return try await token(form: ["code": code, "client_id": clientID, "client_secret": clientSecret,
                                      "redirect_uri": redirect, "grant_type": "authorization_code",
                                      "code_verifier": verifier], session: session)
    }

    public static func refresh(clientID: String, clientSecret: String, refreshToken: String,
                               session: URLSession = .shared) async throws -> Tokens {
        try await token(form: ["client_id": clientID, "client_secret": clientSecret,
                               "refresh_token": refreshToken, "grant_type": "refresh_token"], session: session)
    }

    private static func token(form: [String: String], session: URLSession) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch let error as URLError {
            throw error.code == .cancelled ? error : GmailError.offline
        }
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            if object["error"] as? String == "invalid_grant" { throw GmailError.signedOut }
            throw GmailError.failed((object["error_description"] as? String) ?? (object["error"] as? String) ?? "Google refused the sign-in")
        }
        guard let access = object["access_token"] as? String else { throw GmailError.failed("Google sent no token") }
        let lifetime = (object["expires_in"] as? Double) ?? 3600
        return Tokens(accessToken: access, refreshToken: object["refresh_token"] as? String,
                      expiresAt: Date().addingTimeInterval(lifetime - 60))
    }
}

/// Listens on 127.0.0.1 for the one request Google's redirect makes, answers it with a "you can close
/// this tab" page, and hands back the query parameters.
final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "notchhub.gmail.loopback")
    private var waiter: CheckedContinuation<[String: String], Error>?
    private var early: Result<[String: String], Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            // Handlers run on `queue`, one at a time, so a plain flag object is safe to share.
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            listener.stateUpdateHandler = { [listener] state in
                guard !once.done else { return }
                switch state {
                case .ready: once.done = true; continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): once.done = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    func receive(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let early = self.early { continuation.resume(with: early); self.early = nil; return }
                self.waiter = continuation
            }
            queue.asyncAfter(deadline: .now() + timeout) { self.finish(.failure(GmailError.failed("Sign-in timed out"))) }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { connection.cancel(); return }
            let params = Self.parameters(inRequest: request)
            let page = "<html><body style=\"font-family:-apple-system;text-align:center;margin-top:20vh\"><h2>Notch Hub is connected to Gmail</h2><p>You can close this tab.</p></body></html>"
            let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
            connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if params.isEmpty { return }       // a favicon request or similar, not the redirect
            self.finish(.success(params))
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        if let waiter { waiter.resume(with: result); self.waiter = nil; listener.cancel() }
        else if early == nil { early = result }
    }

    /// The query of the request line `GET /?code=…&state=… HTTP/1.1`.
    static func parameters(inRequest request: String) -> [String: String] {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return [:] }
        let pieces = line.split(separator: " ")
        guard pieces.count >= 2, let query = URLComponents(string: String(pieces[1]))?.queryItems else { return [:] }
        return Dictionary(query.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { $1 })
    }
}

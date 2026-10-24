import AppKit
import GmailKit
import SwiftUI

@MainActor
final class GmailModel: ObservableObject {
    enum State: Equatable {
        case loading
        case needsSetup                  // no Google Cloud client saved yet
        case needsSignIn(note: String?)  // client saved, not signed in (or the sign-in lapsed)
        case signingIn                   // the browser is open
        case ready
    }

    @Published private(set) var state = State.loading
    /// The last good read; kept while a refresh fails so the panel never goes blank.
    @Published private(set) var snapshot: GmailSnapshot?
    @Published private(set) var error: GmailError?

    /// What was typed into the setup fields. Kept here, not in the view: the notch closes whenever you
    /// click away (to copy the next value from Google's page), and the view's own state goes with it.
    @Published var draftClientID = ""
    @Published var draftSecret = ""

    private let client = GmailClient()
    private var credentials: GmailCredentials?
    private var access: (token: String, expires: Date)?
    private var timer: Timer?
    private var lastFetch = Date.distantPast
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        Task {
            // The Keychain can be slow (or ask permission), so never read it on the main thread.
            credentials = await Task.detached { GmailCredentials.load() }.value
            guard running else { return }
            evaluate()
        }
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        snapshot = nil; error = nil; state = .loading
    }

    func refresh() {
        guard running, state == .ready, Date().timeIntervalSince(lastFetch) > 30 else { return }
        Task { await fetch() }
    }

    private func evaluate() {
        guard let credentials else { state = .needsSetup; return }
        guard credentials.refreshToken != nil else { state = .needsSignIn(note: nil); return }
        state = .ready
        Task { await fetch() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.state == .ready { Task { await self?.fetch() } } }
        }
    }

    // MARK: - Connecting

    /// Accepts the JSON file Google offers to download for a client (`{"installed":{"client_id":…,"client_secret":…}}`),
    /// so one paste fills both fields. Returns false when the text is not that.
    @discardableResult
    func absorb(pasted text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = (root["installed"] ?? root["web"] ?? root) as? [String: Any],
              let id = inner["client_id"] as? String else { return false }
        draftClientID = id
        if let secret = inner["client_secret"] as? String { draftSecret = secret }
        return true
    }

    func saveClient(id: String, secret: String) {
        let saved = GmailCredentials(clientID: id.trimmingCharacters(in: .whitespacesAndNewlines),
                                     clientSecret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
        credentials = saved
        draftClientID = ""; draftSecret = ""
        Task.detached { saved.save() }
        signIn()
    }

    func signIn() {
        guard var current = credentials else { return }
        state = .signingIn
        Task {
            do {
                let tokens = try await GmailAuth.signIn(clientID: current.clientID, clientSecret: current.clientSecret,
                                                        open: { url in DispatchQueue.main.async { NSWorkspace.shared.open(url) } })
                guard let refresh = tokens.refreshToken else { throw GmailError.failed("Google did not allow offline access") }
                access = (tokens.accessToken, tokens.expiresAt)
                current.refreshToken = refresh
                current.email = try await client.email(accessToken: tokens.accessToken)
                credentials = current
                let toSave = current
                Task.detached { toSave.save() }
                evaluate()
            } catch {
                state = .needsSignIn(note: (error as? GmailError)?.message ?? error.localizedDescription)
            }
        }
    }

    func disconnect() {
        timer?.invalidate(); timer = nil
        credentials = nil; access = nil; snapshot = nil; error = nil
        Task.detached { GmailCredentials.clear() }
        state = .needsSetup
    }

    // MARK: - Reading

    private func validToken() async throws -> String {
        if let access, access.expires > Date() { return access.token }
        guard let credentials, let refresh = credentials.refreshToken else { throw GmailError.signedOut }
        let tokens = try await GmailAuth.refresh(clientID: credentials.clientID, clientSecret: credentials.clientSecret, refreshToken: refresh)
        access = (tokens.accessToken, tokens.expiresAt)
        return tokens.accessToken
    }

    private func fetch() async {
        do {
            let token = try await validToken()
            let new = try await client.snapshot(email: credentials?.email ?? "", accessToken: token)
            lastFetch = Date()
            snapshot = new; error = nil
        } catch GmailError.signedOut {
            // Revoked, or a testing-mode login that has run out (they last a week): ask again.
            credentials?.refreshToken = nil
            if let credentials { Task.detached { credentials.save() } }
            access = nil; snapshot = nil; timer?.invalidate(); timer = nil
            state = .needsSignIn(note: "Your Gmail sign-in expired. Sign in again.")
        } catch let failure as GmailError {
            error = failure
        } catch {
            self.error = .offline
        }
    }

    /// For the snapshot tool.
    func loadForPreview(_ snapshot: GmailSnapshot?, state: State) {
        self.snapshot = snapshot
        self.state = state
    }
}

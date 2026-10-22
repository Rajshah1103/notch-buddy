import Foundation

/// Polls GitHub in the background. A minute is plenty for pull requests, and it keeps well inside
/// the API's limits; opening the notch asks for a fresher read when the last one is old.
// All mutable state is touched only on `queue`, which is what makes sharing the object safe.
public final class GitHubMonitor: @unchecked Sendable {
    public enum State: Equatable {
        case idle
        case needsToken
        case ready(GitHubSnapshot, source: GitHubToken.Source)
        case failed(GitHubError)
    }

    public var onChange: ((State) -> Void)?
    public var allowCommandLine = true

    private let client = GitHubClient()
    private let queue = DispatchQueue(label: "notchhub.github", qos: .utility)
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var lastFetch = Date.distantPast
    private var failures = 0
    private var state = State.idle
    private var running = false

    public init(interval: TimeInterval = 60) { self.interval = interval }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            schedule(after: 0)
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false
            timer?.cancel()
            timer = nil
            publish(.idle)
        }
    }

    /// Reads again if the last read is older than `maxAge`.
    public func refresh(maxAge: TimeInterval = 30) {
        queue.async { [self] in
            guard running, Date().timeIntervalSince(lastFetch) > maxAge else { return }
            schedule(after: 0)
        }
    }

    private func schedule(after delay: TimeInterval) {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.fetch() }
        }
        timer.resume()
        self.timer = timer
    }

    private func fetch() async {
        guard let credentials = GitHubToken.resolve(allowCommandLine: allowCommandLine) else {
            queue.async { [self] in
                publish(.needsToken)
                if running { schedule(after: interval) }   // the user may connect later
            }
            return
        }
        do {
            let snapshot = try await client.fetch(token: credentials.token)
            queue.async { [self] in
                failures = 0
                lastFetch = Date()
                publish(.ready(snapshot, source: credentials.source))
                if running { schedule(after: interval) }
            }
        } catch {
            let github = error as? GitHubError ?? .failed(error.localizedDescription)
            queue.async { [self] in
                failures += 1
                lastFetch = Date()
                publish(.failed(github))
                // Back off while the network or the token is bad: 1, 2, 4… minutes, never above 10.
                if running { schedule(after: min(interval * pow(2, Double(failures - 1)), 600)) }
            }
        }
    }

    private func publish(_ new: State) {
        guard new != state else { return }
        state = new
        DispatchQueue.main.async { [onChange] in onChange?(new) }
    }
}

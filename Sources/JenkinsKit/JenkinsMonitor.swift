import Foundation

/// Keeps a live view of Jenkins. While something is building it polls every few seconds so the
/// progress moves; otherwise every half minute. When the server is unreachable (the VPN is off) it
/// backs off quietly and keeps the last results instead of raising errors.
// All mutable state is touched only on `queue`, which is what makes sharing the object safe.
public final class JenkinsMonitor: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case ready(JenkinsSnapshot)
        case failed(JenkinsError)
    }

    public var onChange: (@Sendable (State) -> Void)?

    private let client = JenkinsClient()
    private let queue = DispatchQueue(label: "notchhub.jenkins", qos: .utility)
    private var config: JenkinsConfig?
    private var timer: DispatchSourceTimer?
    private var failures = 0
    private var state = State.idle
    private var generation = 0     // bumps on every reconfigure so a stale response is ignored

    public init() {}

    /// Start (or restart) with new settings; nil stops.
    public func configure(_ new: JenkinsConfig?) {
        queue.async { [self] in
            guard new != config else { return }
            config = new
            generation += 1
            failures = 0
            timer?.cancel()
            timer = nil
            guard new != nil else { publish(.idle); return }
            schedule(after: 0)
        }
    }

    /// Read again if the last read is older than `maxAge`.
    public func refresh(maxAge: TimeInterval = 10) {
        queue.async { [self] in
            guard config != nil else { return }
            if case .ready(let snapshot) = state, Date().timeIntervalSince(snapshot.fetchedAt) < maxAge { return }
            schedule(after: 0)
        }
    }

    private func schedule(after delay: TimeInterval) {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self, let config = self.config else { return }
            let generation = self.generation
            Task { await self.fetch(config, generation: generation) }
        }
        timer.resume()
        self.timer = timer
    }

    private func fetch(_ config: JenkinsConfig, generation: Int) async {
        let result: Result<JenkinsSnapshot, JenkinsError>
        do { result = .success(try await client.fetch(config)) }
        catch { result = .failure(error as? JenkinsError ?? .failed(error.localizedDescription)) }

        queue.async { [self] in
            guard generation == self.generation else { return }
            switch result {
            case .success(let snapshot):
                failures = 0
                publish(.ready(snapshot))
                // Live progress while a build runs; relaxed otherwise.
                schedule(after: snapshot.running.isEmpty ? 30 : 5)
            case .failure(let error):
                failures += 1
                publish(.failed(error))
                // 15s, 30s, 60s… up to 5 minutes, so a closed VPN costs almost nothing.
                schedule(after: min(15 * pow(2, Double(failures - 1)), 300))
            }
        }
    }

    private func publish(_ new: State) {
        guard new != state else { return }
        state = new
        DispatchQueue.main.async { [onChange] in onChange?(new) }
    }
}

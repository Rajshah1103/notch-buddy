import Foundation
import WindowEngine

@MainActor
final class WindowsModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot.empty

    private let provider = SystemWindowProvider()

    func refresh() {
        let provider = provider
        Task.detached {
            let snapshot = provider.snapshot()
            await MainActor.run { self.snapshot = snapshot }
        }
    }

    func focus(_ window: WindowRecord, in space: SpaceInfo?) {
        let provider = provider
        Task { await provider.focus(window, in: space) }
    }

    func open(_ app: AppRecord) {
        provider.open(app)
    }
}

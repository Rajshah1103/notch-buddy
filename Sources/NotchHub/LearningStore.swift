import Foundation
import WindowEngine

/// Keeps what search has learned on this Mac (never sent anywhere), and applies it to ranking.
@MainActor
final class LearningStore: ObservableObject {
    private static let defaultsKey = "searchLearning"
    private var learning: SearchLearning
    private let settings: AppSettings

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
        learning = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(SearchLearning.self, from: $0) } ?? SearchLearning()
    }

    var isEmpty: Bool { learning.isEmpty }

    func boost(_ entry: Entry, appName: String, query: String) -> Double {
        guard settings.learnFromUse else { return 0 }
        return learning.boost(key: SearchLearning.key(for: entry, appName: appName), query: query)
    }

    /// Remember that `entry` was opened, after typing `query` (empty when it was opened from the app row).
    func record(_ entry: Entry, appName: String, query: String = "") {
        guard settings.learnFromUse else { return }
        // Opening something you did not search for is a weaker hint than choosing it from results.
        learning.record(key: SearchLearning.key(for: entry, appName: appName), query: query)
        save()
        objectWillChange.send()
    }

    func forgetEverything() {
        learning = SearchLearning()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        objectWillChange.send()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(learning) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }
}

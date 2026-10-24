import Foundation

/// Numbers and wording derived from a `UsageHistory`. Pure, so it is easy to test.
public struct UsageStats {
    public let history: UsageHistory
    private let today: Date
    private let calendar: Calendar

    public init(history: UsageHistory, now: Date = Date(), calendar: Calendar = .current) {
        self.history = history
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
    }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

    /// Tokens per day for the last `days` days, oldest first, today last. Quiet days are zero.
    public func series(days: Int) -> [Int] {
        (0..<days).map { history.daily[day(-(days - 1 - $0))] ?? 0 }
    }

    public func total(days: Int) -> Int { series(days: days).reduce(0, +) }

    public func average(days: Int) -> Int { days > 0 ? total(days: days) / days : 0 }

    /// How the last `days` compare with the `days` before them, as a fraction (0.25 = 25% more).
    /// Nil when there is nothing before to compare with.
    public func trend(days: Int) -> Double? {
        let before = (0..<days).reduce(0) { $0 + (history.daily[day(-days - $1)] ?? 0) }
        guard before > 0 else { return nil }
        return Double(total(days: days) - before) / Double(before)
    }

    public func busiest(days: Int) -> (date: Date, tokens: Int)? {
        (0..<days).map { (day(-$0), history.daily[day(-$0)] ?? 0) }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }
    }

    /// Days in a row, ending today (or yesterday, if today has not started), with any use.
    public var streak: Int {
        var count = 0
        var cursor = (history.daily[today] ?? 0) > 0 ? 0 : -1
        while (history.daily[day(cursor)] ?? 0) > 0 { count += 1; cursor -= 1 }
        return count
    }

    public var activeDays30: Int { series(days: 30).filter { $0 > 0 }.count }

    /// Where the month is heading: what is used so far plus the last two weeks' average for the days left.
    public var monthForecast: (projected: Int, soFar: Int, daysLeft: Int) {
        let components = calendar.dateComponents([.year, .month], from: today)
        let monthStart = calendar.date(from: components) ?? today
        let length = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        let elapsed = (calendar.dateComponents([.day], from: monthStart, to: today).day ?? 0) + 1
        let soFar = (0..<elapsed).reduce(0) { $0 + (history.daily[day(-$1)] ?? 0) }
        let left = max(0, length - elapsed)
        return (soFar + average(days: 14) * left, soFar, left)
    }

    /// The share of use (0...1) between two hours of day, wrapping past midnight when `from > to`.
    private func share(from: Int, to: Int) -> Double {
        let all = history.hours.reduce(0, +)
        guard all > 0 else { return 0 }
        let part = (0..<24).filter { from <= to ? ($0 >= from && $0 < to) : ($0 >= from || $0 < to) }.reduce(0) { $0 + history.hours[$1] }
        return Double(part) / Double(all)
    }

    private var weekendShare: Double {
        let all = total(days: 30)
        guard all > 0 else { return 0 }
        let weekend = (0..<30).map { day(-$0) }.filter { calendar.isDateInWeekend($0) }.reduce(0) { $0 + (history.daily[$1] ?? 0) }
        return Double(weekend) / Double(all)
    }

    /// The hour of day (0...23) with the most use, if there is any.
    public var peakHour: Int? {
        guard let peak = history.hours.max(), peak > 0 else { return nil }
        return history.hours.firstIndex(of: peak)
    }

    // MARK: - The banter

    public struct Persona: Equatable {
        public let name: String
        public let quip: String
    }

    /// A name for how you use Claude: a habit if one stands out, otherwise how much.
    public var persona: Persona {
        let perDay = average(days: 30)
        let tokens = TokenFormat.short(perDay)
        if total(days: 30) == 0 {
            return Persona(name: "The Quiet Type", quip: "No tokens in 30 days. Claude is starting to think you forgot it.")
        }
        if share(from: 22, to: 5) > 0.35 { return Persona(name: "The Midnight Prompter", quip: "A third of your tokens burn after 10pm. Sleep is a suggestion.") }
        if share(from: 5, to: 9) > 0.30 { return Persona(name: "Dawn Patrol Debugger", quip: "Prompting before breakfast. The bugs don't stand a chance.") }
        if weekendShare > 0.40 { return Persona(name: "Weekend Warrior", quip: "Your best prompts happen when everyone else is offline.") }
        if streak >= 14 { return Persona(name: "Never Skips a Day", quip: "\(streak) days in a row. Claude has started saving you a seat.") }
        if let change = trend(days: 30), change > 0.5 { return Persona(name: "Rocket Fuel", quip: "Up \(Int(change * 100))% on last month. Somebody found the good stuff.") }
        switch perDay {
        case ..<50_000: return Persona(name: "The Polite Prompter", quip: "\(tokens) a day. Please and thank you, in moderation.")
        case ..<500_000: return Persona(name: "Steady Collaborator", quip: "\(tokens) a day. A healthy working relationship.")
        case ..<2_000_000: return Persona(name: "Prompt Machine", quip: "\(tokens) a day. The keyboard is getting warm.")
        case ..<6_000_000: return Persona(name: "Token Furnace", quip: "\(tokens) a day. The GPUs know your name.")
        default: return Persona(name: "Token Tornado", quip: "\(tokens) a day. Somewhere, a data center just sighed.")
        }
    }
}

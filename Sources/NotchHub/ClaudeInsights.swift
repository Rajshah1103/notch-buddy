import ClaudeUsage
import SwiftUI

/// The right-hand card of the Claude panel: how much you use Claude, over 30 or 90 days, and a name for it.
struct Insights: View {
    @ObservedObject var model: ClaudeModel
    @State private var days = 30
    @State private var hoveredBar: Int?

    var body: some View {
        let stats = model.stats
        let series = stats.series(days: days)
        let persona = stats.persona

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(model.snapshot.isWorking ? "\(model.snapshot.working.count) working now" : "Idle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.snapshot.isWorking ? Theme.claude : Theme.textSecondary)
                Text("today \(TokenFormat.short(model.snapshot.tokensToday))")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                PeriodToggle(days: $days)
            }

            Text(persona.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.claude)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(persona.quip).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true).lineLimit(2)

            // The headline number follows the pointer over the bars: the day under it, else the period.
            let hovered = hoveredBar.flatMap { $0 < series.count ? $0 : nil }
            VStack(alignment: .leading, spacing: 0) {
                Text(TokenFormat.short(hovered.map { series[$0] } ?? stats.total(days: days)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                Text(hovered.map { dayLabel(stats, series.count, $0) } ?? "tokens in the last \(days) days")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 2)

            Bars(series: series, hovered: $hoveredBar).frame(height: 54)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Fact(title: "Daily average", value: TokenFormat.short(stats.average(days: days)))
                    Fact(title: "Busiest day", value: stats.busiest(days: days).map { TokenFormat.short($0.tokens) } ?? "none",
                         detail: stats.busiest(days: days).map { $0.date.formatted(.dateTime.month(.abbreviated).day()) })
                }
                GridRow {
                    Fact(title: "Streak", value: "\(stats.streak) day\(stats.streak == 1 ? "" : "s")")
                    trendFact(stats)
                }
            }

            let forecast = stats.monthForecast
            if forecast.daysLeft > 0, forecast.soFar > 0 {
                Label("On pace for \(TokenFormat.short(forecast.projected)) this month", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }
            if let peak = stats.peakHour {
                HourStrip(hours: stats.history.hours, peak: peak).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.fillQuiet))
        .accessibilityElement(children: .contain)
    }

    private func trendFact(_ stats: UsageStats) -> some View {
        let change = stats.trend(days: days)
        let text = change.map { "\($0 >= 0 ? "\u{2191}" : "\u{2193}") \(Int(abs($0) * 100))%" } ?? "new"
        return Fact(title: "vs previous \(days)d", value: text,
                    tint: change.map { $0 >= 0 ? Theme.claude : Color.green })
    }

    /// "Oct 12", for the bar at `index` of a series that ends today.
    private func dayLabel(_ stats: UsageStats, _ count: Int, _ index: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -(count - 1 - index), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let chats = model.stats.history.chats[date] ?? 0
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + (chats > 0 ? " \u{00B7} \(chats) chat\(chats == 1 ? "" : "s")" : "")
    }
}

private struct PeriodToggle: View {
    @Binding var days: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach([30, 90], id: \.self) { value in
                Button { days = value } label: {
                    Text("\(value)d").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).frame(height: 18)
                        .foregroundStyle(days == value ? Theme.textPrimary : Theme.textSecondary)
                        .background(Capsule().fill(days == value ? Theme.fillSelected : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.fillQuiet))
    }
}

/// One thin bar per day, today in Claude orange. Hovering a bar reports its index.
private struct Bars: View {
    let series: [Int]
    @Binding var hovered: Int?

    var body: some View {
        let peak = max(series.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: series.count > 45 ? 1 : 2) {
            ForEach(series.indices, id: \.self) { index in
                Bar(fraction: series[index] == 0 ? 0.03 : max(0.06, Double(series[index]) / Double(peak)),
                    isToday: index == series.count - 1, isHovered: hovered == index) { inside in
                    if inside { hovered = index } else if hovered == index { hovered = nil }
                }
            }
        }
    }
}

private struct Bar: View {
    let fraction: Double
    let isToday: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isToday || isHovered ? Theme.claude : Theme.claude.opacity(0.45))
                    .frame(height: max(2, proxy.size.height * fraction))
            }
        }
        .contentShape(Rectangle())
        .pointerHover(perform: onHover)
    }
}

private struct Fact: View {
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 4) {
                Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(tint ?? Theme.textPrimary)
                if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(Theme.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// When in the day you prompt: 24 small bars and the busiest hour in words.
private struct HourStrip: View {
    let hours: [Int]
    let peak: Int

    var body: some View {
        let top = Double(max(hours.max() ?? 1, 1))
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(hour == peak ? Theme.claude : Theme.claude.opacity(0.35))
                        .frame(height: max(2, 14 * Double(hours[hour]) / top))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 14, alignment: .bottom)
            Text("You prompt most around \(label(peak))").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func label(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }
}

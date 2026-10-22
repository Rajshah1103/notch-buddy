import Testing
@testable import WindowEngine

struct ColumnPackerTests {
    private func pack(_ items: [PackItem<Int>]) -> PackedColumns<Int> {
        ColumnPacker.pack(items, columnHeight: 336, headerCost: 28, rowCost: 40, maxColumns: 2)
    }

    @Test func splitGroupRepeatsItsHeadingInTheNextColumn() {
        let items: [PackItem<Int>] = [.header("Desktop 3")] + (0..<5).map { .entry($0) }
            + [.header("Desktop 4")] + (5..<9).map { .entry($0) }
        let packed = pack(items)
        #expect(packed.overflow == 0)
        #expect(packed.columns.count == 2)
        guard case .header(let title)? = packed.columns.last?.first else {
            Issue.record("second column should start with a heading")
            return
        }
        #expect(title.hasPrefix("Desktop"))
    }

    @Test func overflowIsCountedNotScrolled() {
        let items: [PackItem<Int>] = [.header("W")] + (0..<40).map { .entry($0) }
        let packed = pack(items)
        let shown = packed.columns.joined().filter { if case .entry = $0 { true } else { false } }.count
        #expect(packed.overflow > 0)
        #expect(shown + packed.overflow == 40)
    }
}
